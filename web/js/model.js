// Shared model + storage helpers for the web studio.

export const NOTE_LOW = 48;
export const NOTE_HIGH = 71;
export const MIN_LOOP = 0.2;
export const TRACK_COLORS = ['#fa9f2d', '#2aa89a', '#5c8fed', '#cc6bc7'];

const DRUM_VOICE_IDS = ['kick', 'snare', 'lowTom', 'midTom', 'highTom', 'rimshot', 'clap', 'cowbell', 'closedHat', 'openHat', 'cymbal'];
const DRUM_STEP_COUNT = 16;

function emptyDrumPattern() {
  return Object.fromEntries(DRUM_VOICE_IDS.map((voice) => [voice, Array(DRUM_STEP_COUNT).fill(false)]));
}

export function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

export function uid() {
  if (globalThis.crypto && typeof globalThis.crypto.randomUUID === 'function') {
    return globalThis.crypto.randomUUID();
  }
  return `id-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

export function formatTime(seconds) {
  const total = Math.max(0, Number(seconds) || 0);
  const minutes = Math.floor(total / 60);
  const secs = Math.floor(total % 60).toString().padStart(2, '0');
  const tenths = Math.floor((total - Math.floor(total)) * 10);
  return `${minutes.toString().padStart(2, '0')}:${secs}.${tenths}`;
}

export function dbLabel(volume) {
  const value = clamp(Number(volume) || 0, 0, 1);
  if (value < 0.0001) return '-∞ dB';
  return `${(20 * Math.log10(value)).toFixed(1)} dB`;
}

export function panLabel(pan) {
  const value = clamp(Number(pan) || 0, -1, 1);
  if (Math.abs(value) < 0.005) return 'C';
  return value < 0 ? `L${Math.round(Math.abs(value) * 100)}` : `R${Math.round(value * 100)}`;
}

export function noteFrequency(pitch) {
  return 440 * Math.pow(2, (pitch - 69) / 12);
}

const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

export function noteName(pitch) {
  const index = ((pitch % 12) + 12) % 12;
  return `${NOTE_NAMES[index]}${Math.floor(pitch / 12) - 1}`;
}

export function isBlackKey(pitch) {
  return [1, 3, 6, 8, 10].includes(((pitch % 12) + 12) % 12);
}

export function trackColor(index) {
  return TRACK_COLORS[index % TRACK_COLORS.length];
}

function defaultEQ() {
  return {
    bypassed: false,
    low: { frequency: 120, gain: 0 },
    mid: { frequency: 1000, gain: 0 },
    high: { frequency: 8000, gain: 0 }
  };
}

function defaultCompressor() {
  return {
    bypassed: true,
    threshold: -18,
    ratio: 4,
    attack: 0.01,
    release: 0.12
  };
}

function defaultTrackEffectsRack() {
  return {
    chorus: { bypassed: true, rateHz: 0.8, depthMs: 5, mix: 0.25 },
    distortion: { bypassed: true, driveDB: 8, mix: 0.35 },
    stereoDelay: { bypassed: true, timeBeats: 0.5, feedback: 0.3, mix: 0.25 }
  };
}

export function normalizeTrackEffectsRack(rack) {
  const defaults = defaultTrackEffectsRack();
  const value = rack && typeof rack === 'object' ? rack : {};
  const chorus = value.chorus && typeof value.chorus === 'object' ? value.chorus : {};
  const distortion = value.distortion && typeof value.distortion === 'object' ? value.distortion : {};
  const stereoDelay = value.stereoDelay && typeof value.stereoDelay === 'object' ? value.stereoDelay : {};
  return {
    chorus: {
      bypassed: chorus.bypassed !== false,
      rateHz: clamp(Number(chorus.rateHz ?? defaults.chorus.rateHz), 0.1, 5),
      depthMs: clamp(Number(chorus.depthMs ?? defaults.chorus.depthMs), 0, 12),
      mix: clamp(Number(chorus.mix ?? defaults.chorus.mix), 0, 1)
    },
    distortion: {
      bypassed: distortion.bypassed !== false,
      driveDB: clamp(Number(distortion.driveDB ?? defaults.distortion.driveDB), 0, 20),
      mix: clamp(Number(distortion.mix ?? defaults.distortion.mix), 0, 1)
    },
    stereoDelay: {
      bypassed: stereoDelay.bypassed !== false,
      timeBeats: clamp(Number(stereoDelay.timeBeats ?? defaults.stereoDelay.timeBeats), 0.25, 2),
      feedback: clamp(Number(stereoDelay.feedback ?? defaults.stereoDelay.feedback), 0, 0.9),
      mix: clamp(Number(stereoDelay.mix ?? defaults.stereoDelay.mix), 0, 1)
    }
  };
}

/// The two shared send buses: A is a reverb, B is a tempo-synced delay.
export function defaultAuxBuses() {
  return {
    auxA: {
      name: 'Aux A',
      effect: 'reverb',
      bypassed: false,
      level: 0.8,
      reverbMix: 0.4,
      reverbDecay: 1.8,
      delayBeats: 0.5,
      delayFeedback: 0.3,
      delayMix: 0.3
    },
    auxB: {
      name: 'Aux B',
      effect: 'delay',
      bypassed: false,
      level: 0.7,
      reverbMix: 0.3,
      reverbDecay: 1.4,
      delayBeats: 0.75,
      delayFeedback: 0.35,
      delayMix: 0.35
    }
  };
}

function normalizeAuxBus(bus, defaults) {
  const value = bus && typeof bus === 'object' ? bus : {};
  return {
    name: typeof value.name === 'string' && value.name.trim() ? value.name.trim() : defaults.name,
    effect: value.effect === 'delay' ? 'delay' : defaults.effect,
    bypassed: value.bypassed === true,
    level: clamp(Number(value.level ?? defaults.level), 0, 1),
    reverbMix: clamp(Number(value.reverbMix ?? defaults.reverbMix), 0, 1),
    reverbDecay: clamp(Number(value.reverbDecay ?? defaults.reverbDecay), 0.2, 5),
    delayBeats: clamp(Number(value.delayBeats ?? defaults.delayBeats), 0.25, 2),
    delayFeedback: clamp(Number(value.delayFeedback ?? defaults.delayFeedback), 0, 0.9),
    delayMix: clamp(Number(value.delayMix ?? defaults.delayMix), 0, 1)
  };
}

/// Loudness targets the mastering meters are judged against.
export const LOUDNESS_TARGETS = [
  { id: 'streaming', name: 'Streaming', loudness: -14, truePeak: -1, detail: 'Spotify, Apple Music' },
  { id: 'podcast', name: 'Podcast', loudness: -16, truePeak: -1, detail: 'Spoken word' },
  { id: 'club', name: 'Club', loudness: -9, truePeak: -0.1, detail: 'Loud club master' }
];

/// Master EQ, bus compressor and limiter applied to the whole mix.
export function defaultMastering() {
  return {
    bypassed: true,
    target: 'streaming',
    eq: { bypassed: false, lowGain: 0, midFrequency: 1000, midGain: 0, highGain: 0 },
    compressor: { bypassed: false, threshold: -18, ratio: 2, attack: 0.03, release: 0.25 },
    limiter: { bypassed: false, drive: 0, ceiling: -1, release: 0.08 }
  };
}

export function loudnessTarget(id) {
  return LOUDNESS_TARGETS.find((item) => item.id === id) || LOUDNESS_TARGETS[0];
}

function normalizeMastering(mastering) {
  const defaults = defaultMastering();
  const value = mastering && typeof mastering === 'object' ? mastering : {};
  const eq = value.eq && typeof value.eq === 'object' ? value.eq : {};
  const compressor = value.compressor && typeof value.compressor === 'object' ? value.compressor : {};
  const limiter = value.limiter && typeof value.limiter === 'object' ? value.limiter : {};
  return {
    bypassed: value.bypassed !== false,
    target: LOUDNESS_TARGETS.some((item) => item.id === value.target) ? value.target : defaults.target,
    eq: {
      bypassed: eq.bypassed === true,
      lowGain: clamp(Number(eq.lowGain ?? defaults.eq.lowGain), -12, 12),
      midFrequency: clamp(Number(eq.midFrequency ?? defaults.eq.midFrequency), 200, 6000),
      midGain: clamp(Number(eq.midGain ?? defaults.eq.midGain), -12, 12),
      highGain: clamp(Number(eq.highGain ?? defaults.eq.highGain), -12, 12)
    },
    compressor: {
      bypassed: compressor.bypassed === true,
      threshold: clamp(Number(compressor.threshold ?? defaults.compressor.threshold), -40, 0),
      ratio: clamp(Number(compressor.ratio ?? defaults.compressor.ratio), 1, 8),
      attack: clamp(Number(compressor.attack ?? defaults.compressor.attack), 0.001, 0.1),
      release: clamp(Number(compressor.release ?? defaults.compressor.release), 0.05, 1)
    },
    limiter: {
      bypassed: limiter.bypassed === true,
      drive: clamp(Number(limiter.drive ?? defaults.limiter.drive), -12, 12),
      ceiling: clamp(Number(limiter.ceiling ?? defaults.limiter.ceiling), -6, 0),
      release: clamp(Number(limiter.release ?? defaults.limiter.release), 0.02, 0.5)
    }
  };
}

export function createTrack({ name, fileId = null, duration = 0, index = 0 }) {
  const track = {
    id: uid(),
    name: name || `Track ${index + 1}`,
    colorIndex: index,
    volume: 1,
    pan: 0,
    muted: false,
    soloed: false,
    sendA: 0,
    sendB: 0,
    arpeggiator: defaultArpeggiator(),
    voice: 'synth',
    presetId: null,
    guitarTone: defaultGuitarTone(),
    eq: defaultEQ(),
    comp: defaultCompressor(),
    effectsRack: defaultTrackEffectsRack(),
    automation: [],
    panAutomation: [],
    clips: [],
    notes: [],
    frozen: { fileId: null, duration: 0 }
  };

  if (fileId) {
    track.clips.push({
      id: uid(),
      name,
      fileId,
      start: 0,
      duration,
      sourceStart: 0,
      sourceDuration: duration
    });
  }

  return track;
}

export function createSession(name = 'Untitled Session') {
  const auxBuses = defaultAuxBuses();
  return {
    id: uid(),
    name,
    tempo: 120,
    masterVolume: 1,
    auxA: auxBuses.auxA,
    auxB: auxBuses.auxB,
    mastering: defaultMastering(),
    masterEffects: {
      bypassed: true,
      reverbMix: 0.32,
      reverbDecay: 1.8,
      delayBeats: 0.5,
      delayFeedback: 0.38,
      delayMix: 0.22
    },
    loop: { start: 0, end: 0, enabled: false },
    punch: { enabled: false, in: 0, out: 0, armedTrackId: null },
    metronome: { enabled: false, level: 0.7, countIn: false },
    drumPattern: emptyDrumPattern(),
    sections: [],
    groups: [],
    tracks: [],
    editedAt: Date.now()
  };
}

// Prepared layouts a session can be started from, mirroring the iOS templates.

export const SESSION_TEMPLATES = [
  {
    id: 'four-piece-band',
    name: 'Four-Piece Band',
    summary: 'Vocals, guitar, bass and drums, balanced for a live-band mix.',
    tempo: 92,
    suggested: true,
    tracks: [
      { name: 'Vocals', volume: 0.92, pan: 0, low: -2, mid: 1.5, high: 2 },
      { name: 'Drums', volume: 0.9, pan: 0, low: 2, mid: -1, high: 1.5, comp: { threshold: -20, ratio: 4, attack: 0.006, release: 0.14 } },
      { name: 'Bass', volume: 0.86, pan: 0, low: 1.5, mid: -0.5, high: 1, comp: { threshold: -18, ratio: 3 } },
      { name: 'Guitar', volume: 0.7, pan: 0.22, low: -2, mid: 1, high: 1 }
    ]
  },
  {
    id: 'electronic-setup',
    name: 'Electronic Setup',
    summary: 'Drums, bass, synth and an FX return for club-ready productions.',
    tempo: 124,
    suggested: false,
    tracks: [
      { name: 'Drums', volume: 0.9, pan: 0, low: 2, mid: -1, high: 1.5, comp: { threshold: -20, ratio: 4, attack: 0.006, release: 0.14 } },
      { name: 'Bass', volume: 0.85, pan: 0, low: 1.5, mid: -0.5, high: 1, comp: { threshold: -18, ratio: 3 } },
      { name: 'Synth', volume: 0.78, pan: -0.15, low: -1, mid: 1.5, high: 0.5 },
      { name: 'FX', volume: 0.55, pan: 0.3, low: -3, mid: 0, high: 2 }
    ]
  },
  {
    id: 'vocal-and-backing',
    name: 'Vocal and Backing',
    summary: 'A lead vocal with a tucked-back double over a rhythm section.',
    tempo: 78,
    suggested: false,
    tracks: [
      { name: 'Lead Vocal', volume: 0.95, pan: 0, low: -1.5, mid: 2, high: 2.5, comp: { threshold: -22, ratio: 3 } },
      { name: 'Backing', volume: 0.62, pan: -0.25, low: -2, mid: 0.5, high: 1 },
      { name: 'Drums', volume: 0.85, pan: 0, low: 2, mid: -1, high: 1.5 },
      { name: 'Bass', volume: 0.82, pan: 0, low: 1.5, mid: -0.5, high: 1 }
    ]
  }
];

export function createSessionFromTemplate(template, name) {
  const session = createSession(name || template.name);
  session.tempo = clamp(Number(template.tempo) || 120, 60, 200);
  session.templateId = template.id;
  session.tracks = template.tracks.map((slot, index) => {
    const track = createTrack({ name: slot.name, index });
    track.colorIndex = Number.isFinite(slot.colorIndex) ? slot.colorIndex : index;
    track.volume = clamp(Number(slot.volume ?? 1), 0, 1);
    track.pan = clamp(Number(slot.pan ?? 0), -1, 1);
    if (slot.eq) {
      track.eq = JSON.parse(JSON.stringify(slot.eq));
    } else {
      track.eq.low.gain = Number(slot.low ?? 0);
      track.eq.mid.gain = Number(slot.mid ?? 0);
      track.eq.high.gain = Number(slot.high ?? 0);
    }
    if (slot.comp) {
      track.comp = { ...track.comp, ...JSON.parse(JSON.stringify(slot.comp)) };
      if (slot.low !== undefined || slot.mid !== undefined || slot.high !== undefined) track.comp.bypassed = false;
    }
    return track;
  });
  return session;
}

const CUSTOM_TEMPLATES_KEY = 'ai-studio.web.custom-templates.v1';

export function loadCustomTemplates() {
  try {
    const parsed = JSON.parse(localStorage.getItem(CUSTOM_TEMPLATES_KEY) || '[]');
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    console.warn('Could not read custom templates', error);
    return [];
  }
}

export function saveCustomTemplates(templates) {
  try {
    localStorage.setItem(CUSTOM_TEMPLATES_KEY, JSON.stringify(templates));
  } catch (error) {
    console.warn('Could not save custom templates', error);
  }
}

export function createCustomTemplate(session, name) {
  return {
    id: uid(),
    name: name || `${session.name} Template`,
    summary: `Captured from ${session.name}: ${session.tracks.length} tracks with their mixer settings.`,
    tempo: session.tempo,
    suggested: false,
    custom: true,
    tracks: session.tracks.map((track) => ({
      name: track.name,
      colorIndex: track.colorIndex,
      volume: track.volume,
      pan: track.pan,
      eq: JSON.parse(JSON.stringify(track.eq)),
      comp: JSON.parse(JSON.stringify(track.comp))
    }))
  };
}

export function playbackClips(track) {
  if (track.frozen && track.frozen.fileId && track.frozen.duration > 0) {
    return [{
      id: `${track.id}-frozen`,
      name: `${track.name} (Frozen)`,
      fileId: track.frozen.fileId,
      start: 0,
      duration: track.frozen.duration,
      sourceStart: 0,
      sourceDuration: track.frozen.duration,
      frozen: true
    }];
  }
  return track.clips;
}

export const ARPEGGIATOR_PATTERNS = [
  { id: 'up', name: 'UP' },
  { id: 'down', name: 'DOWN' },
  { id: 'upDown', name: 'UP-DOWN' },
  { id: 'random', name: 'RND' }
];

export const ARPEGGIATOR_RATES = [
  { id: '1/8', name: '1/8' },
  { id: '1/16', name: '1/16' },
  { id: '1/32', name: '1/32' }
];

export function defaultArpeggiator() {
  return { enabled: false, pattern: 'up', rate: '1/16', octaves: 1, gate: 0.7, swing: 0 };
}

function normalizeArpeggiator(arpeggiator) {
  const defaults = defaultArpeggiator();
  const value = arpeggiator && typeof arpeggiator === 'object' ? arpeggiator : {};
  return {
    enabled: value.enabled === true,
    pattern: ARPEGGIATOR_PATTERNS.some((item) => item.id === value.pattern) ? value.pattern : defaults.pattern,
    rate: ARPEGGIATOR_RATES.some((item) => item.id === value.rate) ? value.rate : defaults.rate,
    octaves: Math.round(clamp(Number(value.octaves ?? defaults.octaves), 1, 4)),
    gate: clamp(Number(value.gate ?? defaults.gate), 0.05, 1),
    swing: clamp(Number(value.swing ?? defaults.swing), 0, 0.4)
  };
}

export function arpeggiatorStepDuration(settings, tempo) {
  const tempoSafe = clamp(Number(tempo) || 120, 60, 200);
  const rate = normalizeArpeggiator(settings).rate;
  const beats = rate === '1/8' ? 0.5 : rate === '1/32' ? 0.125 : 0.25;
  return 60 / tempoSafe * beats;
}

function shuffledPitches(pitches, seed) {
  const values = [...pitches];
  let state = (seed + 1) >>> 0;
  for (let index = values.length - 1; index > 0; index -= 1) {
    state = (state * 1_664_525 + 1_013_904_223) >>> 0;
    const target = state % (index + 1);
    [values[index], values[target]] = [values[target], values[index]];
  }
  return values;
}

/// Turns held chord notes into arpeggios for playback and offline rendering.
export function arpeggiate(notes, arpeggiator, tempo) {
  const arp = normalizeArpeggiator(arpeggiator);
  if (!arp.enabled || !Array.isArray(notes) || !notes.length) return notes;

  const step = Math.max(0.01, arpeggiatorStepDuration(arp, tempo));
  const tolerance = step / 2;
  const sorted = [...notes].sort((left, right) => left.start - right.start);

  const clusters = [];
  for (const note of sorted) {
    const last = clusters[clusters.length - 1];
    if (last) {
      const clusterStart = Math.min(...last.map((item) => item.start));
      if (Math.abs(note.start - clusterStart) <= tolerance) {
        last.push(note);
        continue;
      }
    }
    clusters.push([note]);
  }

  const result = [];
  clusters.forEach((cluster, clusterIndex) => {
    const start = Math.min(...cluster.map((item) => item.start));
    const end = Math.max(...cluster.map((item) => item.start + item.duration));
    const velocity = Math.max(...cluster.map((item) => Number(item.velocity ?? 0.8)));
    const base = [...new Set(cluster.map((item) => item.pitch))].sort((a, b) => a - b);
    if (!base.length) return;

    const pitches = [];
    for (let octave = 0; octave < arp.octaves; octave += 1) {
      base.forEach((pitch) => pitches.push(pitch + 12 * octave));
    }

    let order;
    switch (arp.pattern) {
      case 'down':
        order = [...pitches].reverse();
        break;
      case 'upDown':
        order = pitches.length > 2 ? [...pitches, ...pitches.slice(1, -1).reverse()] : pitches;
        break;
      case 'random':
        order = shuffledPitches(pitches, clusterIndex);
        break;
      default:
        order = pitches;
    }

    let stepIndex = 0;
    for (let time = start; time < end - 0.001; time += step) {
      const swingOffset = stepIndex % 2 === 1 ? arp.swing * step : 0;
      const noteStart = time + swingOffset;
      const duration = Math.min(step * arp.gate, end - noteStart);
      if (duration >= 0.02) {
        result.push({
          id: `${cluster[0].id || 'arp'}-${clusterIndex}-${stepIndex}`,
          pitch: order[stepIndex % order.length],
          start: Math.max(0, noteStart),
          duration,
          velocity
        });
      }
      stepIndex += 1;
    }
  });

  return result.sort((left, right) => left.start - right.start);
}

/// The notes as they actually play, after the track's arpeggiator.
export function playedNotes(track, tempo) {
  return arpeggiate(sequencedNotes(track), track.arpeggiator, tempo);
}

export function sequencedNotes(track) {
  return track.frozen && track.frozen.fileId ? [] : track.notes;
}

export function clipPlaybackRate(clip, tempo = 120) {
  const sourceTempo = Number(clip?.sourceTempoBPM);
  if (!Number.isFinite(sourceTempo) || sourceTempo <= 0) return 1;
  return clamp(clamp(Number(tempo) || 120, 60, 200) / clamp(sourceTempo, 60, 200), 0.25, 4);
}

export function clipTimelineDuration(clip, tempo = 120) {
  const sourceLength = Math.min(Number(clip?.duration) || 0, Math.max(0, (Number(clip?.sourceDuration) || 0) - (Number(clip?.sourceStart) || 0)));
  return sourceLength / clipPlaybackRate(clip, tempo);
}

export function clipSourceOffset(clip, timelineOffset, tempo = 120) {
  return Math.max(0, Number(timelineOffset) || 0) * clipPlaybackRate(clip, tempo);
}

export function trackDuration(track, tempo = 120) {
  let end = 0;
  for (const clip of playbackClips(track)) {
    const playable = clipTimelineDuration(clip, tempo);
    end = Math.max(end, Math.max(0, clip.start) + playable);
  }
  for (const note of sequencedNotes(track)) {
    end = Math.max(end, note.start + note.duration);
  }
  return end;
}

export function sessionDuration(session) {
  let end = 0;
  for (const track of session.tracks) {
    end = Math.max(end, trackDuration(track, session.tempo));
  }
  return end;
}

export function hasLoopRange(session) {
  return session.loop.end - session.loop.start > 0.01;
}

/// The gain of a clip at an absolute timeline moment, including its own fades
/// and automatic crossfades with the clips it overlaps.
export function clipGainAt(clip, track, time, tempo = 120) {
  const start = Math.max(0, clip.start);
  const playable = clipTimelineDuration(clip, tempo);
  const local = time - start;
  if (local < 0 || local > playable) return 0;

  let gain = 1;
  const fadeIn = Math.max(0, Number(clip.fadeIn) || 0);
  const fadeOut = Math.max(0, Number(clip.fadeOut) || 0);
  if (fadeIn > 0 && local < fadeIn) gain *= local / fadeIn;
  if (fadeOut > 0 && local > playable - fadeOut) gain *= (playable - local) / fadeOut;

  const others = (track.clips || [])
    .filter((item) => item.id !== clip.id)
    .sort((left, right) => left.start - right.start);
  const previous = [...others].reverse().find((item) => item.start <= start);
  const previousEnd = previous
    ? previous.start + clipTimelineDuration(previous, tempo)
    : 0;
  if (previous && previousEnd > start) {
    const overlap = previousEnd - start;
    if (local < overlap && overlap > 0) gain *= 0.5 + 0.5 * (local / overlap);
  }
  const next = others.find((item) => item.start > start);
  if (next && next.start < start + playable) {
    const overlap = start + playable - next.start;
    const remaining = playable - local;
    if (remaining < overlap && overlap > 0) gain *= 0.5 + 0.5 * (remaining / overlap);
  }
  return clamp(gain, 0, 1);
}

export function automationGain(track, time) {  const points = [...(track.automation || [])].sort((a, b) => a.time - b.time);
  if (!points.length) return 1;
  const first = points[0];
  if (time <= first.time) return clamp(first.gain, 0, 1);

  for (let i = 1; i < points.length; i += 1) {
    const left = points[i - 1];
    const right = points[i];
    if (time > right.time) continue;
    const span = right.time - left.time;
    if (span <= 0) return clamp(right.gain, 0, 1);
    let progress = clamp((time - left.time) / span, 0, 1);
    progress = progress * progress * (3 - 2 * progress);
    const from = clamp(left.gain, 0, 1);
    const to = clamp(right.gain, 0, 1);
    return from + (to - from) * progress;
  }

  return clamp(points[points.length - 1].gain, 0, 1);
}

/// The value of a volume or pan automation lane at a moment in time.
export function automationValue(points, time, key) {
  const list = [...(points || [])].sort((a, b) => a.time - b.time);
  if (!list.length) return null;

  const first = list[0];
  if (time <= first.time) return first[key];

  for (let index = 1; index < list.length; index += 1) {
    const left = list[index - 1];
    const right = list[index];
    if (time > right.time) continue;
    const span = right.time - left.time;
    const progress = clamp((time - left.time) / (span || 1), 0, 1);
    const eased = progress * progress * (3 - 2 * progress);
    return left[key] + (right[key] - left[key]) * eased;
  }

  return list[list.length - 1][key];
}

export function normalizeSession(session) {
  const normal = session || createSession();
  normal.id = normal.id || uid();
  normal.name = normal.name || 'Untitled Session';
  normal.templateId = normal.templateId || null;
  normal.tempo = clamp(Number(normal.tempo) || 120, 60, 200);
  normal.masterVolume = clamp(Number(normal.masterVolume ?? 1), 0, 1);
  normal.masterEffects = normal.masterEffects || {};
  normal.masterEffects.bypassed = normal.masterEffects.bypassed !== false;
  normal.masterEffects.reverbMix = clamp(Number(normal.masterEffects.reverbMix ?? 0.32), 0, 1);
  normal.masterEffects.reverbDecay = clamp(Number(normal.masterEffects.reverbDecay ?? 1.8), 0.2, 5);
  normal.masterEffects.delayBeats = clamp(Number(normal.masterEffects.delayBeats ?? 0.5), 0.25, 2);
  normal.masterEffects.delayFeedback = clamp(Number(normal.masterEffects.delayFeedback ?? 0.38), 0, 0.9);
  normal.masterEffects.delayMix = clamp(Number(normal.masterEffects.delayMix ?? 0.22), 0, 1);
  const auxDefaults = defaultAuxBuses();
  normal.auxA = normalizeAuxBus(normal.auxA, auxDefaults.auxA);
  normal.auxB = normalizeAuxBus(normal.auxB, auxDefaults.auxB);
  normal.mastering = normalizeMastering(normal.mastering);
  normal.loop = normal.loop || { start: 0, end: 0, enabled: false };
  normal.loop.start = Math.max(0, Number(normal.loop.start) || 0);
  normal.loop.end = Math.max(normal.loop.start, Number(normal.loop.end) || 0);
  normal.loop.enabled = Boolean(normal.loop.enabled);
  normal.metronome = normal.metronome || { enabled: false, level: 0.7, countIn: false };
  normal.punch = normal.punch || { enabled: false, in: 0, out: 0, armedTrackId: null };
  normal.punch.enabled = Boolean(normal.punch.enabled);
  normal.punch.in = Math.max(0, Number(normal.punch.in) || 0);
  normal.punch.out = Math.max(0, Number(normal.punch.out) || 0);
  normal.punch.armedTrackId = normal.punch.armedTrackId || null;
  normal.metronome.level = clamp(Number(normal.metronome.level ?? 0.7), 0, 1);
  normal.metronome.enabled = Boolean(normal.metronome.enabled);
  normal.metronome.countIn = Boolean(normal.metronome.countIn);
  const storedDrumPattern = normal.drumPattern && typeof normal.drumPattern === 'object' && !Array.isArray(normal.drumPattern)
    ? normal.drumPattern
    : {};
  normal.drumPattern = Object.fromEntries(DRUM_VOICE_IDS.map((voice) => {
    const steps = storedDrumPattern[voice];
    return [voice, Array.from({ length: DRUM_STEP_COUNT }, (_, index) => Boolean(Array.isArray(steps) && steps[index]))];
  }));
  normal.sections = Array.isArray(normal.sections) ? normal.sections : [];
  normal.sections.forEach((section) => {
    section.id = section.id || uid();
    section.name = section.name || 'Section';
    section.time = Math.max(0, Number(section.time) || 0);
  });
  normal.sections.sort((a, b) => a.time - b.time);
  normal.groups = Array.isArray(normal.groups) ? normal.groups : [];
  normal.tracks = Array.isArray(normal.tracks) ? normal.tracks : [];
  normal.editedAt = normal.editedAt || Date.now();

  normal.tracks.forEach((track, index) => {
    track.id = track.id || uid();
    track.name = track.name || `Track ${index + 1}`;
    track.colorIndex = Number.isFinite(track.colorIndex) ? track.colorIndex : index;
    track.volume = clamp(Number(track.volume ?? 1), 0, 1);
    track.pan = clamp(Number(track.pan ?? 0), -1, 1);
    track.muted = Boolean(track.muted);
    track.soloed = Boolean(track.soloed);
    track.sendA = clamp(Number(track.sendA ?? 0), 0, 1);
    track.sendB = clamp(Number(track.sendB ?? 0), 0, 1);
    track.arpeggiator = normalizeArpeggiator(track.arpeggiator);
    track.voice = VOICES.some((voice) => voice.id === track.voice) ? track.voice : 'synth';
    const storedPreset = presetById(track.presetId);
    track.presetId = storedPreset && storedPreset.voice === track.voice ? storedPreset.id : null;
    track.guitarTone = normalizeGuitarTone(track.guitarTone);
    track.eq = track.eq || defaultEQ();
    track.eq.bypassed = Boolean(track.eq.bypassed);
    track.eq.low = track.eq.low || { frequency: 120, gain: 0 };
    track.eq.mid = track.eq.mid || { frequency: 1000, gain: 0 };
    track.eq.high = track.eq.high || { frequency: 8000, gain: 0 };
    track.comp = track.comp || defaultCompressor();
    track.comp.bypassed = track.comp.bypassed !== false;
    track.effectsRack = normalizeTrackEffectsRack(track.effectsRack);
    track.automation = Array.isArray(track.automation) ? track.automation : [];
    track.panAutomation = Array.isArray(track.panAutomation) ? track.panAutomation : [];
    track.clips = Array.isArray(track.clips) ? track.clips : [];
    track.clips.forEach((clip) => {
      clip.id = clip.id || uid();
      clip.start = Math.max(0, Number(clip.start) || 0);
      clip.sourceStart = Math.max(0, Number(clip.sourceStart) || 0);
      clip.duration = Math.max(0, Number(clip.duration) || 0);
      clip.sourceDuration = Math.max(
        clip.sourceStart,
        Number.isFinite(Number(clip.sourceDuration))
          ? Number(clip.sourceDuration)
          : clip.sourceStart + clip.duration
      );
      clip.duration = Math.min(clip.duration, Math.max(0, clip.sourceDuration - clip.sourceStart));
      const sourceTempo = Number(clip.sourceTempoBPM);
      clip.sourceTempoBPM = Number.isFinite(sourceTempo) && sourceTempo > 0
        ? clamp(sourceTempo, 60, 200)
        : null;
      clip.transposeSemitones = clamp(Math.round(Number(clip.transposeSemitones) || 0), -12, 12);
      clip.fadeIn = Math.max(0, Number(clip.fadeIn) || 0);
      clip.fadeOut = Math.max(0, Number(clip.fadeOut) || 0);
    });
    track.takes = Array.isArray(track.takes) ? track.takes : [];
    track.activeTakeId = track.activeTakeId || null;
    track.notes = Array.isArray(track.notes) ? track.notes : [];
    track.frozen = track.frozen || { fileId: null, duration: 0 };
    track.frozen.fileId = track.frozen.fileId || null;
    track.frozen.duration = Math.max(0, Number(track.frozen.duration) || 0);
    track.notes.forEach((note) => {
      note.velocity = clamp(Number(note.velocity ?? 0.8), 0.05, 1);
    });
  });

  const validTrackIDs = new Set(normal.tracks.map((track) => track.id));
  const claimedTrackIDs = new Set();
  normal.groups = normal.groups.map((group, index) => {
    group.id = group.id || uid();
    group.name = group.name || `Group ${index + 1}`;
    group.colorIndex = Number.isFinite(group.colorIndex) ? group.colorIndex : index;
    group.volume = clamp(Number(group.volume ?? 1), 0, 1);
    group.muted = Boolean(group.muted);
    group.soloed = Boolean(group.soloed);
    group.trackIDs = Array.isArray(group.trackIDs)
      ? group.trackIDs.filter((id) => validTrackIDs.has(id) && !claimedTrackIDs.has(id))
      : [];
    group.trackIDs.forEach((id) => claimedTrackIDs.add(id));
    return group;
  }).filter((group) => group.trackIDs.length > 0);

  return normal;
}

// ---------- Session persistence (localStorage) ----------

const STORE_KEY = 'ai-studio.web.store.v1';

export function loadStore() {
  try {
    const raw = localStorage.getItem(STORE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      if (parsed && Array.isArray(parsed.sessions) && parsed.sessions.length) {
        const sessions = parsed.sessions.map(normalizeSession);
        const activeId = sessions.some((s) => s.id === parsed.activeId) ? parsed.activeId : sessions[0].id;
        const needsDemo = parsed.houseDemoSeeded !== true
          && !sessions.some((session) => session.templateId === 'house-demo');
        return { sessions, activeId, needsDemo, houseDemoSeeded: parsed.houseDemoSeeded === true };
      }
    }
  } catch (error) {
    console.warn('Could not read saved sessions', error);
  }

  const session = createSession();
  return { sessions: [session], activeId: session.id, needsDemo: true, houseDemoSeeded: false };
}

export function saveStore(store) {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify({
      sessions: store.sessions,
      activeId: store.activeId,
      houseDemoSeeded: store.houseDemoSeeded !== false
    }));
  } catch (error) {
    console.warn('Could not save sessions', error);
  }
}

// ---------- Audio file storage (IndexedDB) ----------

const DB_NAME = 'ai-studio.web.audio';
const DB_VERSION = 3;
const DB_STORE = 'files';
const DB_EXPORT_STORE = 'exports';
const DB_VERSION_STORE = 'versions';
let dbPromise = null;

function openDb() {
  if (!dbPromise) {
    dbPromise = new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains(DB_STORE)) {
          db.createObjectStore(DB_STORE);
        }
        if (!db.objectStoreNames.contains(DB_EXPORT_STORE)) {
          db.createObjectStore(DB_EXPORT_STORE);
        }
        if (!db.objectStoreNames.contains(DB_VERSION_STORE)) {
          db.createObjectStore(DB_VERSION_STORE);
        }
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }
  return dbPromise;
}

async function withStore(mode, action, storeName = DB_STORE) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(storeName, mode);
    const store = transaction.objectStore(storeName);
    const request = action(store);
    let result;
    request.onsuccess = () => { result = request.result; };
    request.onerror = () => reject(request.error);
    transaction.oncomplete = () => resolve(result);
    transaction.onerror = () => reject(transaction.error || request.error);
    transaction.onabort = () => reject(transaction.error || new Error('IndexedDB transaction was aborted'));
  });
}

export function saveFile(blob, name = 'audio') {
  const id = uid();
  return withStore('readwrite', (store) => store.put({ blob, name }, id)).then(() => id);
}

export function loadFile(id) {
  return withStore('readonly', (store) => store.get(id)).then((entry) => entry || null);
}

export function removeFile(id) {
  return withStore('readwrite', (store) => store.delete(id));
}

export function saveExport(exportItem) {
  const id = uid();
  const entry = { ...exportItem, id };
  return withStore('readwrite', (store) => store.put(entry, id), DB_EXPORT_STORE).then(() => id);
}

export function listExports() {
  return withStore('readonly', (store) => store.getAll(), DB_EXPORT_STORE)
    .then((entries) => entries.sort((left, right) => right.createdAt - left.createdAt));
}

export function removeExport(id) {
  return withStore('readwrite', (store) => store.delete(id), DB_EXPORT_STORE);
}

export async function renameExport(id, name) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(DB_EXPORT_STORE, 'readwrite');
    const store = transaction.objectStore(DB_EXPORT_STORE);
    const request = store.get(id);
    let renamed = false;

    request.onsuccess = () => {
      const entry = request.result;
      if (!entry) return;
      store.put({ ...entry, name }, id);
      renamed = true;
    };
    transaction.oncomplete = () => resolve(renamed);
    transaction.onerror = () => reject(transaction.error || request.error);
    transaction.onabort = () => reject(transaction.error || new Error('IndexedDB transaction was aborted'));
  });
}

// ---------- Session versions (IndexedDB) ----------

export function saveVersion(version) {
  const id = uid();
  const entry = { ...version, id };
  return withStore('readwrite', (store) => store.put(entry, id), DB_VERSION_STORE).then(() => id);
}

export function listVersions() {
  return withStore('readonly', (store) => store.getAll(), DB_VERSION_STORE)
    .then((entries) => entries.sort((left, right) => right.createdAt - left.createdAt));
}

export function removeVersion(id) {
  return withStore('readwrite', (store) => store.delete(id), DB_VERSION_STORE);
}

export async function removeVersionsForSession(sessionId) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(DB_VERSION_STORE, 'readwrite');
    const store = transaction.objectStore(DB_VERSION_STORE);
    const request = store.openCursor();

    request.onsuccess = () => {
      const cursor = request.result;
      if (!cursor) return;
      if (cursor.value && cursor.value.sessionId === sessionId) cursor.delete();
      cursor.continue();
    };
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error || request.error);
    transaction.onabort = () => reject(transaction.error || new Error('IndexedDB transaction was aborted'));
  });
}


// ---------- Standard MIDI files ----------

export const MIDI_TICKS_PER_QUARTER = 480;

function encodeVariableLength(value) {
  let remaining = Math.max(0, Math.floor(Number(value) || 0));
  const bytes = [remaining & 0x7f];
  remaining >>= 7;
  while (remaining > 0) {
    bytes.unshift((remaining & 0x7f) | 0x80);
    remaining >>= 7;
  }
  return bytes;
}

function midiBytes(text, limit) {
  const encoded = [...new TextEncoder().encode(String(text || ''))];
  return encoded.slice(0, Math.max(0, limit));
}

function midiFileName(name) {
  const base = String(name || 'Track').replace(/[^\w\-. ]+/g, '').trim().slice(0, 60) || 'Track';
  return `${base}.mid`;
}

/// Writes a track's sequenced notes as a format 0 MIDI file at the session tempo.
export function encodeMidi(track, tempo) {
  const bpm = clamp(Math.round(Number(tempo) || 120), 60, 200);
  const secondsPerBeat = 60 / bpm;
  const toTick = (seconds) => Math.max(0, Math.round((Math.max(0, Number(seconds) || 0) / secondsPerBeat) * MIDI_TICKS_PER_QUARTER));

  const events = [];
  const microseconds = Math.round(60000000 / bpm);
  events.push({
    tick: 0,
    order: 0,
    bytes: [0xff, 0x51, 0x03, (microseconds >> 16) & 0xff, (microseconds >> 8) & 0xff, microseconds & 0xff]
  });

  const nameBytes = midiBytes(track?.name || 'Track', 127);
  if (nameBytes.length) {
    events.push({ tick: 0, order: 1, bytes: [0xff, 0x03, nameBytes.length, ...nameBytes] });
  }

  (track?.notes || []).forEach((note) => {
    const pitch = clamp(Math.round(Number(note.pitch) || 0), 0, 127);
    const velocity = clamp(Math.round((Number(note.velocity) || 0.8) * 127), 1, 127);
    const start = toTick(note.start);
    const end = Math.max(start + 1, toTick((Number(note.start) || 0) + (Number(note.duration) || 0)));
    events.push({ tick: start, order: 2, bytes: [0x90, pitch, velocity] });
    events.push({ tick: end, order: 0, bytes: [0x80, pitch, 0] });
  });

  events.sort((left, right) => (left.tick - right.tick) || (left.order - right.order));

  const trackData = [];
  let lastTick = 0;
  events.forEach((event) => {
    trackData.push(...encodeVariableLength(event.tick - lastTick), ...event.bytes);
    lastTick = event.tick;
  });
  trackData.push(0x00, 0xff, 0x2f, 0x00);

  const header = [
    0x4d, 0x54, 0x68, 0x64, // MThd
    0x00, 0x00, 0x00, 0x06,
    0x00, 0x00, // format 0
    0x00, 0x01, // one track
    (MIDI_TICKS_PER_QUARTER >> 8) & 0xff, MIDI_TICKS_PER_QUARTER & 0xff
  ];
  const chunk = [
    0x4d, 0x54, 0x72, 0x6b, // MTrk
    (trackData.length >>> 24) & 0xff,
    (trackData.length >>> 16) & 0xff,
    (trackData.length >>> 8) & 0xff,
    trackData.length & 0xff
  ];

  return new Uint8Array([...header, ...chunk, ...trackData]);
}

/// Reads a standard MIDI file into notes, its track name and its tempo.
export function parseMidi(buffer) {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  let index = 0;

  const readU8 = () => {
    if (index >= bytes.length) throw new Error('That MIDI file is incomplete');
    const value = bytes[index];
    index += 1;
    return value;
  };
  const readU16 = () => (readU8() << 8) | readU8();
  const readU32 = () => ((readU8() << 24) | (readU8() << 16) | (readU8() << 8) | readU8()) >>> 0;
  const readVar = () => {
    let value = 0;
    for (let count = 0; count < 4; count += 1) {
      const byte = readU8();
      value = (value << 7) | (byte & 0x7f);
      if ((byte & 0x80) === 0) return value;
    }
    return value;
  };
  const match = (text) => {
    const expected = [...text].map((char) => char.charCodeAt(0));
    if (index + expected.length > bytes.length) return false;
    for (let offset = 0; offset < expected.length; offset += 1) {
      if (bytes[index + offset] !== expected[offset]) return false;
    }
    index += expected.length;
    return true;
  };

  if (!match('MThd')) throw new Error('That file is not a MIDI file');

  const headerLength = readU32();
  readU16(); // format
  const trackCount = readU16();
  const division = readU16();
  if (!division || (division & 0x8000)) throw new Error('That MIDI file uses an unsupported time division');
  index = Math.min(bytes.length, 8 + headerLength);

  let tempo = 120;
  let tempoFound = false;
  let name = null;
  const rawNotes = [];

  for (let chunk = 0; chunk < trackCount; chunk += 1) {
    if (index + 8 > bytes.length) break;
    if (!match('MTrk')) throw new Error('That MIDI file has an unreadable track');

    const length = readU32();
    const end = Math.min(bytes.length, index + length);
    let tickTime = 0;
    let running = 0;
    const open = new Map();

    while (index < end) {
      tickTime += readVar();
      if (index >= end) break;

      const status = bytes[index];
      let kind;
      if (status >= 0x80) {
        index += 1;
        kind = status;
        if (kind < 0xf0) running = kind;
      } else {
        kind = running;
      }
      if (kind < 0x80) break;

      if (kind === 0xff) {
        const type = readU8();
        const metaLength = readVar();
        const payloadStart = index;
        index = Math.min(end, index + metaLength);
        const payload = bytes.subarray(payloadStart, index);

        if (type === 0x51 && payload.length >= 3 && !tempoFound) {
          const value = (payload[0] << 16) | (payload[1] << 8) | payload[2];
          if (value > 0) {
            tempo = 60000000 / value;
            tempoFound = true;
          }
        } else if (type === 0x03 && !name) {
          const text = new TextDecoder().decode(payload).trim();
          if (text) name = text;
        } else if (type === 0x2f) {
          break;
        }
        continue;
      }

      if (kind === 0xf0 || kind === 0xf7) {
        const sysexLength = readVar();
        index = Math.min(end, index + sysexLength);
        continue;
      }

      const command = kind & 0xf0;
      if (command === 0x80 || command === 0x90) {
        const pitch = readU8();
        const velocity = readU8();
        if (command === 0x90 && velocity > 0) {
          const stack = open.get(pitch) || [];
          stack.push({ start: tickTime, velocity });
          open.set(pitch, stack);
        } else {
          const stack = open.get(pitch);
          const started = stack && stack.pop();
          if (started) rawNotes.push({ pitch, start: started.start, end: tickTime, velocity: started.velocity });
        }
      } else if (command === 0xa0 || command === 0xb0 || command === 0xe0) {
        readU8();
        readU8();
      } else if (command === 0xc0 || command === 0xd0) {
        readU8();
      } else {
        break;
      }
    }

    open.forEach((stack, pitch) => {
      stack.forEach((started) => {
        rawNotes.push({ pitch, start: started.start, end: tickTime, velocity: started.velocity });
      });
    });

    index = end;
  }

  if (!rawNotes.length) throw new Error('That MIDI file has no notes in it');

  const secondsPerTick = (60 / tempo) / division;
  const notes = rawNotes
    .map((note) => ({
      id: uid(),
      pitch: clamp(note.pitch, 0, 127),
      start: Math.max(0, note.start * secondsPerTick),
      duration: Math.max(0.05, (note.end - note.start) * secondsPerTick),
      velocity: clamp(note.velocity / 127, 0.05, 1)
    }))
    .sort((left, right) => left.start - right.start);

  return {
    notes,
    name: name || null,
    tempo: clamp(Math.round(tempo), 60, 200)
  };
}

export { midiFileName };


// ---------- Voices and sound presets ----------

export const VOICES = [
  { id: 'synth', name: 'Studio Synth' },
  { id: 'piano', name: 'Piano' },
  { id: 'strings', name: 'String Ensemble' },
  { id: 'organ', name: 'Organ' },
  { id: 'percussion', name: 'Percussion' },
  { id: 'acousticGuitar', name: 'Acoustic Guitar' },
  { id: 'electricGuitar', name: 'Electric Guitar' },
  { id: 'distortedGuitar', name: 'Distorted Guitar' },
  { id: 'bassGuitar', name: 'Bass Guitar' },
  { id: 'marleneVocal', name: 'Marlene Vocal' }
];

export const INSTRUMENT_PRESETS = [
  { id: 'synth-bright-saw', name: 'Bright Saw', detail: 'Cutting saw lead with an open filter', voice: 'synth', waveform: 'sawtooth', brightness: 7200, sustain: 1, attack: 0.012, release: 0.24, vibrato: 0, harmonic: 0.5, level: 1 },
  { id: 'synth-warm-pad', name: 'Warm Pad', detail: 'Soft saw pad that swells in slowly', voice: 'synth', waveform: 'sawtooth', brightness: 1800, sustain: 1.2, attack: 0.24, release: 0.62, vibrato: 0.006, harmonic: 0.4, level: 1 },
  { id: 'synth-square-lead', name: 'Square Lead', detail: 'Hollow square lead for hooks', voice: 'synth', waveform: 'square', brightness: 4200, sustain: 1, attack: 0.02, release: 0.26, vibrato: 0, harmonic: 0.5, level: 0.9 },
  { id: 'synth-sine-bell', name: 'Sine Bell', detail: 'Clean sine with a long ring', voice: 'synth', waveform: 'sine', brightness: 9000, sustain: 1.4, attack: 0.005, release: 0.8, vibrato: 0, harmonic: 0.5, level: 0.85 },

  { id: 'piano-bright-keys', name: 'Bright Keys', detail: 'Hammered piano with a crisp top', voice: 'piano', brightness: 6500, sustain: 1, attack: 0.004, release: 0.18, vibrato: 0, harmonic: 0.35, level: 1 },
  { id: 'piano-soft-upright', name: 'Soft Upright', detail: 'Gentle upright with a rounded edge', voice: 'piano', brightness: 3200, sustain: 0.8, attack: 0.006, release: 0.2, vibrato: 0, harmonic: 0.2, level: 0.95 },
  { id: 'piano-warm-grand', name: 'Warm Grand', detail: 'Full concert grand with long decay', voice: 'piano', brightness: 4200, sustain: 1.3, attack: 0.005, release: 0.28, vibrato: 0, harmonic: 0.28, level: 1 },
  { id: 'piano-felt', name: 'Felt Piano', detail: 'Muted, intimate felt hammers', voice: 'piano', brightness: 1800, sustain: 0.75, attack: 0.01, release: 0.22, vibrato: 0, harmonic: 0.12, level: 0.9 },

  { id: 'strings-legato', name: 'Legato Strings', detail: 'Smooth section that bows in together', voice: 'strings', brightness: 3400, sustain: 1.1, attack: 0.08, release: 0.32, vibrato: 0.008, harmonic: 0.5, level: 0.9 },
  { id: 'strings-cinematic', name: 'Cinematic Strings', detail: 'Wide, dramatic swell with deep vibrato', voice: 'strings', brightness: 4800, sustain: 1.2, attack: 0.14, release: 0.46, vibrato: 0.014, harmonic: 0.55, level: 1 },
  { id: 'strings-soft', name: 'Soft Ensemble', detail: 'Quiet, airy background strings', voice: 'strings', brightness: 2200, sustain: 1, attack: 0.18, release: 0.5, vibrato: 0.006, harmonic: 0.45, level: 0.85 },
  { id: 'strings-bright', name: 'Bright Strings', detail: 'Staccato-ready section with bite', voice: 'strings', brightness: 6800, sustain: 0.9, attack: 0.05, release: 0.24, vibrato: 0.01, harmonic: 0.6, level: 0.9 },

  { id: 'organ-gospel', name: 'Gospel Drawbars', detail: 'Full drawbar organ with a percussive click', voice: 'organ', brightness: 5200, sustain: 1, attack: 0.012, release: 0.12, vibrato: 0.004, harmonic: 0.55, level: 0.95 },
  { id: 'organ-pipe', name: 'Church Pipe', detail: 'Slow speaking pipes with a long tail', voice: 'organ', brightness: 3600, sustain: 1, attack: 0.07, release: 0.32, vibrato: 0.002, harmonic: 0.35, level: 0.9 },
  { id: 'organ-tonewheel', name: 'Tonewheel', detail: 'Rounded vintage organ, no click', voice: 'organ', brightness: 2600, sustain: 1, attack: 0.02, release: 0.18, vibrato: 0.006, harmonic: 0.3, level: 0.9 },
  { id: 'organ-bright', name: 'Bright Organ', detail: 'Thin, cutting organ for stabs', voice: 'organ', brightness: 8000, sustain: 1, attack: 0.008, release: 0.1, vibrato: 0.003, harmonic: 0.7, level: 0.85 },

  { id: 'percussion-marimba', name: 'Marimba', detail: 'Warm wooden bars with a round mallet', voice: 'percussion', brightness: 2400, sustain: 1, attack: 0.003, release: 0.3, vibrato: 0, harmonic: 0.35, level: 1 },
  { id: 'percussion-soft-mallets', name: 'Soft Mallets', detail: 'Dark, gentle tuned percussion', voice: 'percussion', brightness: 1500, sustain: 0.8, attack: 0.004, release: 0.35, vibrato: 0, harmonic: 0.2, level: 0.9 },
  { id: 'percussion-bells', name: 'Tuned Bells', detail: 'Glass bells with a long shimmer', voice: 'percussion', brightness: 6000, sustain: 1.3, attack: 0.002, release: 0.6, vibrato: 0.004, harmonic: 0.6, level: 0.9 },
  { id: 'percussion-wood', name: 'Wood Block', detail: 'Dry, tight wooden strike', voice: 'percussion', brightness: 3200, sustain: 0.35, attack: 0.001, release: 0.08, vibrato: 0, harmonic: 0.15, level: 0.85 },

  { id: 'acoustic-fingerpicked', name: 'Fingerpicked', detail: 'Soft fingertips on steel strings', voice: 'acousticGuitar', brightness: 3200, sustain: 1, attack: 0, release: 0.22, vibrato: 0, harmonic: 0.5, level: 0.95 },
  { id: 'acoustic-strummed', name: 'Strummed Steel', detail: 'Bright, ringing strum', voice: 'acousticGuitar', brightness: 4800, sustain: 1.2, attack: 0, release: 0.24, vibrato: 0, harmonic: 0.6, level: 1 },
  { id: 'acoustic-nylon', name: 'Soft Nylon', detail: 'Warm classical guitar', voice: 'acousticGuitar', brightness: 1900, sustain: 0.9, attack: 0, release: 0.22, vibrato: 0, harmonic: 0.4, level: 0.9 },

  { id: 'electric-clean', name: 'Clean Neck', detail: 'Rounded neck pickup with long sustain', voice: 'electricGuitar', brightness: 2200, sustain: 1.1, attack: 0, release: 0.24, vibrato: 0, harmonic: 0.5, level: 0.95 },
  { id: 'electric-bridge', name: 'Bridge Twang', detail: 'Bright bridge pickup with snap', voice: 'electricGuitar', brightness: 4600, sustain: 0.95, attack: 0, release: 0.22, vibrato: 0, harmonic: 0.6, level: 0.9 },
  { id: 'electric-muted', name: 'Muted', detail: 'Palm-muted short notes', voice: 'electricGuitar', brightness: 1400, sustain: 0.45, attack: 0, release: 0.16, vibrato: 0, harmonic: 0.4, level: 0.85 },

  { id: 'distorted-overdriven', name: 'Overdriven', detail: 'Saturated rhythm voice', voice: 'distortedGuitar', brightness: 2000, sustain: 1, attack: 0, release: 0.26, vibrato: 0, harmonic: 0.5, level: 0.95 },
  { id: 'distorted-lead', name: 'Lead', detail: 'Singing lead with long sustain', voice: 'distortedGuitar', brightness: 2800, sustain: 1.25, attack: 0, release: 0.28, vibrato: 0.006, harmonic: 0.55, level: 0.9 },
  { id: 'distorted-fuzz', name: 'Fuzz', detail: 'Thick, woolly fuzz', voice: 'distortedGuitar', brightness: 1200, sustain: 0.9, attack: 0, release: 0.24, vibrato: 0, harmonic: 0.7, level: 0.85 },

  { id: 'bass-fingered', name: 'Fingered', detail: 'Round fingerstyle bass', voice: 'bassGuitar', brightness: 900, sustain: 1, attack: 0, release: 0.22, vibrato: 0, harmonic: 0.5, level: 1 },
  { id: 'bass-picked', name: 'Picked', detail: 'Bright picked bass with attack', voice: 'bassGuitar', brightness: 1600, sustain: 0.9, attack: 0, release: 0.2, vibrato: 0, harmonic: 0.55, level: 0.95 },
  { id: 'bass-sub', name: 'Sub Bass', detail: 'Deep, dark sub tone', voice: 'bassGuitar', brightness: 500, sustain: 1.25, attack: 0.01, release: 0.26, vibrato: 0, harmonic: 0.35, level: 1 },

  { id: 'vocal-clear', name: 'Clear Lead', detail: 'Focused lead with a steady vibrato', voice: 'marleneVocal', brightness: 2600, sustain: 1, attack: 0.06, release: 0.26, vibrato: 0.011, harmonic: 0.07, level: 1 },
  { id: 'vocal-breathy', name: 'Breathy', detail: 'Airy, intimate delivery', voice: 'marleneVocal', brightness: 2200, sustain: 1, attack: 0.05, release: 0.3, vibrato: 0.014, harmonic: 0.18, level: 0.95 },
  { id: 'vocal-powerful', name: 'Powerful', detail: 'Open and loud with a quick start', voice: 'marleneVocal', brightness: 3200, sustain: 1, attack: 0.03, release: 0.22, vibrato: 0.009, harmonic: 0.04, level: 1 },
  { id: 'vocal-soft', name: 'Soft Vowel', detail: 'Gentle, rounded vowel', voice: 'marleneVocal', brightness: 1800, sustain: 1, attack: 0.09, release: 0.3, vibrato: 0.008, harmonic: 0.1, level: 0.9 }
];

export function presetById(id) {
  return INSTRUMENT_PRESETS.find((preset) => preset.id === id) || null;
}

export function presetsForVoice(voice) {
  return INSTRUMENT_PRESETS.filter((preset) => preset.voice === voice);
}

export function defaultPresetFor(voice) {
  return presetsForVoice(voice)[0] || INSTRUMENT_PRESETS[0];
}

export function presetForTrack(track) {
  const stored = presetById(track && track.presetId);
  if (stored && track.voice === stored.voice) return stored;
  return defaultPresetFor(track && track.voice);
}

export function voiceName(id) {
  const voice = VOICES.find((item) => item.id === id);
  return voice ? voice.name : VOICES[0].name;
}


// ---------- Guitar tone ----------

export const GUITAR_VOICES = ['acousticGuitar', 'electricGuitar', 'distortedGuitar'];

export const GUITAR_TONES = [
  { id: 'clean', name: 'Clean', detail: 'Neck pickup, low gain, plenty of headroom', tone: { gain: 0.3, brightness: 0.55, pickup: 0.3 } },
  { id: 'crunch', name: 'Crunch', detail: 'Mildly broken up rhythm tone', tone: { gain: 0.62, brightness: 0.5, pickup: 0.6 } },
  { id: 'lead', name: 'Lead', detail: 'Saturated bridge tone that sings', tone: { gain: 0.86, brightness: 0.75, pickup: 0.85 } },
  { id: 'fingerpicked', name: 'Fingerpicked', detail: 'Soft, dark and dynamic for picking', tone: { gain: 0.18, brightness: 0.38, pickup: 0.2 } }
];

export function defaultGuitarTone() {
  return { gain: 0.5, brightness: 0.5, pickup: 0.5 };
}

export function normalizeGuitarTone(tone) {
  const value = tone && typeof tone === 'object' ? tone : {};
  const defaults = defaultGuitarTone();
  return {
    gain: clamp(Number(value.gain ?? defaults.gain), 0, 1),
    brightness: clamp(Number(value.brightness ?? defaults.brightness), 0, 1),
    pickup: clamp(Number(value.pickup ?? defaults.pickup), 0, 1)
  };
}

export function guitarTonePresetById(id) {
  return GUITAR_TONES.find((preset) => preset.id === id) || null;
}

export function guitarTonePresetFor(tone) {
  const safe = normalizeGuitarTone(tone);
  return GUITAR_TONES.find((preset) => (
    Math.abs(preset.tone.gain - safe.gain) < 0.01
    && Math.abs(preset.tone.brightness - safe.brightness) < 0.01
    && Math.abs(preset.tone.pickup - safe.pickup) < 0.01
  )) || null;
}

export function isGuitarVoice(voice) {
  return GUITAR_VOICES.includes(voice);
}
