// Web Audio engine: mixing, clip + note scheduling, metronome, offline rendering.

import * as model from './model.js';

const AHEAD = 0.3;
const TICK_MS = 25;
const SYNTH_WAVEFORM = 'sawtooth';
const SYNTH_CUTOFF = 6500;
const SYNTH_ATTACK = 0.02;
const SYNTH_RELEASE = 0.28;

export class StudioEngine {
  constructor() {
    this.ctx = null;
    this.masterGain = null;
    this.masterAnalyser = null;
    this.trackNodes = new Map();
    this.buffers = new Map();
    this.session = null;

    this.isPlaying = false;
    this.position = 0;
    this.anchorPos = 0;
    this.anchorCtx = 0;
    this.cursorPos = 0;
    this.cursorCtx = 0;
    this.timer = null;
    this.sources = new Set();
    this.oscillators = new Set();
  }

  ensureContext() {
    if (!this.ctx) {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      this.ctx = new Ctx();
      this.masterAnalyser = this.ctx.createAnalyser();
      this.masterAnalyser.fftSize = 1024;

      const chain = buildMasterChain(this.ctx, this.masterAnalyser, {
        masterVolume: this.session?.masterVolume ?? 1,
        effects: this.session?.masterEffects,
        tempo: this.session?.tempo ?? 120,
        includeEffects: true
      });
      this.masterGain = chain.input;
      this.masterChain = chain;
      this.masterAnalyser.connect(this.ctx.destination);

      this.clickBus = this.ctx.createGain();
      this.clickBus.connect(this.masterAnalyser);

      if (this.session) this.rebuild();
    }
    if (this.ctx.state === 'suspended') {
      this.ctx.resume().catch(() => {});
    }
    return this.ctx;
  }

  async decode(arrayBuffer) {
    this.ensureContext();
    return this.ctx.decodeAudioData(arrayBuffer);
  }

  setSession(session) {
    this.session = session;
    if (this.ctx) this.rebuild();
  }

  applyMasterEffects() {
    if (!this.session) return;
    applyMasterChain(this.masterChain, {
      effects: this.session.masterEffects,
      tempo: this.session.tempo
    });
  }

  duration() {
    return this.session ? model.sessionDuration(this.session) : 0;
  }

  activeLoop() {
    const loop = this.session?.loop;
    if (!loop || !loop.enabled) return null;
    if (loop.end - loop.start <= 0.05) return null;
    return loop;
  }

  rebuild() {
    if (!this.ctx || !this.session) return;
    const wanted = new Set(this.session.tracks.map((track) => track.id));

    for (const [id, nodes] of this.trackNodes) {
      if (!wanted.has(id)) {
        this.disposeTrackNodes(nodes);
        this.trackNodes.delete(id);
      }
    }

    for (const track of this.session.tracks) {
      let nodes = this.trackNodes.get(track.id);
      if (!nodes) {
        nodes = this.buildTrackNodes(track);
        this.trackNodes.set(track.id, nodes);
      }
      this.applyTrackSettings(track, nodes);
    }

    this.masterGain.gain.value = this.session.masterVolume;
    applyMasterChain(this.masterChain, {
      effects: this.session.masterEffects,
      tempo: this.session.tempo
    });
    this.updateMix(this.isPlaying ? this.getPosition() : this.position);
  }

  buildTrackNodes(track) {
    const ctx = this.ctx;
    const input = ctx.createGain();
    const pan = typeof ctx.createStereoPanner === 'function' ? ctx.createStereoPanner() : null;
    const low = ctx.createBiquadFilter();
    low.type = 'lowshelf';
    const mid = ctx.createBiquadFilter();
    mid.type = 'peaking';
    mid.Q.value = 1;
    const high = ctx.createBiquadFilter();
    high.type = 'highshelf';
    const comp = ctx.createDynamicsCompressor();
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 1024;

    let tail = input;
    if (pan) {
      tail.connect(pan);
      tail = pan;
    }
    tail.connect(low);
    low.connect(mid);
    mid.connect(high);
    high.connect(comp);
    comp.connect(analyser);
    analyser.connect(this.masterGain);

    return { input, pan, low, mid, high, comp, analyser, meterData: new Float32Array(analyser.fftSize) };
  }

  disposeTrackNodes(nodes) {
    try {
      nodes.input.disconnect();
      nodes.pan?.disconnect();
      nodes.low.disconnect();
      nodes.mid.disconnect();
      nodes.high.disconnect();
      nodes.comp.disconnect();
      nodes.analyser.disconnect();
    } catch (error) {
      // already disconnected
    }
  }

  applyTrackSettings(track, nodes) {
    const eq = track.eq || {};
    const frozen = Boolean(track.frozen?.fileId);
    const eqBypassed = Boolean(eq.bypassed) || frozen;

    nodes.low.frequency.value = eq.low?.frequency ?? 120;
    nodes.low.gain.value = eqBypassed ? 0 : (eq.low?.gain ?? 0);
    nodes.mid.frequency.value = eq.mid?.frequency ?? 1000;
    nodes.mid.gain.value = eqBypassed ? 0 : (eq.mid?.gain ?? 0);
    nodes.high.frequency.value = eq.high?.frequency ?? 8000;
    nodes.high.gain.value = eqBypassed ? 0 : (eq.high?.gain ?? 0);

    const comp = track.comp || {};
    if (frozen || comp.bypassed !== false) {
      nodes.comp.threshold.value = 0;
      nodes.comp.ratio.value = 1;
    } else {
      nodes.comp.threshold.value = comp.threshold ?? -18;
      nodes.comp.ratio.value = comp.ratio ?? 4;
      nodes.comp.attack.value = comp.attack ?? 0.01;
      nodes.comp.release.value = comp.release ?? 0.12;
    }

    if (nodes.pan) nodes.pan.pan.value = model.clamp(track.pan ?? 0, -1, 1);
  }

  updateMix(position) {
    if (!this.ctx || !this.session) return;
    const anySolo = this.session.tracks.some((track) => track.soloed);

    for (const track of this.session.tracks) {
      const nodes = this.trackNodes.get(track.id);
      if (!nodes) continue;
      const audible = !track.muted && (!anySolo || track.soloed);
      nodes.input.gain.value = audible ? track.volume * model.automationGain(track, position) : 0;
      if (nodes.pan) {
        const automatedPan = model.automationValue(track.panAutomation, position, 'pan');
        const pan = automatedPan === null ? (track.pan ?? 0) : automatedPan;
        nodes.pan.pan.value = model.clamp(pan, -1, 1);
      }
    }

    this.masterGain.gain.value = this.session.masterVolume;
  }

  getPosition() {
    if (!this.isPlaying || !this.ctx) return this.position;
    const elapsed = Math.max(0, this.ctx.currentTime - this.anchorCtx);
    const linear = this.anchorPos + elapsed;
    const loop = this.activeLoop();

    if (loop) {
      if (linear < loop.end) return Math.max(0, linear);
      const length = loop.end - loop.start;
      const overflow = (linear - loop.end) % length;
      return loop.start + overflow;
    }

    const duration = this.duration();
    return duration > 0 ? Math.min(duration, linear) : linear;
  }

  play(startPos) {
    this.ensureContext();
    if (!this.session || this.isPlaying) return;
    const duration = this.duration();
    if (duration <= 0) return;

    const requested = Number.isFinite(startPos) ? startPos : this.position;
    this.position = requested >= duration ? 0 : Math.max(0, requested);

    const now = this.ctx.currentTime + 0.08;
    this.anchorPos = this.position;
    this.anchorCtx = now;
    this.cursorPos = this.position;
    this.cursorCtx = now;
    this.isPlaying = true;
    this.updateMix(this.position);
    this.tick();
    this.timer = setInterval(() => this.tick(), TICK_MS);
  }

  pause() {
    if (!this.isPlaying) return;
    this.position = this.getPosition();
    this.isPlaying = false;
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    this.stopAll();
    this.updateMix(this.position);
  }

  stop() {
    this.pause();
    this.position = 0;
    this.updateMix(0);
  }

  seek(position) {
    const wasPlaying = this.isPlaying;
    if (wasPlaying) this.pause();
    const duration = this.duration();
    this.position = model.clamp(position, 0, duration > 0 ? duration : position);
    this.updateMix(this.position);
    if (wasPlaying) this.play(this.position);
  }

  stopAll() {
    for (const source of this.sources) {
      try { source.stop(); } catch (error) { /* stopped */ }
    }
    this.sources.clear();
    for (const osc of this.oscillators) {
      try { osc.stop(); } catch (error) { /* stopped */ }
    }
    this.oscillators.clear();
  }

  tick() {
    if (!this.isPlaying || !this.ctx || !this.session) return;
    const horizon = this.ctx.currentTime + AHEAD;
    let guard = 0;

    while (this.cursorCtx < horizon && guard < 300) {
      guard += 1;
      const loop = this.activeLoop();
      const endPos = loop ? loop.end : this.duration();

      if (this.cursorPos >= endPos - 1e-4) {
        if (loop && loop.end > loop.start) {
          this.cursorPos = loop.start;
          continue;
        }
        break;
      }

      const available = horizon - this.cursorCtx;
      const windowEnd = Math.min(endPos, this.cursorPos + available);
      if (windowEnd <= this.cursorPos) break;

      this.scheduleRange(this.cursorPos, windowEnd, this.cursorCtx);
      this.cursorCtx += windowEnd - this.cursorPos;
      this.cursorPos = windowEnd;
    }
  }

  scheduleRange(fromPos, toPos, atCtx) {
    if (!this.session) return;

    for (const track of this.session.tracks) {
      const nodes = this.trackNodes.get(track.id);
      if (!nodes) continue;

      for (const clip of model.playbackClips(track)) {
        const buffer = this.buffers.get(clip.fileId);
        if (!buffer) continue;

        const clipStart = Math.max(0, clip.start);
        const playable = Math.min(clip.duration, Math.max(0, clip.sourceDuration - clip.sourceStart));
        const clipEnd = clipStart + playable;
        const overlapStart = Math.max(fromPos, clipStart);
        const overlapEnd = Math.min(toPos, clipEnd);
        if (overlapEnd - overlapStart <= 1e-4) continue;

        const source = this.ctx.createBufferSource();
        source.buffer = buffer;
        source.connect(nodes.input);
        const offset = clip.sourceStart + (overlapStart - clipStart);
        const when = Math.max(this.ctx.currentTime, atCtx + (overlapStart - fromPos));
        try {
          source.start(when, offset, overlapEnd - overlapStart);
        } catch (error) {
          continue;
        }
        this.sources.add(source);
        source.onended = () => this.sources.delete(source);
      }

      for (const note of model.sequencedNotes(track)) {
        if (note.start < fromPos || note.start >= toPos) continue;
        const when = atCtx + (note.start - fromPos);
        this.scheduleNote(this.ctx, nodes.input, note, when);
      }
    }

    if (this.session.metronome.enabled) {
      this.scheduleClicks(fromPos, toPos, atCtx);
    }
  }

  scheduleNote(ctx, destination, note, when) {
    const duration = Math.max(0.08, note.duration);
    const start = Math.max(ctx.currentTime, when);
    const end = start + duration;

    const osc = ctx.createOscillator();
    osc.type = SYNTH_WAVEFORM;
    osc.frequency.value = model.noteFrequency(note.pitch);

    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = SYNTH_CUTOFF;

    const env = ctx.createGain();
    env.gain.setValueAtTime(0.0001, start);
    env.gain.exponentialRampToValueAtTime(0.18, start + Math.min(SYNTH_ATTACK, duration * 0.5));
    env.gain.setValueAtTime(0.18, Math.max(start + SYNTH_ATTACK + 0.001, end - SYNTH_RELEASE));
    env.gain.exponentialRampToValueAtTime(0.0001, end);

    osc.connect(filter);
    filter.connect(env);
    env.connect(destination);
    osc.start(start);
    osc.stop(end + 0.02);
    this.oscillators.add(osc);
    osc.onended = () => this.oscillators.delete(osc);
  }

  scheduleClicks(fromPos, toPos, atCtx) {
    const tempo = this.session?.tempo || 120;
    const beat = 60 / tempo;
    const level = this.session?.metronome?.level ?? 0.7;
    let index = Math.ceil(fromPos / beat - 1e-6);

    while (index * beat < toPos - 1e-6) {
      const when = Math.max(this.ctx.currentTime, atCtx + (index * beat - fromPos));
      this.scheduleClick(when, index % 4 === 0, level);
      index += 1;
    }
  }

  scheduleClick(when, accent, level) {
    const ctx = this.ensureContext();
    const osc = ctx.createOscillator();
    osc.type = 'square';
    osc.frequency.value = accent ? 1800 : 1200;

    const gain = ctx.createGain();
    const peak = model.clamp(level, 0, 1) * (accent ? 0.5 : 0.24);
    gain.gain.setValueAtTime(0.0001, when);
    gain.gain.exponentialRampToValueAtTime(Math.max(0.0002, peak), when + 0.003);
    gain.gain.exponentialRampToValueAtTime(0.0001, when + 0.055);

    osc.connect(gain);
    gain.connect(this.clickBus || this.masterGain);
    osc.start(when);
    osc.stop(when + 0.07);
    this.oscillators.add(osc);
    osc.onended = () => this.oscillators.delete(osc);
  }

  playCountIn(beats = 4) {
    this.ensureContext();
    const tempo = this.session?.tempo || 120;
    const beat = 60 / tempo;
    const start = this.ctx.currentTime + 0.12;
    const level = this.session?.metronome?.level ?? 0.7;

    for (let i = 0; i < beats; i += 1) {
      this.scheduleClick(start + i * beat, i % 4 === 0, level);
    }

    return beats * beat;
  }

  getTrackLevel(trackId) {
    const nodes = this.trackNodes.get(trackId);
    if (!nodes) return 0;
    nodes.analyser.getFloatTimeDomainData(nodes.meterData);
    let sum = 0;
    let count = 0;
    for (let i = 0; i < nodes.meterData.length; i += 4) {
      sum += nodes.meterData[i] * nodes.meterData[i];
      count += 1;
    }
    return Math.min(1, Math.sqrt(sum / Math.max(1, count)) * 3);
  }

  getMasterLevel() {
    if (!this.masterAnalyser) return 0;
    const data = new Float32Array(this.masterAnalyser.fftSize);
    this.masterAnalyser.getFloatTimeDomainData(data);
    let sum = 0;
    for (let i = 0; i < data.length; i += 4) sum += data[i] * data[i];
    return Math.min(1, Math.sqrt(sum / Math.max(1, data.length / 4)) * 3);
  }

  // ---------- Offline rendering ----------

  async renderMix({ masterVolume = 1, singleTrackId = null } = {}) {
    if (!this.session) throw new Error('There is no session to render.');
    const duration = this.duration();
    if (duration <= 0) throw new Error('There is nothing to render yet.');

    return this.renderOffline({
      duration,
      tracks: singleTrackId
        ? this.session.tracks.filter((track) => track.id === singleTrackId)
        : this.session.tracks,
      masterVolume,
      includeMixer: true,
      frozenSource: singleTrackId ? this.session.tracks.find((t) => t.id === singleTrackId)?.frozen?.fileId : null
    });
  }

  async renderTrackFreeze(track) {
    const duration = model.trackDuration(track);
    if (duration <= 0) throw new Error('This track has nothing to freeze yet.');
    return this.renderOffline({
      duration,
      tracks: [track],
      masterVolume: 1,
      includeMixer: false,
      forceSource: true
    });
  }

  async renderStem(track) {
    const duration = model.trackDuration(track);
    if (duration <= 0) throw new Error('This track has nothing to render.');
    return this.renderOffline({
      duration,
      tracks: [track],
      masterVolume: this.session?.masterVolume ?? 1,
      includeMixer: true,
      applyMuteSolo: false
    });
  }

  async renderOffline({ duration, tracks, masterVolume = 1, includeMixer = true, forceSource = false, frozenSource = null, applyMuteSolo = true }) {
    const sampleRate = 44100;
    const offline = new OfflineAudioContext(2, Math.ceil(duration * sampleRate) + 1024, sampleRate);

    const masterChain = buildMasterChain(offline, offline.destination, {
      masterVolume: includeMixer ? masterVolume : 1,
      effects: this.session?.masterEffects,
      tempo: this.session?.tempo ?? 120,
      includeEffects: includeMixer
    });
    const master = masterChain.input;

    const anySolo = this.session ? this.session.tracks.some((t) => t.soloed) : false;

    for (const track of tracks) {
      const input = this.buildOfflineTrack(offline, track, master, { includeMixer, anySolo, duration, applyMuteSolo });
      this.scheduleOfflineTrack(offline, track, input, duration, forceSource);
    }

    return offline.startRendering();
  }

  buildOfflineTrack(ctx, track, destination, { includeMixer, anySolo, duration, applyMuteSolo = true }) {
    const input = ctx.createGain();

    if (includeMixer) {
      const audible = !applyMuteSolo || (!track.muted && (!anySolo || track.soloed));
      const volume = audible ? track.volume : 0;
      input.gain.setValueAtTime(volume * model.automationGain(track, 0), 0);
      const step = 0.05;
      for (let time = step; time <= duration; time += step) {
        const value = volume * model.automationGain(track, time);
        input.gain.linearRampToValueAtTime(value, time);
      }
    } else {
      input.gain.value = 1;
    }

    const low = ctx.createBiquadFilter();
    low.type = 'lowshelf';
    const mid = ctx.createBiquadFilter();
    mid.type = 'peaking';
    mid.Q.value = 1;
    const high = ctx.createBiquadFilter();
    high.type = 'highshelf';
    const comp = ctx.createDynamicsCompressor();

    const frozen = !forceSource && Boolean(track.frozen?.fileId);
    const eq = track.eq || {};
    const eqBypassed = Boolean(eq.bypassed) || frozen;
    low.frequency.value = eq.low?.frequency ?? 120;
    low.gain.value = eqBypassed ? 0 : (eq.low?.gain ?? 0);
    mid.frequency.value = eq.mid?.frequency ?? 1000;
    mid.gain.value = eqBypassed ? 0 : (eq.mid?.gain ?? 0);
    high.frequency.value = eq.high?.frequency ?? 8000;
    high.gain.value = eqBypassed ? 0 : (eq.high?.gain ?? 0);

    const compSettings = track.comp || {};
    if (frozen || compSettings.bypassed !== false) {
      comp.threshold.value = 0;
      comp.ratio.value = 1;
    } else {
      comp.threshold.value = compSettings.threshold ?? -18;
      comp.ratio.value = compSettings.ratio ?? 4;
      comp.attack.value = compSettings.attack ?? 0.01;
      comp.release.value = compSettings.release ?? 0.12;
    }

    let tail = input;
    if (includeMixer && typeof ctx.createStereoPanner === 'function') {
      const panner = ctx.createStereoPanner();
      scheduleAutomatedPan(panner.pan, track, duration);
      tail.connect(panner);
      tail = panner;
    }

    tail.connect(low);
    low.connect(mid);
    mid.connect(high);
    high.connect(comp);
    comp.connect(destination);

    return input;
  }

  scheduleOfflineTrack(ctx, track, input, duration, forceSource) {
    const clips = forceSource ? track.clips : model.playbackClips(track);
    const notes = forceSource ? track.notes : model.sequencedNotes(track);

    for (const clip of clips) {
      const buffer = this.buffers.get(clip.fileId);
      if (!buffer) continue;
      const playable = Math.min(clip.duration, Math.max(0, clip.sourceDuration - clip.sourceStart));
      if (playable <= 0) continue;

      const source = ctx.createBufferSource();
      source.buffer = buffer;
      source.connect(input);
      try {
        source.start(Math.max(0, clip.start), clip.sourceStart, playable);
      } catch (error) {
        continue;
      }
    }

    for (const note of notes) {
      this.scheduleNote(ctx, input, note, Math.max(0, note.start));
    }
  }
}

function scheduleAutomatedPan(param, track, duration) {
  const panAt = (time) => {
    const automated = model.automationValue(track.panAutomation, time, 'pan');
    return model.clamp(automated === null ? (track.pan ?? 0) : automated, -1, 1);
  };

  param.setValueAtTime(panAt(0), 0);
  for (let time = 0.05; time <= duration; time += 0.05) {
    param.linearRampToValueAtTime(panAt(time), time);
  }
}

function makeImpulseResponse(ctx, decay) {
  const rate = ctx.sampleRate;
  const seconds = model.clamp(Number(decay) || 1.8, 0.2, 5);
  const length = Math.max(1, Math.floor(rate * seconds));
  const impulse = ctx.createBuffer(2, length, rate);

  for (let channel = 0; channel < 2; channel += 1) {
    const data = impulse.getChannelData(channel);
    for (let index = 0; index < length; index += 1) {
      data[index] = (Math.random() * 2 - 1) * Math.pow(1 - index / length, 2.2);
    }
  }

  return impulse;
}

function buildMasterChain(ctx, destination, { masterVolume = 1, effects, tempo = 120, includeEffects = true }) {
  const input = ctx.createGain();
  input.gain.value = masterVolume;

  const dry = ctx.createGain();
  input.connect(dry);
  dry.connect(destination);

  if (!includeEffects) {
    return { input, dry, reverb: null, revWet: null, delay: null, delayWet: null, feedback: null, impulseDecay: 0 };
  }

  const reverb = ctx.createConvolver();
  const revWet = ctx.createGain();
  const delay = ctx.createDelay(2);
  const feedback = ctx.createGain();
  const delayWet = ctx.createGain();

  input.connect(reverb);
  reverb.connect(revWet);
  revWet.connect(destination);

  input.connect(delay);
  delay.connect(feedback);
  feedback.connect(delay);
  delay.connect(delayWet);
  delayWet.connect(destination);

  const chain = { input, dry, reverb, revWet, delay, delayWet, feedback, impulseDecay: 0 };
  applyMasterChain(chain, { effects, tempo });
  return chain;
}

function applyMasterChain(chain, { effects, tempo }) {
  if (!chain || !chain.reverb) return;
  const settings = effects || { bypassed: true };
  const bypassed = settings.bypassed !== false;
  const tempoSafe = tempo || 120;
  const decay = model.clamp(Number(settings.reverbDecay ?? 1.8), 0.2, 5);

  if (chain.impulseDecay !== decay) {
    chain.impulseDecay = decay;
    try {
      chain.reverb.buffer = makeImpulseResponse(chain.reverb.context, decay);
    } catch (error) {
      // keep the previous impulse if the browser rejects the swap
    }
  }

  chain.revWet.gain.value = bypassed ? 0 : model.clamp(Number(settings.reverbMix ?? 0.32), 0, 1);
  chain.delayWet.gain.value = bypassed ? 0 : model.clamp(Number(settings.delayMix ?? 0.22), 0, 1);
  chain.feedback.gain.value = bypassed ? 0 : model.clamp(Number(settings.delayFeedback ?? 0.38), 0, 0.9);
  const beats = Number(settings.delayBeats ?? 0.5);
  chain.delay.delayTime.value = Math.min(2, Math.max(0.01, beats * 60 / tempoSafe));
}

export function encodeWav(buffer) {
  const channels = buffer.numberOfChannels;
  const sampleRate = buffer.sampleRate;
  const frames = buffer.length;
  const bytesPerSample = 2;
  const blockAlign = channels * bytesPerSample;
  const dataSize = frames * blockAlign;
  const arrayBuffer = new ArrayBuffer(44 + dataSize);
  const view = new DataView(arrayBuffer);

  const writeString = (offset, text) => {
    for (let i = 0; i < text.length; i += 1) {
      view.setUint8(offset + i, text.charCodeAt(i));
    }
  };

  writeString(0, 'RIFF');
  view.setUint32(4, 36 + dataSize, true);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, channels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * blockAlign, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, 16, true);
  writeString(36, 'data');
  view.setUint32(40, dataSize, true);

  const channelData = [];
  for (let channel = 0; channel < channels; channel += 1) {
    channelData.push(buffer.getChannelData(channel));
  }

  let offset = 44;
  for (let frame = 0; frame < frames; frame += 1) {
    for (let channel = 0; channel < channels; channel += 1) {
      const sample = Math.max(-1, Math.min(1, channelData[channel][frame]));
      view.setInt16(offset, sample < 0 ? sample * 0x8000 : sample * 0x7fff, true);
      offset += 2;
    }
  }

  return new Blob([arrayBuffer], { type: 'audio/wav' });
}
