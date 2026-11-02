// Web Audio instrument voices for the web studio's instrument rack.

const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

export const DRUM_PADS = [
  { id: 'kick', name: 'Bass Drum' },
  { id: 'snare', name: 'Snare' },
  { id: 'lowTom', name: 'Low Tom' },
  { id: 'midTom', name: 'Mid Tom' },
  { id: 'highTom', name: 'Hi Tom' },
  { id: 'rimshot', name: 'Rimshot' },
  { id: 'clap', name: 'Clap' },
  { id: 'cowbell', name: 'Cowbell' },
  { id: 'closedHat', name: 'Closed Hat' },
  { id: 'openHat', name: 'Open Hat' },
  { id: 'cymbal', name: 'Cymbal' }
];

export const STARTER_SOUNDS = [
  { file: 'starter-kick-1.wav', name: 'Kick 1' },
  { file: 'starter-kick-2.wav', name: 'Kick 2' },
  { file: 'starter-snare.wav', name: 'Snare' },
  { file: 'starter-clap.wav', name: 'Clap' },
  { file: 'starter-hat.wav', name: 'Hat' },
  { file: 'starter-hat-2.wav', name: 'Hat 2' },
  { file: 'starter-flute-c4.wav', name: 'Flute C4' },
  { file: 'starter-flute-e4.wav', name: 'Flute E4' },
  { file: 'starter-flute-a4.wav', name: 'Flute A4' },
  { file: 'starter-flute-c5.wav', name: 'Flute C5' },
  { file: 'starter-flute-e5.wav', name: 'Flute E5' },
  { file: 'starter-flute-a5.wav', name: 'Flute A5' }
];

export class InstrumentEngine {
  constructor(ctx) {
    this.ctx = ctx;
    this.active = new Set();
    this.noiseBuffer = this.createNoiseBuffer();
  }

  createNoiseBuffer() {
    const rate = this.ctx.sampleRate;
    const buffer = this.ctx.createBuffer(1, Math.floor(rate * 2), rate);
    const data = buffer.getChannelData(0);
    for (let index = 0; index < data.length; index += 1) {
      data[index] = Math.random() * 2 - 1;
    }
    return buffer;
  }

  track(node) {
    this.active.add(node);
    node.onended = () => this.active.delete(node);
  }

  stopAll() {
    for (const node of this.active) {
      try { node.stop(); } catch (error) { /* already stopped */ }
    }
    this.active.clear();
  }

  playSynthNote(frequency, {
    waveform = 'sawtooth',
    cutoff = 6500,
    attack = 0.02,
    release = 0.28,
    duration = 0.7
  } = {}, destination) {
    const ctx = this.ctx;
    const start = ctx.currentTime + 0.005;
    const end = start + Math.max(0.12, duration);

    const osc = ctx.createOscillator();
    osc.type = waveform;
    osc.frequency.value = frequency;

    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = clamp(cutoff, 80, ctx.sampleRate * 0.45);

    const env = ctx.createGain();
    const attackTime = clamp(attack, 0.005, 1);
    const releaseTime = clamp(release, 0.02, 2);
    env.gain.setValueAtTime(0.0001, start);
    env.gain.exponentialRampToValueAtTime(0.2, start + attackTime);
    env.gain.setValueAtTime(0.2, Math.max(start + attackTime + 0.001, end - releaseTime));
    env.gain.exponentialRampToValueAtTime(0.0001, end);

    osc.connect(filter);
    filter.connect(env);
    env.connect(destination);
    osc.start(start);
    osc.stop(end + 0.02);
    this.track(osc);
  }

  playDrum(pad, destination) {
    const start = this.ctx.currentTime + 0.005;
    switch (pad) {
      case 'kick':
        this.tone(start, destination, { type: 'sine', from: 120, to: 45, decay: 0.45, gain: 0.6 });
        break;
      case 'snare':
        this.noise(start, destination, { gain: 0.32, decay: 0.18, filterType: 'bandpass', frequency: 1800, q: 0.9 });
        this.tone(start, destination, { type: 'triangle', from: 210, to: 160, decay: 0.12, gain: 0.22 });
        break;
      case 'lowTom':
        this.tone(start, destination, { type: 'sine', from: 140, to: 80, decay: 0.34, gain: 0.45 });
        break;
      case 'midTom':
        this.tone(start, destination, { type: 'sine', from: 190, to: 110, decay: 0.3, gain: 0.42 });
        break;
      case 'highTom':
        this.tone(start, destination, { type: 'sine', from: 250, to: 150, decay: 0.26, gain: 0.4 });
        break;
      case 'rimshot':
        this.tone(start, destination, { type: 'square', from: 1750, to: 900, decay: 0.05, gain: 0.18 });
        this.noise(start, destination, { gain: 0.18, decay: 0.05, filterType: 'highpass', frequency: 3000 });
        break;
      case 'clap':
        [0, 0.012, 0.026].forEach((delay, index) => {
          this.noise(start + delay, destination, {
            gain: index === 2 ? 0.28 : 0.2,
            decay: index === 2 ? 0.18 : 0.05,
            filterType: 'bandpass',
            frequency: 1400,
            q: 1.2
          });
        });
        break;
      case 'cowbell':
        this.tone(start, destination, { type: 'square', from: 587, to: 587, decay: 0.3, gain: 0.14, filter: { type: 'bandpass', frequency: 800, q: 4 } });
        this.tone(start, destination, { type: 'square', from: 845, to: 845, decay: 0.3, gain: 0.12, filterType: 'bandpass', frequency: 800, q: 3 });
        break;
      case 'closedHat':
        this.noise(start, destination, { gain: 0.24, decay: 0.06, filterType: 'highpass', frequency: 7000 });
        break;
      case 'openHat':
        this.noise(start, destination, { gain: 0.24, decay: 0.3, filterType: 'highpass', frequency: 6500 });
        break;
      case 'cymbal':
        this.noise(start, destination, { gain: 0.24, decay: 1.1, filterType: 'highpass', frequency: 5000 });
        break;
      default:
        break;
    }
  }

  tone(start, destination, { type, from, to, decay, gain, filter: filterSettings }) {
    const ctx = this.ctx;
    const osc = ctx.createOscillator();
    osc.type = type;
    osc.frequency.setValueAtTime(from, start);
    osc.frequency.exponentialRampToValueAtTime(Math.max(20, to), start + decay);

    const env = ctx.createGain();
    env.gain.setValueAtTime(0.0001, start);
    env.gain.exponentialRampToValueAtTime(gain, start + 0.005);
    env.gain.exponentialRampToValueAtTime(0.0001, start + decay);

    let tail = osc;
    if (filterSettings) {
      const filter = ctx.createBiquadFilter();
      filter.type = filterSettings.type;
      filter.frequency.value = filterSettings.frequency;
      filter.Q.value = filterSettings.q ?? 1;
      osc.connect(filter);
      tail = filter;
    }
    tail.connect(env);
    env.connect(destination);
    osc.start(start);
    osc.stop(start + decay + 0.02);
    this.track(osc);
  }

  noise(start, destination, { gain, decay, filterType = 'highpass', frequency = 6000, q = 1 }) {
    const ctx = this.ctx;
    const source = ctx.createBufferSource();
    source.buffer = this.noiseBuffer;
    const filter = ctx.createBiquadFilter();
    filter.type = filterType;
    filter.frequency.value = frequency;
    filter.Q.value = q;
    const env = ctx.createGain();
    env.gain.setValueAtTime(0.0001, start);
    env.gain.exponentialRampToValueAtTime(gain, start + 0.004);
    env.gain.exponentialRampToValueAtTime(0.0001, start + decay);
    source.connect(filter);
    filter.connect(env);
    env.connect(destination);
    source.start(start);
    source.stop(start + decay + 0.02);
    this.track(source);
  }

  playTB303(frequency, {
    waveform = 'sawtooth',
    cutoff = 1250,
    resonance = 0.68,
    envelopeAmount = 0.58,
    decay = 0.42,
    accent = false
  } = {}, destination) {
    const ctx = this.ctx;
    const start = ctx.currentTime + 0.005;
    const duration = clamp(decay, 0.16, 1.2);

    const osc = ctx.createOscillator();
    osc.type = waveform === 'square' ? 'square' : 'sawtooth';
    osc.frequency.value = frequency;

    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.Q.value = clamp(4 + resonance * 18, 1, 24);
    const base = clamp(cutoff, 90, 8000);
    const peak = clamp(base + envelopeAmount * 6000, 90, 12000);
    filter.frequency.setValueAtTime(peak, start);
    filter.frequency.exponentialRampToValueAtTime(base, start + Math.max(0.05, decay));

    const env = ctx.createGain();
    const level = accent ? 0.34 : 0.24;
    env.gain.setValueAtTime(0.0001, start);
    env.gain.exponentialRampToValueAtTime(level, start + 0.005);
    env.gain.exponentialRampToValueAtTime(0.0001, start + decay + 0.06);

    osc.connect(filter);
    filter.connect(env);
    env.connect(destination);
    osc.start(start);
    osc.stop(start + decay + 0.1);
    this.track(osc);
  }

  playBuffer(buffer, destination, gain = 1) {
    const ctx = this.ctx;
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    const env = ctx.createGain();
    env.gain.value = clamp(gain, 0, 1);
    source.connect(env);
    env.connect(destination);
    source.start();
    this.track(source);
    return source;
  }
}
