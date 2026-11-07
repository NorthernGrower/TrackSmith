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
    this.groups = [];
    this.transformedClipBuffers = new Map();

    this.isPlaying = false;
    this.position = 0;
    this.anchorPos = 0;
    this.anchorCtx = 0;
    this.cursorPos = 0;
    this.cursorCtx = 0;
    this.timer = null;
    this.sources = new Set();
    this.oscillators = new Set();
    this.liveMIDINotes = new Set();
    this.sequencedDrumNodes = new Set();
    this.drumHitScheduler = null;

    this.kWeightAnalyser = null;
    this.loudnessBlockSum = 0;
    this.loudnessBlockReads = 0;
    this.loudnessBlockStartedAt = 0;
    this.loudnessBlocks = [];
    this.loudnessPeak = 0;
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
        includeEffects: true,
        mastering: this.session?.mastering
      });
      this.masterGain = chain.input;
      this.masterChain = chain;
      this.masterAnalyser.connect(this.ctx.destination);

      // K-weighting branch used by the loudness meters.
      this.kWeightAnalyser = this.ctx.createAnalyser();
      this.kWeightAnalyser.fftSize = 2048;
      const kShelf = this.ctx.createBiquadFilter();
      kShelf.type = 'highshelf';
      kShelf.frequency.value = 1681.97;
      kShelf.gain.value = 4;
      const kHighPass = this.ctx.createBiquadFilter();
      kHighPass.type = 'highpass';
      kHighPass.frequency.value = 38.14;
      kHighPass.Q.value = 0.5;
      this.masterAnalyser.connect(kShelf);
      kShelf.connect(kHighPass);
      kHighPass.connect(this.kWeightAnalyser);

      this.auxChain = buildAuxChain(this.ctx, this.masterGain);
      applyAuxBusSettings(this.auxChain, this.session?.auxA, this.session?.auxB, this.session?.tempo ?? 120);

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
    this.groups = session?.groups || [];
    if (this.ctx) this.rebuild();
  }

  setDrumHitScheduler(scheduler) {
    this.drumHitScheduler = typeof scheduler === 'function' ? scheduler : null;
  }

  updateGroups(groups) {
    this.groups = Array.isArray(groups) ? groups : [];
    if (this.session) this.session.groups = this.groups;
    this.updateMix(this.isPlaying ? this.getPosition() : this.position);
  }

  applyMasterEffects() {
    if (!this.session) return;
    applyMasterChain(this.masterChain, {
      effects: this.session.masterEffects,
      tempo: this.session.tempo,
      mastering: this.session.mastering
    });
    this.applyAuxBuses();
  }

  /// Applies the master EQ, bus compressor and limiter.
  applyMastering() {
    if (!this.session) return;
    applyMastering(this.masterChain, this.session.mastering);
  }

  /// Measures the master output for the loudness meters.
  readLoudness() {
    if (!this.ctx || !this.kWeightAnalyser || !this.masterAnalyser) return emptyLoudness();
    if (!this.isPlaying) return this.loudnessSnapshot();

    const weighted = new Float32Array(this.kWeightAnalyser.fftSize);
    this.kWeightAnalyser.getFloatTimeDomainData(weighted);
    const raw = new Float32Array(this.masterAnalyser.fftSize);
    this.masterAnalyser.getFloatTimeDomainData(raw);

    let sum = 0;
    for (let i = 0; i < weighted.length; i += 1) sum += weighted[i] * weighted[i];
    let peak = 0;
    for (let i = 0; i < raw.length; i += 1) {
      const value = Math.abs(raw[i]);
      if (value > peak) peak = Math.abs(value);
    }

    const now = this.ctx.currentTime;
    if (!this.loudnessBlockStartedAt) this.loudnessBlockStartedAt = now;
    this.loudnessBlockSum += sum / Math.max(1, weighted.length);
    this.loudnessBlockReads += 1;
    this.loudnessPeak = Math.max(this.loudnessPeak, peak);

    if (now - this.loudnessBlockStartedAt >= 0.4) {
      this.loudnessBlocks.push(this.loudnessBlockSum / Math.max(1, this.loudnessBlockReads));
      if (this.loudnessBlocks.length > 4500) this.loudnessBlocks.shift();
      this.loudnessBlockSum = 0;
      this.loudnessBlockReads = 0;
      this.loudnessBlockStartedAt = now;
    }

    return this.loudnessSnapshot();
  }

  loudnessSnapshot() {
    const blocks = this.loudnessBlocks;
    const absoluteGate = Math.pow(10, (-70 + 0.691) / 10);
    const gated = blocks.filter((value) => value >= absoluteGate);
    let integrated = null;
    if (gated.length) {
      const ungatedMean = gated.reduce((sum, value) => sum + value, 0) / gated.length;
      const relativeGate = ungatedMean * Math.pow(10, -10 / 10);
      const above = gated.filter((value) => value >= relativeGate);
      const mean = above.length
        ? above.reduce((sum, value) => sum + value, 0) / above.length
        : ungatedMean;
      integrated = -0.691 + 10 * Math.log10(Math.max(1e-12, mean));
    }

    const recent = blocks.slice(-8);
    let shortTerm = null;
    if (recent.length) {
      const mean = recent.reduce((sum, value) => sum + value, 0) / recent.length;
      shortTerm = -0.691 + 10 * Math.log10(Math.max(1e-12, mean));
    }

    const truePeak = this.loudnessPeak > 0 ? 20 * Math.log10(this.loudnessPeak) : null;
    return { integrated, shortTerm, truePeak, seconds: 0 };
  }

  resetLoudness() {
    this.loudnessBlockSum = 0;
    this.loudnessBlockReads = 0;
    this.loudnessBlockStartedAt = 0;
    this.loudnessBlocks = [];
    this.loudnessPeak = 0;
  }

  /// Applies both send buses' effects, return levels and delay time.
  applyAuxBuses() {
    if (!this.session) return;
    applyAuxBusSettings(this.auxChain, this.session.auxA, this.session.auxB, this.session.tempo);
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
    if (!this.noteCache) this.noteCache = new Map();
    this.noteCache.clear();
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
      tempo: this.session.tempo,
      mastering: this.session.mastering
    });
    applyAuxBusSettings(this.auxChain, this.session.auxA, this.session.auxB, this.session.tempo);
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
    const effects = buildTrackEffects(ctx, comp);
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 1024;
    const sendA = ctx.createGain();
    const sendB = ctx.createGain();

    let tail = input;
    if (pan) {
      tail.connect(pan);
      tail = pan;
    }
    tail.connect(low);
    low.connect(mid);
    mid.connect(high);
    high.connect(comp);
    effects.output.connect(analyser);
    analyser.connect(this.masterGain);

    if (this.auxChain) {
      effects.output.connect(sendA);
      sendA.connect(this.auxChain.aInput);
      effects.output.connect(sendB);
      sendB.connect(this.auxChain.bInput);
    }

    return { input, pan, low, mid, high, comp, effects, analyser, sendA, sendB, meterData: new Float32Array(analyser.fftSize) };
  }

  notesForTrack(track) {
    if (!this.session) return [];
    if (!this.noteCache) this.noteCache = new Map();
    if (this.noteCache.has(track.id)) return this.noteCache.get(track.id);
    const notes = model.playedNotes(track, this.session.tempo ?? 120);
    this.noteCache.set(track.id, notes);
    return notes;
  }

  disposeTrackNodes(nodes) {
    try {
      nodes.input.disconnect();
      nodes.pan?.disconnect();
      nodes.low.disconnect();
      nodes.mid.disconnect();
      nodes.high.disconnect();
      nodes.comp.disconnect();
      Object.values(nodes.effects || {}).forEach((node) => {
        try { node.disconnect(); } catch (error) { /* already disconnected */ }
      });
      try { nodes.effects?.chorusLFO?.stop(); } catch (error) { /* already stopped */ }
      nodes.analyser.disconnect();
      nodes.sendA?.disconnect();
      nodes.sendB?.disconnect();
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
    applyTrackEffects(track, nodes.effects, this.session?.tempo ?? 120, this.isPlaying ? this.getPosition() : this.position, frozen);
  }

  updateMix(position) {
    if (!this.ctx || !this.session) return;
    const groups = this.groups || [];
    const mutedTrackIDs = new Set(groups.filter((group) => group.muted).flatMap((group) => group.trackIDs));
    const soloedTrackIDs = new Set(groups.filter((group) => group.soloed).flatMap((group) => group.trackIDs));
    const anySolo = this.session.tracks.some((track) => track.soloed || soloedTrackIDs.has(track.id));

    for (const track of this.session.tracks) {
      const nodes = this.trackNodes.get(track.id);
      if (!nodes) continue;
      const group = groups.find((item) => item.trackIDs.includes(track.id));
      const audible = !(track.muted || mutedTrackIDs.has(track.id))
        && (!anySolo || track.soloed || soloedTrackIDs.has(track.id));
      nodes.input.gain.value = audible
        ? track.volume * (group ? group.volume : 1) * model.automationGain(track, position)
        : 0;
      // Sends are post-fader: they follow the track level and drop out when it is muted.
      nodes.sendA.gain.value = audible ? model.clamp(Number(track.sendA ?? 0), 0, 1) : 0;
      nodes.sendB.gain.value = audible ? model.clamp(Number(track.sendB ?? 0), 0, 1) : 0;
      if (nodes.pan) {
        const automatedPan = model.automationValue(track.panAutomation, position, 'pan');
        const pan = automatedPan === null ? (track.pan ?? 0) : automatedPan;
        nodes.pan.pan.value = model.clamp(pan, -1, 1);
      }
      applyTrackEffects(track, nodes.effects, this.session.tempo ?? 120, position, Boolean(track.frozen?.fileId));
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
    this.resetLoudness();
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
    for (const handle of this.liveMIDINotes) handle.stop();
    this.liveMIDINotes.clear();
    for (const source of this.sources) {
      try { source.stop(); } catch (error) { /* stopped */ }
    }
    this.sources.clear();
    for (const osc of this.oscillators) {
      try { osc.stop(); } catch (error) { /* stopped */ }
    }
    this.oscillators.clear();
    for (const node of this.sequencedDrumNodes) {
      try { node.stop(); } catch (error) { /* stopped */ }
    }
    this.sequencedDrumNodes.clear();
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

  clipBuffer(clip, sourceBuffer, context = this.ctx) {
    const tempo = this.session?.tempo ?? 120;
    const rate = model.clipPlaybackRate(clip, tempo);
    const transpose = model.clamp(Math.round(Number(clip.transposeSemitones) || 0), -12, 12);
    if (transpose === 0 && Math.abs(rate - 1) < 1e-6) return sourceBuffer;

    const key = `${clip.fileId}:${Math.round(tempo)}:${clip.sourceTempoBPM ?? 'natural'}:${transpose}`;
    if (this.transformedClipBuffers.has(key)) return this.transformedClipBuffers.get(key);
    const transformed = transformClipBuffer(context, sourceBuffer, transpose, rate);
    if (this.transformedClipBuffers.size >= 24) {
      this.transformedClipBuffers.delete(this.transformedClipBuffers.keys().next().value);
    }
    this.transformedClipBuffers.set(key, transformed);
    return transformed;
  }

  scheduleRange(fromPos, toPos, atCtx) {
    if (!this.session) return;

    for (const track of this.session.tracks) {
      const nodes = this.trackNodes.get(track.id);
      if (!nodes) continue;

      for (const clip of model.playbackClips(track)) {
        const sourceBuffer = this.buffers.get(clip.fileId);
        if (!sourceBuffer) continue;
        const tempo = this.session.tempo ?? 120;
        const buffer = this.clipBuffer(clip, sourceBuffer, this.ctx);

        const clipStart = Math.max(0, clip.start);
        const playable = model.clipTimelineDuration(clip, tempo);
        const clipEnd = clipStart + playable;
        const overlapStart = Math.max(fromPos, clipStart);
        const overlapEnd = Math.min(toPos, clipEnd);
        if (overlapEnd - overlapStart <= 1e-4) continue;

        const source = this.ctx.createBufferSource();
        source.buffer = buffer;
        const fadeGain = this.ctx.createGain();
        const clipStartAbs = clipStart;
        const gainAt = (time) => model.clipGainAt(clip, track, time, tempo);
        const startGain = gainAt(overlapStart);
        fadeGain.gain.setValueAtTime(startGain, Math.max(this.ctx.currentTime, atCtx + (overlapStart - fromPos)));
        const fadeInEnd = clipStartAbs + Math.max(0, Number(clip.fadeIn) || 0);
        const fadeOutStart = clipEnd - Math.max(0, Number(clip.fadeOut) || 0);
        if (fadeInEnd > overlapStart && fadeInEnd < overlapEnd) {
          fadeGain.gain.linearRampToValueAtTime(gainAt(fadeInEnd), Math.max(this.ctx.currentTime, atCtx + (fadeInEnd - fromPos)));
        }
        if (fadeOutStart > overlapStart && fadeOutStart < overlapEnd) {
          fadeGain.gain.linearRampToValueAtTime(gainAt(fadeOutStart), Math.max(this.ctx.currentTime, atCtx + (fadeOutStart - fromPos)));
        }
        fadeGain.gain.linearRampToValueAtTime(gainAt(overlapEnd), Math.max(this.ctx.currentTime, atCtx + (overlapEnd - fromPos)));
        source.connect(fadeGain);
        fadeGain.connect(nodes.input);
        const playbackRate = model.clipPlaybackRate(clip, tempo);
        const offset = clip.sourceStart / playbackRate + (overlapStart - clipStart);
        const segmentDuration = Math.min(overlapEnd - overlapStart, buffer.duration - offset);
        const when = Math.max(this.ctx.currentTime, atCtx + (overlapStart - fromPos));
        if (segmentDuration <= 1e-4) continue;
        try {
          source.start(when, offset, segmentDuration);
        } catch (error) {
          continue;
        }
        this.sources.add(source);
        source.onended = () => this.sources.delete(source);
      }

      for (const note of this.notesForTrack(track)) {
        if (note.start < fromPos || note.start >= toPos) continue;
        const when = atCtx + (note.start - fromPos);
        this.scheduleNote(this.ctx, nodes.input, note, when, model.presetForTrack(track), track.guitarTone);
      }
    }

    this.scheduleDrumPattern(fromPos, toPos, atCtx);

    if (this.session.metronome.enabled) {
      this.scheduleClicks(fromPos, toPos, atCtx);
    }
  }

  scheduleDrumPattern(fromPos, toPos, atCtx) {
    const pattern = this.session?.drumPattern;
    if (!pattern || !this.drumHitScheduler || !this.ctx || toPos <= fromPos) return;

    const stepDuration = 60 / (this.session.tempo || 120) / 4;
    const firstStep = Math.max(0, Math.ceil((fromPos - 1e-6) / stepDuration));
    for (let absoluteStep = firstStep; ; absoluteStep += 1) {
      const stepTime = absoluteStep * stepDuration;
      if (stepTime >= toPos - 1e-6) break;

      const step = absoluteStep % 16;
      for (const [voice, steps] of Object.entries(pattern)) {
        if (!Array.isArray(steps) || !steps[step]) continue;
        const when = Math.max(this.ctx.currentTime, atCtx + (stepTime - fromPos));
        const nodes = this.drumHitScheduler(voice, when);
        if (Array.isArray(nodes)) {
          for (const node of nodes) {
            if (!node || typeof node.stop !== 'function') continue;
            this.sequencedDrumNodes.add(node);
            const onended = node.onended;
            node.onended = (event) => {
              this.sequencedDrumNodes.delete(node);
              if (typeof onended === 'function') onended.call(node, event);
            };
          }
        }
      }
    }
  }

  scheduleNote(ctx, destination, note, when, preset, tone) {
    const resolved = preset || model.defaultPresetFor('synth');
    const start = Math.max(ctx.currentTime, when);
    const duration = Math.max(0.08, note.duration);
    const frequency = model.noteFrequency(note.pitch);
    const velocity = model.clamp(Number(note.velocity ?? 0.8), 0.05, 1);

    switch (resolved.voice) {
      case 'piano':
      case 'percussion':
        return this.scheduleStruckNote(ctx, destination, frequency, start, duration, velocity, resolved);
      case 'organ':
        return this.scheduleOrganNote(ctx, destination, frequency, start, duration, velocity, resolved);
      case 'strings':
        return this.scheduleStringNote(ctx, destination, frequency, start, duration, velocity, resolved);
      case 'acousticGuitar':
      case 'electricGuitar':
      case 'distortedGuitar':
      case 'bassGuitar':
        return this.schedulePluckedNote(ctx, destination, frequency, start, duration, velocity, resolved, tone);
      case 'marleneVocal':
        return this.scheduleVocalNote(ctx, destination, frequency, start, duration, velocity, resolved);
      default:
        return this.scheduleSynthNote(ctx, destination, frequency, start, duration, velocity, resolved);
    }
  }

  startMIDINote(trackId, pitch, velocity, destination) {
    const track = this.session?.tracks.find((item) => item.id === trackId);
    if (!track || !destination) return null;
    const preset = model.presetForTrack(track);
    const note = {
      pitch: Number(pitch),
      velocity: model.clamp(Number(velocity), 0.05, 1),
      duration: 120
    };
    const handle = this.scheduleNote(
      this.ensureContext(),
      destination,
      note,
      this.ctx.currentTime + 0.01,
      preset,
      track.guitarTone
    );
    if (handle) this.liveMIDINotes.add(handle);
    return handle;
  }

  releaseMIDINote(handle) {
    handle?.release?.();
  }

  trackOscillator(osc) {
    this.oscillators.add(osc);
    osc.onended = () => this.oscillators.delete(osc);
  }

  createNoteHandle(ctx, sources, envelopes, releaseSeconds) {
    let released = false;
    const handle = {
      release: () => {
        if (released) return;
        released = true;
        const now = ctx.currentTime;
        const releaseTime = Math.max(0.02, Number(releaseSeconds) || 0.2);
        const end = now + releaseTime;
        for (const envelope of envelopes) {
          const parameter = envelope.gain;
          if (typeof parameter.cancelAndHoldAtTime === 'function') {
            parameter.cancelAndHoldAtTime(now);
          } else {
            const current = Math.max(0.0001, parameter.value);
            parameter.cancelScheduledValues(now);
            parameter.setValueAtTime(current, now);
          }
          parameter.exponentialRampToValueAtTime(0.0001, end);
        }
        for (const source of sources) {
          try { source.stop(end + 0.03); } catch (error) { /* already stopped */ }
        }
      },
      stop: () => {
        if (released) return;
        released = true;
        for (const source of sources) {
          try { source.stop(); } catch (error) { /* already stopped */ }
        }
      }
    };

    const remaining = new Set(sources);
    for (const source of sources) {
      const previousOnEnded = source.onended;
      source.onended = (event) => {
        remaining.delete(source);
        if (typeof previousOnEnded === 'function') previousOnEnded.call(source, event);
        if (remaining.size === 0) this.liveMIDINotes.delete(handle);
      };
    }
    return handle;
  }

  scheduleSynthNote(ctx, destination, frequency, start, duration, velocity, preset) {
    const release = Math.max(0.02, preset.release);
    const attack = Math.max(0.005, preset.attack);
    const end = start + duration + release;

    const osc = ctx.createOscillator();
    osc.type = preset.waveform || 'sawtooth';
    osc.frequency.value = frequency;

    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = model.clamp(preset.brightness, 120, ctx.sampleRate * 0.45);

    const env = ctx.createGain();
    const peak = Math.max(0.0002, 0.18 * velocity * model.clamp(preset.level, 0.2, 1.4));
    env.gain.setValueAtTime(0.0001, start);
    env.gain.exponentialRampToValueAtTime(peak, start + Math.min(attack, duration * 0.5));
    env.gain.setValueAtTime(peak, Math.max(start + attack + 0.001, end - release));
    env.gain.exponentialRampToValueAtTime(0.0001, end);

    osc.connect(filter);
    filter.connect(env);
    env.connect(destination);
    osc.start(start);
    osc.stop(end + 0.02);
    this.trackOscillator(osc);
    return this.createNoteHandle(ctx, [osc], [env], release);
  }

  /// Piano and tuned percussion: a small stack of partials, each decaying.
  scheduleStruckNote(ctx, destination, frequency, start, duration, velocity, preset) {
    const partials = preset.voice === 'percussion'
      ? [[1, 1, 0.42], [4, 0.3, 0.22], [10, 0.08, 0.12]]
      : [[1, 1, 0.9], [2, 0.42, 0.62], [3, 0.22, 0.46], [4, 0.12, 0.34], [6, 0.06, 0.24]];
    const sustain = model.clamp(preset.sustain, 0.25, 2.5);
    const level = model.clamp(preset.level, 0.2, 1.4) * velocity;
    const attack = Math.max(0.002, preset.attack);
    const release = Math.max(0.05, preset.release);
    const gainSum = partials.reduce((sum, partial) => sum + partial[1], 0) || 1;
    const normal = 0.34 / gainSum;
    const sources = [];
    const envelopes = [];

    partials.forEach(([ratio, gain, decay]) => {
      const ring = Math.max(0.12, decay * sustain + Math.min(duration, 2) * 0.3);
      const end = start + Math.max(duration, ring) + release;
      const osc = ctx.createOscillator();
      osc.type = 'sine';
      osc.frequency.value = frequency * ratio;

      const env = ctx.createGain();
      const peak = Math.max(0.0002, normal * gain * level);
      env.gain.setValueAtTime(0.0001, start);
      env.gain.exponentialRampToValueAtTime(peak, start + attack);
      env.gain.exponentialRampToValueAtTime(0.0001, start + ring);

      osc.connect(env);
      env.connect(destination);
      osc.start(start);
      osc.stop(end);
      this.trackOscillator(osc);
      sources.push(osc);
      envelopes.push(env);
    });
    return this.createNoteHandle(ctx, sources, envelopes, release);
  }

  /// Drawbar organ: stacked sines held for the note, then released.
  scheduleOrganNote(ctx, destination, frequency, start, duration, velocity, preset) {
    const mix = model.clamp(preset.harmonic, 0, 1);
    const drawbars = [[1, 1], [2, 0.5 + 0.5 * mix], [3, 0.28 * mix], [4, 0.2 * mix], [6, 0.12 * mix]];
    const gainSum = drawbars.reduce((sum, bar) => sum + bar[1], 0) || 1;
    const normal = 0.5 / gainSum;
    const level = model.clamp(preset.level, 0.2, 1.4) * velocity;
    const attack = Math.max(0.004, preset.attack);
    const release = Math.max(0.02, preset.release);
    const end = start + duration;
    const holdEnd = Math.max(start + attack + 0.001, end - release);
    const sources = [];
    const envelopes = [];

    drawbars.forEach(([ratio, gain]) => {
      const osc = ctx.createOscillator();
      osc.type = 'sine';
      osc.frequency.value = frequency * ratio;

      const env = ctx.createGain();
      const peak = Math.max(0.0002, normal * gain * level);
      env.gain.setValueAtTime(0.0001, start);
      env.gain.exponentialRampToValueAtTime(peak, start + attack);
      env.gain.setValueAtTime(peak, holdEnd);
      env.gain.exponentialRampToValueAtTime(0.0001, end + release);

      osc.connect(env);
      env.connect(destination);
      osc.start(start);
      osc.stop(end + release + 0.02);
      this.trackOscillator(osc);
      sources.push(osc);
      envelopes.push(env);
    });
    return this.createNoteHandle(ctx, sources, envelopes, release);
  }

  /// Bowed strings: three detuned saws through a low-pass with a slow attack.
  scheduleStringNote(ctx, destination, frequency, start, duration, velocity, preset) {
    const level = model.clamp(preset.level, 0.2, 1.4) * velocity;
    const attack = Math.max(0.01, Math.min(preset.attack, duration * 0.6));
    const release = Math.max(0.02, Math.min(preset.release, 0.9));
    const end = start + duration;
    const holdEnd = Math.max(start + attack + 0.001, end - release);

    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = model.clamp(preset.brightness, 200, ctx.sampleRate * 0.4);

    const env = ctx.createGain();
    const peak = Math.max(0.0002, 0.16 * level);
    env.gain.setValueAtTime(0.0001, start);
    env.gain.exponentialRampToValueAtTime(peak, start + attack);
    env.gain.setValueAtTime(peak, holdEnd);
    env.gain.exponentialRampToValueAtTime(0.0001, end + release);

    filter.connect(env);
    env.connect(destination);
    const sources = [];

    [-4, 0, 4].forEach((cents) => {
      const osc = ctx.createOscillator();
      osc.type = 'sawtooth';
      osc.frequency.value = frequency;
      osc.detune.value = cents;
      osc.connect(filter);
      osc.start(start);
      osc.stop(end + release + 0.02);
      this.trackOscillator(osc);
      sources.push(osc);
    });
    return this.createNoteHandle(ctx, sources, [env], release);
  }

  /// Plucked strings: a short filtered tone that decays like a picked string.
  schedulePluckedNote(ctx, destination, frequency, start, duration, velocity, preset, tone) {
    const safeTone = model.normalizeGuitarTone(tone);
    const toneScale = (0.5 + safeTone.brightness) * (0.7 + 0.6 * safeTone.pickup);
    const drive = 0.7 + safeTone.gain * 2.6;
    const driveCompensation = 1 / (0.85 + safeTone.gain * 0.6);
    const level = model.clamp(preset.level, 0.2, 1.4) * velocity;
    const ring = model.clamp(0.5 * preset.sustain + Math.min(duration, 2) * 0.4, 0.2, 2.4);
    const end = start + Math.max(duration, ring);

    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = model.clamp(preset.brightness * toneScale, 200, ctx.sampleRate * 0.4);

    const shaper = ctx.createWaveShaper();
    shaper.curve = this.makeDriveCurve(drive);

    const env = ctx.createGain();
    const peak = Math.max(0.0002, 0.2 * level * driveCompensation);
    env.gain.setValueAtTime(0.0001, start);
    env.gain.exponentialRampToValueAtTime(peak, start + 0.004);
    env.gain.exponentialRampToValueAtTime(0.0001, start + ring);

    filter.connect(shaper);
    shaper.connect(env);
    env.connect(destination);

    const sources = [];
    [[1, 1], [2, 0.3]].forEach(([ratio, gain]) => {
      const osc = ctx.createOscillator();
      osc.type = 'triangle';
      osc.frequency.value = frequency * ratio;
      const partialGain = ctx.createGain();
      partialGain.gain.value = gain;
      osc.connect(partialGain);
      partialGain.connect(filter);
      osc.start(start);
      osc.stop(end + 0.05);
      this.trackOscillator(osc);
      sources.push(osc);
    });
    return this.createNoteHandle(ctx, sources, [env], Math.max(0.05, preset.release));
  }

  /// A soft saturation curve for the guitar amp's drive, 0.7 (clean) to 3.3.
  makeDriveCurve(amount) {
    const samples = 1024;
    const curve = new Float32Array(samples);
    const k = Math.max(0.001, amount);
    for (let index = 0; index < samples; index += 1) {
      const x = (index / (samples - 1)) * 2 - 1;
      curve[index] = Math.tanh(k * x) / Math.tanh(k);
    }
    return curve;
  }

  /// Sung vowel: a saw through two formant filters.
  scheduleVocalNote(ctx, destination, frequency, start, duration, velocity, preset) {
    const level = model.clamp(preset.level, 0.2, 1.4) * velocity;
    const attack = Math.max(0.01, Math.min(preset.attack, duration * 0.3));
    const release = Math.max(0.02, Math.min(preset.release, 0.6));
    const end = start + duration;
    const holdEnd = Math.max(start + attack + 0.001, end - release);
    const tilt = model.clamp(preset.brightness / 2600, 0.6, 1.4);

    const osc = ctx.createOscillator();
    osc.type = 'sawtooth';
    osc.frequency.value = frequency;

    const formantOne = ctx.createBiquadFilter();
    formantOne.type = 'bandpass';
    formantOne.frequency.value = 880 * tilt;
    formantOne.Q.value = 6;

    const formantTwo = ctx.createBiquadFilter();
    formantTwo.type = 'bandpass';
    formantTwo.frequency.value = 1260 * tilt;
    formantTwo.Q.value = 8;

    const formantGain = ctx.createGain();
    formantGain.gain.value = 0.6;

    const env = ctx.createGain();
    const peak = Math.max(0.0002, 0.34 * level);
    env.gain.setValueAtTime(0.0001, start);
    env.gain.exponentialRampToValueAtTime(peak, start + attack);
    env.gain.setValueAtTime(peak, holdEnd);
    env.gain.exponentialRampToValueAtTime(0.0001, end + release);

    osc.connect(formantOne);
    osc.connect(formantTwo);
    formantOne.connect(env);
    formantTwo.connect(formantGain);
    formantGain.connect(env);
    env.connect(destination);

    osc.start(start);
    osc.stop(end + release + 0.02);
    this.trackOscillator(osc);
    return this.createNoteHandle(ctx, [osc], [env], release);
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

  async renderMix({ masterVolume = 1, singleTrackId = null, sampleRate = 44100, normalize = false, rangeStart = 0, rangeEnd = null } = {}) {
    if (!this.session) throw new Error('There is no session to render.');
    const offset = Math.max(0, Number(rangeStart) || 0);
    const sourceDuration = rangeEnd == null ? this.duration() : Math.max(0, Number(rangeEnd) - offset);
    const tracks = singleTrackId
      ? this.session.tracks.filter((track) => track.id === singleTrackId)
      : this.session.tracks;
    const tempo = this.session.tempo ?? 120;
    const releaseTail = Math.max(0, ...tracks.map((track) => trackNoteReleaseTail(track, false, tempo)));
    const effectsTail = trackEffectsTailDuration(tracks, tempo);
    const duration = sourceDuration + releaseTail + effectsTail;
    if (sourceDuration <= 0) throw new Error('There is nothing to render yet.');

    const buffer = await this.renderOffline({
      duration,
      sourceDuration,
      offset,
      tracks,
      masterVolume,
      sampleRate,
      includeMixer: true,
      frozenSource: singleTrackId ? this.session.tracks.find((t) => t.id === singleTrackId)?.frozen?.fileId : null
    });
    return normalize ? normalizeBuffer(buffer) : buffer;
  }

  async renderTrackFreeze(track) {
    const tempo = this.session?.tempo ?? 120;
    const sourceDuration = model.trackDuration(track, tempo);
    const releaseTail = trackNoteReleaseTail(track, true, tempo);
    const effectsTail = trackEffectsTailDuration([track], tempo, true);
    const duration = sourceDuration + releaseTail + effectsTail;
    if (sourceDuration <= 0) throw new Error('This track has nothing to freeze yet.');
    return this.renderOffline({
      duration,
      sourceDuration,
      tracks: [track],
      masterVolume: 1,
      includeMixer: false,
      forceSource: true
    });
  }

  async renderStem(track, { sampleRate = 44100, normalize = false, rangeStart = 0, rangeEnd = null } = {}) {
    const offset = Math.max(0, Number(rangeStart) || 0);
    const tempo = this.session?.tempo ?? 120;
    const sourceDuration = rangeEnd == null ? model.trackDuration(track, tempo) : Math.max(0, Number(rangeEnd) - offset);
    const releaseTail = trackNoteReleaseTail(track, false, tempo);
    const effectsTail = trackEffectsTailDuration([track], tempo);
    const duration = sourceDuration + releaseTail + effectsTail;
    if (sourceDuration <= 0) throw new Error('This track has nothing to render.');
    const buffer = await this.renderOffline({
      duration,
      sourceDuration,
      offset,
      tracks: [track],
      masterVolume: this.session?.masterVolume ?? 1,
      sampleRate,
      includeMixer: true,
      applyMuteSolo: false
    });
    return normalize ? normalizeBuffer(buffer) : buffer;
  }

  async renderOffline({ duration, sourceDuration = duration, offset = 0, tracks, masterVolume = 1, sampleRate = 44100, includeMixer = true, forceSource = false, frozenSource = null, applyMuteSolo = true }) {
    const offline = new OfflineAudioContext(2, Math.ceil(duration * sampleRate) + 1024, sampleRate);

    const masterChain = buildMasterChain(offline, offline.destination, {
      masterVolume: includeMixer ? masterVolume : 1,
      effects: this.session?.masterEffects,
      tempo: this.session?.tempo ?? 120,
      includeEffects: includeMixer,
      mastering: includeMixer ? this.session?.mastering : null
    });
    const master = masterChain.input;

    let auxChain = null;
    if (includeMixer) {
      auxChain = buildAuxChain(offline, master);
      applyAuxBusSettings(auxChain, this.session?.auxA, this.session?.auxB, this.session?.tempo ?? 120);
    }

    const groups = this.session?.groups || [];
    const soloedTrackIDs = new Set(groups.filter((group) => group.soloed).flatMap((group) => group.trackIDs));
    const anySolo = this.session ? this.session.tracks.some((track) => track.soloed || soloedTrackIDs.has(track.id)) : false;

    for (const track of tracks) {
      const input = this.buildOfflineTrack(offline, track, master, {
        includeMixer,
        anySolo,
        duration,
        offset,
        applyMuteSolo,
        groups: this.session?.groups || [],
        auxChain,
        forceSource
      });
      this.scheduleOfflineTrack(offline, track, input, sourceDuration, forceSource, offset);
    }

    return offline.startRendering();
  }

  buildOfflineTrack(ctx, track, destination, { includeMixer, anySolo, duration, offset = 0, applyMuteSolo = true, groups = [], auxChain = null, forceSource = false }) {
    const input = ctx.createGain();
    const group = groups.find((item) => item.trackIDs.includes(track.id));
    const mutedByGroup = group?.muted ?? false;
    const soloedByGroup = group?.soloed ?? false;
    const audible = !applyMuteSolo
      || (!(track.muted || mutedByGroup) && (!anySolo || track.soloed || soloedByGroup));

    if (includeMixer) {
      const volume = audible ? track.volume * (group ? group.volume : 1) : 0;
      input.gain.setValueAtTime(volume * model.automationGain(track, offset), 0);
      const step = 0.05;
      for (let time = step; time <= duration; time += step) {
        const value = volume * model.automationGain(track, offset + time);
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
      scheduleAutomatedPan(panner.pan, track, duration, offset);
      tail.connect(panner);
      tail = panner;
    }

    tail.connect(low);
    low.connect(mid);
    mid.connect(high);
    high.connect(comp);
    const effects = buildTrackEffects(ctx, comp);
    applyTrackEffects(track, effects, this.session?.tempo ?? 120, offset, frozen);
    effects.output.connect(destination);

    if (includeMixer && auxChain) {
      const sendLevel = (value) => (applyMuteSolo && !audible ? 0 : model.clamp(Number(value ?? 0), 0, 1));
      const sendA = ctx.createGain();
      sendA.gain.value = sendLevel(track.sendA);
      effects.output.connect(sendA);
      sendA.connect(auxChain.aInput);

      const sendB = ctx.createGain();
      sendB.gain.value = sendLevel(track.sendB);
      effects.output.connect(sendB);
      sendB.connect(auxChain.bInput);
    }

    return input;
  }

  scheduleOfflineTrack(ctx, track, input, duration, forceSource, offset = 0) {
    const clips = forceSource ? track.clips : model.playbackClips(track);
    const sourceNotes = forceSource ? track.notes : model.sequencedNotes(track);
    const notes = model.arpeggiate(sourceNotes, track.arpeggiator, this.session?.tempo ?? 120);
    const rangeEnd = offset + duration;

    const tempo = this.session?.tempo ?? 120;
    for (const clip of clips) {
      const sourceBuffer = this.buffers.get(clip.fileId);
      if (!sourceBuffer) continue;
      const buffer = this.clipBuffer(clip, sourceBuffer, ctx);
      const playable = model.clipTimelineDuration(clip, tempo);
      if (playable <= 0) continue;
      const clipEnd = clip.start + playable;
      const clipStart = Math.max(clip.start, offset);
      const clippedEnd = Math.min(clipEnd, rangeEnd);
      if (clippedEnd <= clipStart) continue;
      const localStart = clipStart - offset;
      const localEnd = clippedEnd - offset;
      const playbackRate = model.clipPlaybackRate(clip, tempo);
      const sourceOffset = clip.sourceStart / playbackRate + clipStart - clip.start;
      const clippedDuration = Math.min(clippedEnd - clipStart, buffer.duration - sourceOffset);
      if (clippedDuration <= 1e-4) continue;

      const source = ctx.createBufferSource();
      source.buffer = buffer;
      const fadeGain = ctx.createGain();
      const gainAt = (localTime) => model.clipGainAt(clip, track, offset + localTime, tempo);
      fadeGain.gain.setValueAtTime(gainAt(localStart), localStart);
      fadeGain.gain.linearRampToValueAtTime(gainAt(localEnd), localEnd);
      source.connect(fadeGain);
      fadeGain.connect(input);
      try {
        source.start(localStart, sourceOffset, clippedDuration);
      } catch (error) {
        continue;
      }
    }

    for (const note of notes) {
      if (note.start >= rangeEnd || note.start + note.duration <= offset) continue;
      const clippedNote = { ...note, start: Math.max(0, note.start - offset) };
      this.scheduleNote(ctx, input, clippedNote, clippedNote.start, model.presetForTrack(track), track.guitarTone);
    }
  }
}

function transformClipBuffer(context, buffer, semitones, playbackRate) {
  const pitchRatio = Math.pow(2, semitones / 12);
  const pitched = Math.abs(pitchRatio - 1) < 1e-6
    ? buffer
    : resamplePitchBuffer(context, buffer, pitchRatio);
  const stretchFactor = pitchRatio / playbackRate;
  return Math.abs(stretchFactor - 1) < 1e-6
    ? pitched
    : stretchAudioBuffer(context, pitched, stretchFactor);
}

function resamplePitchBuffer(context, buffer, ratio) {
  const outputLength = Math.max(1, Math.round(buffer.length / ratio));
  const output = context.createBuffer(buffer.numberOfChannels, outputLength, buffer.sampleRate);
  for (let channel = 0; channel < buffer.numberOfChannels; channel += 1) {
    const source = buffer.getChannelData(channel);
    const destination = output.getChannelData(channel);
    for (let index = 0; index < outputLength; index += 1) {
      const position = Math.min(source.length - 1, index * ratio);
      const lower = Math.floor(position);
      const upper = Math.min(source.length - 1, lower + 1);
      const blend = position - lower;
      destination[index] = source[lower] * (1 - blend) + source[upper] * blend;
    }
  }
  return output;
}

function stretchAudioBuffer(context, buffer, factor) {
  const targetLength = Math.max(1, Math.round(buffer.length * factor));
  const frameLength = Math.min(1024, buffer.length);
  if (frameLength < 128) {
    const output = context.createBuffer(buffer.numberOfChannels, targetLength, buffer.sampleRate);
    for (let channel = 0; channel < buffer.numberOfChannels; channel += 1) {
      const source = buffer.getChannelData(channel);
      const destination = output.getChannelData(channel);
      for (let index = 0; index < targetLength; index += 1) {
        const position = targetLength <= 1 ? 0 : (index / (targetLength - 1)) * Math.max(0, source.length - 1);
        const lower = Math.floor(position);
        const upper = Math.min(source.length - 1, lower + 1);
        const blend = position - lower;
        destination[index] = source[lower] * (1 - blend) + source[upper] * blend;
      }
    }
    return output;
  }

  const hop = Math.floor(frameLength / 2);
  const overlap = frameLength - hop;
  const searchRadius = Math.min(96, Math.floor(overlap / 5));
  const window = new Float32Array(frameLength);
  for (let index = 0; index < frameLength; index += 1) {
    window[index] = 0.5 - 0.5 * Math.cos((2 * Math.PI * index) / (frameLength - 1));
  }

  const sourceChannels = Array.from({ length: buffer.numberOfChannels }, (_, index) => buffer.getChannelData(index));
  const output = context.createBuffer(buffer.numberOfChannels, targetLength, buffer.sampleRate);
  const accumulated = Array.from({ length: buffer.numberOfChannels }, (_, index) => output.getChannelData(index));
  const weights = new Float32Array(targetLength);
  let previousStart = 0;

  for (let outputStart = 0; outputStart < targetLength; outputStart += hop) {
    const maxSourceStart = Math.max(0, buffer.length - frameLength);
    const expected = outputStart === 0 ? 0 : previousStart + hop / factor;
    let sourceStart = Math.min(maxSourceStart, Math.max(0, Math.round(expected)));

    if (outputStart > 0 && searchRadius > 0) {
      let bestScore = -Infinity;
      const center = sourceStart;
      for (let delta = -searchRadius; delta <= searchRadius; delta += 4) {
        const candidate = Math.min(maxSourceStart, Math.max(0, center + delta));
        let score = 0;
        for (let sample = 0; sample < overlap; sample += 16) {
          const previousIndex = Math.min(buffer.length - 1, previousStart + hop + sample);
          const candidateIndex = Math.min(buffer.length - 1, candidate + sample);
          let previousValue = 0;
          let candidateValue = 0;
          for (let channel = 0; channel < sourceChannels.length; channel += 1) {
            previousValue += sourceChannels[channel][previousIndex];
            candidateValue += sourceChannels[channel][candidateIndex];
          }
          score += previousValue * candidateValue;
        }
        if (score > bestScore) {
          bestScore = score;
          sourceStart = candidate;
        }
      }
    }

    const usable = Math.min(frameLength, targetLength - outputStart);
    for (let sample = 0; sample < usable; sample += 1) {
      const destinationIndex = outputStart + sample;
      const sourceIndex = Math.min(buffer.length - 1, sourceStart + sample);
      const weight = window[sample];
      weights[destinationIndex] += weight;
      for (let channel = 0; channel < sourceChannels.length; channel += 1) {
        accumulated[channel][destinationIndex] += sourceChannels[channel][sourceIndex] * weight;
      }
    }
    previousStart = sourceStart;
  }

  for (let channel = 0; channel < buffer.numberOfChannels; channel += 1) {
    const destination = accumulated[channel];
    for (let index = 0; index < targetLength; index += 1) {
      destination[index] = weights[index] > 1e-5 ? accumulated[channel][index] / weights[index] : 0;
    }
  }
  return output;
}

function scheduleAutomatedPan(param, track, duration, offset = 0) {
  const panAt = (time) => {
    const automated = model.automationValue(track.panAutomation, offset + time, 'pan');
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

function emptyLoudness() {
  return { integrated: null, shortTerm: null, truePeak: null, seconds: 0 };
}

function buildMasterChain(ctx, destination, { masterVolume = 1, effects, tempo = 120, includeEffects = true, mastering = null }) {
  const input = ctx.createGain();
  input.gain.value = masterVolume;

  // Master EQ, bus compressor and limiter sit on everything, before the
  // reverb and delay sends and before the destination.
  const eqLow = ctx.createBiquadFilter();
  eqLow.type = 'lowshelf';
  eqLow.frequency.value = 120;
  const eqMid = ctx.createBiquadFilter();
  eqMid.type = 'peaking';
  eqMid.Q.value = 1.2;
  eqMid.frequency.value = 1000;
  const eqHigh = ctx.createBiquadFilter();
  eqHigh.type = 'highshelf';
  eqHigh.frequency.value = 8000;
  const compressor = ctx.createDynamicsCompressor();
  const drive = ctx.createGain();
  const limiter = ctx.createDynamicsCompressor();
  limiter.ratio.value = 20;
  limiter.knee.value = 0;
  limiter.attack.value = 0.002;
  const ceiling = ctx.createGain();

  input.connect(eqLow);
  eqLow.connect(eqMid);
  eqMid.connect(eqHigh);
  eqHigh.connect(compressor);
  compressor.connect(drive);
  drive.connect(limiter);
  limiter.connect(ceiling);

  const chain = {
    input,
    eqLow,
    eqMid,
    eqHigh,
    compressor,
    drive,
    limiter,
    ceiling,
    dry: null,
    reverb: null,
    revWet: null,
    delay: null,
    delayWet: null,
    feedback: null,
    impulseDecay: 0
  };

  const dry = ctx.createGain();
  ceiling.connect(dry);
  dry.connect(destination);
  chain.dry = dry;

  if (!includeEffects) {
    applyMasterChain(chain, { effects, tempo, mastering });
    return chain;
  }

  const reverb = ctx.createConvolver();
  const revWet = ctx.createGain();
  const delay = ctx.createDelay(2);
  const feedback = ctx.createGain();
  const delayWet = ctx.createGain();

  ceiling.connect(reverb);
  reverb.connect(revWet);
  revWet.connect(destination);

  ceiling.connect(delay);
  delay.connect(feedback);
  feedback.connect(delay);
  delay.connect(delayWet);
  delayWet.connect(destination);

  chain.reverb = reverb;
  chain.revWet = revWet;
  chain.delay = delay;
  chain.delayWet = delayWet;
  chain.feedback = feedback;

  applyMasterChain(chain, { effects, tempo, mastering });
  return chain;
}

function applyMasterChain(chain, { effects, tempo, mastering }) {
  if (!chain) return;
  applyMastering(chain, mastering);
  if (!chain.reverb) return;

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

/// Applies the mastering settings to a built master chain.
function applyMastering(chain, mastering) {
  if (!chain || !chain.eqLow) return;

  const settings = mastering || { bypassed: true };
  const off = settings.bypassed === true;

  const eq = settings.eq || {};
  const eqOff = off || eq.bypassed === true;
  chain.eqLow.gain.value = eqOff ? 0 : model.clamp(Number(eq.lowGain ?? 0), -12, 12);
  chain.eqMid.frequency.value = model.clamp(Number(eq.midFrequency ?? 1000), 200, 6000);
  chain.eqMid.gain.value = eqOff ? 0 : model.clamp(Number(eq.midGain ?? 0), -12, 12);
  chain.eqHigh.gain.value = eqOff ? 0 : model.clamp(Number(eq.highGain ?? 0), -12, 12);

  const comp = settings.compressor || {};
  const compOff = off || comp.bypassed === true;
  chain.compressor.threshold.value = compOff ? 0 : model.clamp(Number(comp.threshold ?? -18), -60, 0);
  chain.compressor.ratio.value = compOff ? 1 : model.clamp(Number(comp.ratio ?? 2), 1, 20);
  chain.compressor.attack.value = model.clamp(Number(comp.attack ?? 0.03), 0.001, 1);
  chain.compressor.release.value = model.clamp(Number(comp.release ?? 0.25), 0.05, 1);

  const lim = settings.limiter || {};
  const limOff = off || lim.bypassed === true;
  const ceilingDB = model.clamp(Number(lim.ceiling ?? -1), -6, 0);
  chain.drive.gain.value = limOff
    ? 1
    : Math.pow(10, model.clamp(Number(lim.drive ?? 0), -12, 12) / 20);
  chain.limiter.threshold.value = limOff ? 0 : ceilingDB;
  chain.limiter.ratio.value = limOff ? 1 : 20;
  chain.limiter.knee.value = 0;
  chain.limiter.attack.value = 0.002;
  chain.limiter.release.value = model.clamp(Number(lim.release ?? 0.08), 0.02, 0.5);
}

function buildAuxChain(ctx, destination) {
  const aInput = ctx.createGain();
  const aReverb = ctx.createConvolver();
  const aWet = ctx.createGain();
  const aReturn = ctx.createGain();
  aInput.connect(aReverb);
  aReverb.connect(aWet);
  aWet.connect(aReturn);
  aReturn.connect(destination);

  const bInput = ctx.createGain();
  const bDelay = ctx.createDelay(2);
  const bWet = ctx.createGain();
  const bFeedback = ctx.createGain();
  const bReturn = ctx.createGain();
  bInput.connect(bDelay);
  bDelay.connect(bWet);
  bWet.connect(bReturn);
  bReturn.connect(destination);
  bDelay.connect(bFeedback);
  bFeedback.connect(bDelay);

  return { aInput, aReverb, aWet, aReturn, bInput, bDelay, bWet, bFeedback, bReturn, reverbDecay: 0 };
}

function applyAuxBusSettings(chain, auxA, auxB, tempo) {
  if (!chain) return;
  const a = auxA || {};
  const decay = model.clamp(Number(a.reverbDecay ?? 1.4), 0.2, 5);
  if (chain.reverbDecay !== decay) {
    chain.reverbDecay = decay;
    try {
      chain.aReverb.buffer = makeImpulseResponse(chain.aReverb.context, decay);
    } catch (error) {
      // keep the previous impulse if the browser rejects the swap
    }
  }
  const aOff = a.bypassed === true;
  chain.aWet.gain.value = aOff ? 0 : model.clamp(Number(a.reverbMix ?? 0.4), 0, 1);
  chain.aReturn.gain.value = aOff ? 0 : model.clamp(Number(a.level ?? 0.8), 0, 1);

  const b = auxB || {};
  const bOff = b.bypassed === true;
  const beats = Number(b.delayBeats ?? 0.75);
  chain.bDelay.delayTime.value = Math.min(2, Math.max(0.01, beats * 60 / (tempo || 120)));
  chain.bWet.gain.value = bOff ? 0 : model.clamp(Number(b.delayMix ?? 0.35), 0, 1);
  chain.bFeedback.gain.value = bOff ? 0 : model.clamp(Number(b.delayFeedback ?? 0.35), 0, 0.9);
  chain.bReturn.gain.value = bOff ? 0 : model.clamp(Number(b.level ?? 0.7), 0, 1);
}

export function encodeWav(buffer, bitDepth = 16) {
  const channels = buffer.numberOfChannels;
  const sampleRate = buffer.sampleRate;
  const frames = buffer.length;
  const bytesPerSample = bitDepth / 8;
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
  view.setUint16(34, bitDepth, true);
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
      if (bitDepth === 24) {
        const value = sample < 0 ? Math.round(sample * 0x800000) : Math.round(sample * 0x7fffff);
        view.setUint8(offset, value & 0xff);
        view.setUint8(offset + 1, (value >> 8) & 0xff);
        view.setUint8(offset + 2, (value >> 16) & 0xff);
        offset += 3;
      } else {
        view.setInt16(offset, sample < 0 ? sample * 0x8000 : sample * 0x7fff, true);
        offset += 2;
      }
    }
  }

  return new Blob([arrayBuffer], { type: 'audio/wav' });
}



function normalizeBuffer(buffer) {
  let peak = 0;
  for (let channel = 0; channel < buffer.numberOfChannels; channel += 1) {
    const samples = buffer.getChannelData(channel);
    for (let index = 0; index < samples.length; index += 1) {
      peak = Math.max(peak, Math.abs(samples[index]));
    }
  }
  if (peak > 0) {
    const gain = Math.pow(10, -1 / 20) / peak;
    for (let channel = 0; channel < buffer.numberOfChannels; channel += 1) {
      const samples = buffer.getChannelData(channel);
      for (let index = 0; index < samples.length; index += 1) samples[index] *= gain;
    }
  }
  return buffer;
}



function buildTrackEffects(ctx, input) {
  const chorusDelay = ctx.createDelay(0.05);
  chorusDelay.delayTime.value = 0.02;
  const chorusDry = ctx.createGain();
  const chorusWet = ctx.createGain();
  const chorusOut = ctx.createGain();
  const chorusLFO = ctx.createOscillator();
  const chorusDepth = ctx.createGain();
  chorusLFO.type = 'sine';
  chorusLFO.frequency.value = 0.8;
  chorusDepth.gain.value = 0.005;
  chorusLFO.connect(chorusDepth);
  chorusDepth.connect(chorusDelay.delayTime);
  chorusLFO.start();

  input.connect(chorusDry);
  chorusDry.connect(chorusOut);
  input.connect(chorusDelay);
  chorusDelay.connect(chorusWet);
  chorusWet.connect(chorusOut);

  const distortion = ctx.createWaveShaper();
  distortion.oversample = '4x';
  const distortionDry = ctx.createGain();
  const distortionWet = ctx.createGain();
  const distortionOut = ctx.createGain();
  distortionOut.channelCount = 2;
  distortionOut.channelCountMode = 'explicit';
  chorusOut.connect(distortionDry);
  distortionDry.connect(distortionOut);
  chorusOut.connect(distortion);
  distortion.connect(distortionWet);
  distortionWet.connect(distortionOut);

  const stereoDelay = ctx.createDelay(4);
  const delayFeedback = ctx.createGain();
  const delayDry = ctx.createGain();
  const delayWet = ctx.createGain();
  const output = ctx.createGain();
  distortionOut.connect(delayDry);
  delayDry.connect(output);
  distortionOut.connect(stereoDelay);
  stereoDelay.connect(delayFeedback);
  delayFeedback.connect(stereoDelay);
  stereoDelay.connect(delayWet);
  delayWet.connect(output);

  return {
    output,
    chorusDelay,
    chorusDry,
    chorusWet,
    chorusLFO,
    chorusDepth,
    chorusOut,
    distortion,
    distortionDry,
    distortionWet,
    distortionOut,
    stereoDelay,
    delayFeedback,
    delayDry,
    delayWet
  };
}

function applyTrackEffects(track, effects, tempo, time, frozen = false) {
  if (!effects) return;
  const rack = model.normalizeTrackEffectsRack(track.effectsRack);
  const chorusOn = !frozen && !rack.chorus.bypassed;
  const chorusMix = chorusOn ? rack.chorus.mix : 0;
  effects.chorusLFO.frequency.value = rack.chorus.rateHz;
  effects.chorusDepth.gain.value = rack.chorus.depthMs / 1000;
  effects.chorusDelay.delayTime.value = 0.02;
  effects.chorusDry.gain.value = 1 - chorusMix;
  effects.chorusWet.gain.value = chorusMix;

  const distortionOn = !frozen && !rack.distortion.bypassed;
  const distortionMix = distortionOn ? rack.distortion.mix : 0;
  if (effects.distortionDriveDB !== rack.distortion.driveDB) {
    effects.distortion.curve = makeTrackDistortionCurve(rack.distortion.driveDB);
    effects.distortionDriveDB = rack.distortion.driveDB;
  }
  effects.distortionDry.gain.value = 1 - distortionMix;
  effects.distortionWet.gain.value = distortionMix;

  const delayOn = !frozen && !rack.stereoDelay.bypassed;
  const delayMix = delayOn ? rack.stereoDelay.mix : 0;
  const beatSeconds = 60 / Math.max(60, Number(tempo) || 120);
  const delayTime = model.clamp(rack.stereoDelay.timeBeats * beatSeconds, 0.01, 2);
  effects.stereoDelay.delayTime.value = delayTime;
  const feedback = delayOn ? rack.stereoDelay.feedback : 0;
  effects.delayFeedback.gain.value = feedback;
  effects.delayDry.gain.value = 1 - delayMix;
  effects.delayWet.gain.value = delayMix;
}

function makeTrackDistortionCurve(driveDB) {
  const samples = 2_048;
  const curve = new Float32Array(samples);
  const amount = Math.pow(10, model.clamp(Number(driveDB) || 0, 0, 20) / 20);
  const scale = 1 + amount * 0.45;
  const normalizer = Math.tanh(scale);
  for (let index = 0; index < samples; index += 1) {
    const input = (index / (samples - 1)) * 2 - 1;
    curve[index] = Math.tanh(scale * input) / normalizer;
  }
  return curve;
}


function trackNoteReleaseTail(track, forceSource = false, tempo = 120) {
  const notes = forceSource ? (track.notes || []) : model.sequencedNotes(track);
  if (!notes.length) return 0;
  const preset = model.presetForTrack(track);
  const release = Math.max(0, Number(preset.release) || 0);
  const noteEnd = Math.max(...notes.map((note) => Number(note.start) + Number(note.duration) + release));
  const clipEnd = (forceSource ? (track.clips || []) : model.playbackClips(track)).reduce((end, clip) => (
    Math.max(end, Math.max(0, clip.start) + model.clipTimelineDuration(clip, tempo))
  ), 0);
  const sourceEnd = Math.max(clipEnd, ...notes.map((note) => Number(note.start) + Number(note.duration)));
  return Math.max(0, noteEnd - sourceEnd);
}

function trackEffectsTailDuration(tracks, tempo, forceSource = false) {
  return Math.max(0, ...tracks.map((track) => {
    const frozen = !forceSource && Boolean(track.frozen?.fileId);
    if (frozen) return 0;
    const rack = model.normalizeTrackEffectsRack(track.effectsRack);
    let tail = 0;
    if (!rack.chorus.bypassed && rack.chorus.mix > 0) tail = Math.max(tail, 0.04);
    if (!rack.stereoDelay.bypassed && rack.stereoDelay.mix > 0) {
      const delayTime = model.clamp(rack.stereoDelay.timeBeats * 60 / Math.max(60, Number(tempo) || 120), 0.01, 2);
      const feedback = rack.stereoDelay.feedback;
      const repeats = feedback > 0 ? Math.max(1, Math.ceil(Math.log(0.001) / Math.log(feedback))) : 1;
      tail = Math.max(tail, Math.min(8, delayTime * repeats));
    }
    return tail;
  }));
}
