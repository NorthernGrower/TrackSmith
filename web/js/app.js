// AI Music Studio — web app shell: rendering, interactions and persistence.

import * as model from './model.js';
import { StudioEngine, encodeWav } from './audio-engine.js';
import { InstrumentEngine, DRUM_PADS, STARTER_SOUNDS } from './instruments.js';

const ROW_HEIGHT = 92;
const RULER_HEIGHT = 62;
const SECTION_TOP = 14;
const SECTION_HEIGHT = 24;
const NOTE_HEIGHT = 24;
const ROLL_BEAT_WIDTH = 76;

const engine = new StudioEngine();

const state = {
  store: model.loadStore(),
  session: null,
  mode: 'simple',
  zoom: 70,
  playhead: 0,
  selectedClip: null,
  automationTrack: null,
  automationParam: 'volume',
  selectedAutomationPoint: null,
  rollTrackId: null,
  selectedNote: null,
  rollDivision: 2,
  rollChord: 'single',
  rollQuantizeStrength: 1,
  selectedNotes: [],
  groupSelectionMode: false,
  selectedGroupTrackIDs: [],
  customTemplates: [],
  bounceSettings: null,
  undo: [],
  redo: [],
  buffers: new Map(),
  peaks: new Map(),
  countInActive: false,
  countInTimer: null,
  countInInterval: null,
  countInRemaining: 0,
  freezing: false,
  bouncing: false,
  presets: [],
  instrumentTab: 'synth',
  instrumentTrackId: null,
  synthWaveform: 'sawtooth',
  synthCutoff: 6500,
  synthAttack: 0.02,
  synthRelease: 0.28,
  tb303Waveform: 'sawtooth',
  tb303Cutoff: 1250,
  tb303Resonance: 0.68,
  tb303Envelope: 0.58,
  tb303Decay: 0.42,
  tb303Tuning: 1,
  tb303Level: 0.8,
  tb303Accent: false,
  drumVolume: 0.8,
  drumTuning: 1,
  drumDecay: 1,
  drumTone: 0.65,
  samplerBuffer: null,
  samplerName: null,
  samplerSoundId: null,
  instrumentBus: null,
  instrumentBusContext: null,
  instrumentBusTarget: null,
  instrumentRecorder: null,
  instrumentRecordDestination: null,
  instrumentRecordChunks: [],
  instrumentRecordTrackId: null,
  instrumentRecordStartTime: 0,
  instrumentRecordStartWall: 0,
  instrumentRecordTakeName: null,
  instrumentRecordTimer: null,
  instrumentRecording: false,
  instrumentRecordDuration: 0,
  microphoneStream: null,
  microphoneRecorder: null,
  microphoneRecordTimer: null,
  microphoneRecording: false,
  microphoneFinalizing: false,
  microphoneRequesting: false,
  microphoneRequestID: 0,
  microphoneRecordDuration: 0,
  microphoneRecordStartWall: 0,
  modal: null
};

let instrumentVoice = null;

const el = {
  modeSimpleBtn: document.getElementById('modeSimpleBtn'),
  modeProBtn: document.getElementById('modeProBtn'),
  sessionName: document.getElementById('sessionName'),
  sessionSubtitle: document.getElementById('sessionSubtitle'),
  undoBtn: document.getElementById('undoBtn'),
  redoBtn: document.getElementById('redoBtn'),
  mixerBtn: document.getElementById('mixerBtn'),
  masteringBtn: document.getElementById('masteringBtn'),
  fxBtn: document.getElementById('fxBtn'),
  presetBtn: document.getElementById('presetBtn'),
  sessionsBtn: document.getElementById('sessionsBtn'),
  addTrackBtn: document.getElementById('addTrackBtn'),
  blankTrackBtn: document.getElementById('blankTrackBtn'),
  instrumentTrackBtn: document.getElementById('instrumentTrackBtn'),
  templatesBtn: document.getElementById('templatesBtn'),
  emptyTemplatesBtn: document.getElementById('emptyTemplatesBtn'),
  instrumentsBtn: document.getElementById('instrumentsBtn'),
  stemBounceBtn: document.getElementById('stemBounceBtn'),
  bounceBtn: document.getElementById('bounceBtn'),
  fileInput: document.getElementById('fileInput'),
  emptyImportBtn: document.getElementById('emptyImportBtn'),
  emptyInstrumentTrackBtn: document.getElementById('emptyInstrumentTrackBtn'),
  arrangement: document.getElementById('arrangement'),
  arrGrid: document.getElementById('arrGrid'),
  arrHeads: document.getElementById('arrHeads'),
  arrScroll: document.getElementById('arrScroll'),
  arrContent: document.getElementById('arrContent'),
  ruler: document.getElementById('ruler'),
  rulerCanvas: document.getElementById('rulerCanvas'),
  loopStrip: document.getElementById('loopStrip'),
  sectionLayer: document.getElementById('sectionLayer'),
  sectionBtn: document.getElementById('sectionBtn'),
  loopRegion: document.getElementById('loopRegion'),
  loopStartHandle: document.getElementById('loopStartHandle'),
  loopEndHandle: document.getElementById('loopEndHandle'),
  loopHint: document.getElementById('loopHint'),
  lanes: document.getElementById('lanes'),
  playhead: document.getElementById('playhead'),
  emptyState: document.getElementById('emptyState'),
  progressFill: document.getElementById('progressFill'),
  timecode: document.getElementById('timecode'),
  durationLabel: document.getElementById('durationLabel'),
  playBtn: document.getElementById('playBtn'),
  rewindBtn: document.getElementById('rewindBtn'),
  stopBtn: document.getElementById('stopBtn'),
  loopBtn: document.getElementById('loopBtn'),
  loopRangeLabel: document.getElementById('loopRangeLabel'),
  punchBtn: document.getElementById('punchBtn'),
  punchInBtn: document.getElementById('punchInBtn'),
  punchOutBtn: document.getElementById('punchOutBtn'),
  punchRangeLabel: document.getElementById('punchRangeLabel'),
  punchArm: document.getElementById('punchArm'),
  punchRegion: document.getElementById('punchRegion'),
  metronomeBtn: document.getElementById('metronomeBtn'),
  metronomeLevel: document.getElementById('metronomeLevel'),
  countInBtn: document.getElementById('countInBtn'),
  tempoValue: document.getElementById('tempoValue'),
  tempoDown: document.getElementById('tempoDown'),
  tempoUp: document.getElementById('tempoUp'),
  modalRoot: document.getElementById('modalRoot'),
  toast: document.getElementById('toast'),
  transferOverlay: document.getElementById('transferOverlay'),
  transferLabel: document.getElementById('transferLabel'),
  transferFill: document.getElementById('transferFill'),
  sessionImportInput: document.getElementById('sessionImportInput'),
  midiImportInput: document.getElementById('midiImportInput')
};

let toastTimer = null;
let clipToolbar = null;

// ---------- Utilities ----------

function escapeHtml(text) {
  return String(text ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function beatDuration() {
  return 60 / (state.session?.tempo || 120);
}

function snapTime(time) {
  const beat = beatDuration();
  return Math.max(0, Math.round(time / beat) * beat);
}

function sessionDuration() {
  return state.session ? model.sessionDuration(state.session) : 0;
}

function durationOfTrack(track) {
  return model.trackDuration(track);
}

function trackById(id) {
  return state.session?.tracks.find((track) => track.id === id) || null;
}

function trackColorFor(track, index) {
  const group = state.session?.groups?.find((item) => item.trackIDs.includes(track.id));
  return model.trackColor(group ? group.colorIndex : (track.colorIndex ?? index));
}

function currentPosition() {
  return engine.isPlaying ? engine.getPosition() : engine.position;
}

// ---------- Punch recording ----------

function hasPunchRange() {
  const punch = state.session?.punch;
  return Boolean(punch && punch.out > punch.in + 0.05);
}

function isPunchActiveFor(trackId) {
  const punch = state.session?.punch;
  return Boolean(punch && punch.enabled && hasPunchRange() && punch.armedTrackId === trackId);
}

function trimClipsForPunch(track, punchIn, punchOut, crossFade) {
  const kept = [];
  for (const clip of track.clips) {
    const start = Math.max(0, clip.start);
    const playable = Math.min(clip.duration, Math.max(0, clip.sourceDuration - clip.sourceStart));
    const end = start + playable;
    const cutStart = punchIn + crossFade;
    const cutEnd = punchOut - crossFade;

    if (end <= cutStart || start >= cutEnd) {
      kept.push(clip);
      continue;
    }
    if (start < cutStart) {
      kept.push({ ...clip, duration: cutStart - start });
    }
    if (end > cutEnd) {
      kept.push({
        ...clip,
        id: model.uid(),
        start: cutEnd,
        duration: end - cutEnd,
        sourceStart: clip.sourceStart + (cutEnd - start)
      });
    }
  }
  track.clips = kept;
}

async function applyPunchRecording(track, buffer, position, baseName) {
  if (!isPunchActiveFor(track.id)) return null;
  const punch = state.session.punch;
  const offset = Math.max(0, punch.in - position);
  const length = Math.min(punch.out - punch.in, buffer.duration - offset);
  if (length <= 0.05) return null;

  const sampleRate = buffer.sampleRate;
  const startFrame = Math.floor(offset * sampleRate);
  const frames = Math.max(1, Math.floor(length * sampleRate));
  const channels = buffer.numberOfChannels;
  if (!engine.ctx) return null;

  const sliced = engine.ctx.createBuffer(channels, frames, sampleRate);
  for (let channel = 0; channel < channels; channel += 1) {
    const source = buffer.getChannelData(channel).subarray(startFrame, startFrame + frames);
    sliced.getChannelData(channel).set(source);
  }

  const crossFade = Math.min(0.03, length / 6);
  const fadeFrames = Math.max(1, Math.min(Math.floor(crossFade * sampleRate), Math.floor(frames / 4)));
  for (let channel = 0; channel < channels; channel += 1) {
    const data = sliced.getChannelData(channel);
    for (let frame = 0; frame < fadeFrames; frame += 1) {
      const gain = frame / fadeFrames;
      data[frame] *= gain;
      data[frames - 1 - frame] *= gain;
    }
  }

  const blob = encodeWav(sliced);
  const fileName = `${safeName(baseName)}-punch-${Date.now()}.wav`;
  const fileId = await model.saveFile(blob, fileName);
  state.buffers.set(fileId, sliced);
  engine.buffers.set(fileId, sliced);
  state.peaks.set(fileId, computePeaks(sliced));
  model.saveStore(state.store);

  trimClipsForPunch(track, punch.in, punch.out, crossFade);
  track.clips.push({
    id: model.uid(),
    name: 'Punch',
    fileId,
    start: punch.in,
    duration: length,
    sourceStart: 0,
    sourceDuration: length
  });
  track.clips.sort((left, right) => left.start - right.start);

  return { fileId, name: 'Punch', start: punch.in, duration: length };
}

function toast(message) {
  el.toast.textContent = message;
  el.toast.classList.add('visible');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.toast.classList.remove('visible'), 2200);
}

function download(blob, name) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
}

function safeName(text) {
  return String(text || 'mix').replace(/[^\w\-. ]+/g, '').trim() || 'mix';
}

function startDrag(onMove, onEnd) {
  const move = (event) => onMove(event);
  const end = (event) => {
    window.removeEventListener('pointermove', move);
    window.removeEventListener('pointerup', end);
    window.removeEventListener('pointercancel', end);
    if (onEnd) onEnd(event);
  };
  window.addEventListener('pointermove', move);
  window.addEventListener('pointerup', end);
  window.addEventListener('pointercancel', end);
}

// ---------- Persistence ----------

function persist() {
  if (!state.session) return;
  state.session.editedAt = Date.now();
  const index = state.store.sessions.findIndex((session) => session.id === state.session.id);
  if (index >= 0) state.store.sessions[index] = state.session;
  scheduleSave();
  scheduleVersionSave();
}

let saveTimer = null;
let versionTimer = null;
let lastVersionSignature = '';
const SESSION_VERSION_LIMIT = 30;

function scheduleSave() {
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    model.saveStore(state.store);
    saveTimer = null;
  }, 250);
}

function versionSignature(session) {
  const copy = { ...session };
  delete copy.editedAt;
  return JSON.stringify(copy);
}

function versionTimeLabel(timestamp) {
  try {
    return new Date(timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  } catch (error) {
    return '';
  }
}

function versionDateLabel(timestamp) {
  try {
    return new Date(timestamp).toLocaleDateString([], { month: 'short', day: 'numeric' });
  } catch (error) {
    return '';
  }
}

/// Records the open session a couple of seconds after the last change.
function scheduleVersionSave() {
  if (versionTimer) clearTimeout(versionTimer);
  versionTimer = setTimeout(() => {
    versionTimer = null;
    void recordVersion();
  }, 1800);
}

async function recordVersion({ force = false } = {}) {
  if (!state.session) return null;
  const signature = versionSignature(state.session);
  if (!force && signature === lastVersionSignature) return null;
  lastVersionSignature = signature;

  try {
    await model.saveVersion({
      sessionId: state.session.id,
      createdAt: Date.now(),
      name: state.session.name,
      trackCount: state.session.tracks.length,
      duration: model.sessionDuration(state.session),
      tempo: state.session.tempo,
      sectionCount: state.session.sections.length,
      session: JSON.parse(JSON.stringify(state.session))
    });
    await pruneVersions(state.session.id);
  } catch (error) {
    console.warn('Could not save a session version', error);
  }
  return true;
}

async function pruneVersions(sessionId) {
  try {
    const all = await model.listVersions();
    const mine = all.filter((entry) => entry.sessionId === sessionId);
    const excess = mine.slice(SESSION_VERSION_LIMIT);
    await Promise.all(excess.map((entry) => model.removeVersion(entry.id)));
  } catch (error) {
    console.warn('Could not trim session versions', error);
  }
}

async function ensureInitialVersion() {
  try {
    const versions = await model.listVersions();
    if (!versions.some((version) => version.sessionId === state.session.id)) {
      await recordVersion({ force: true });
    }
  } catch (error) {
    console.warn('Could not check session versions', error);
  }
}

async function restoreVersion(version) {
  if (!version || !state.session) return;
  await recordVersion({ force: true });
  const restored = JSON.parse(JSON.stringify(version.session));
  restored.id = state.session.id;
  restored.name = version.name;
  restored.editedAt = Date.now();
  adoptSession(restored);
}

async function duplicateVersion(version) {
  if (!version) return;
  await recordVersion({ force: true });
  const copy = JSON.parse(JSON.stringify(version.session));
  copy.id = model.uid();
  copy.name = uniqueSessionName(`${version.name} Copy`);
  copy.editedAt = Date.now();
  state.store.sessions.push(copy);
  state.store.activeId = copy.id;
  model.saveStore(state.store);
  closeModal();
  adoptSession(copy);
  toast('Version opened as a new session');
}

function snapshot() {
  state.undo.push(JSON.stringify(state.session));
  if (state.undo.length > 50) state.undo.shift();
  state.redo.length = 0;
  renderTransport();
}

function cloneSession() {
  return JSON.parse(JSON.stringify(state.session));
}

function adoptSession(session) {
  engine.pause();
  cancelCountIn();
  state.session = model.normalizeSession(session);
  lastVersionSignature = versionSignature(state.session);
  const index = state.store.sessions.findIndex((item) => item.id === state.session.id);
  if (index >= 0) state.store.sessions[index] = state.session;
  state.store.activeId = state.session.id;
  state.selectedClip = null;
  state.selectedAutomationPoint = null;
  state.selectedNote = null;
  state.selectedNotes = [];
  state.groupSelectionMode = false;
  state.selectedGroupTrackIDs = [];
  state.automationTrack = null;
  engine.setSession(state.session);
  engine.position = 0;
  state.playhead = 0;
  persist();
  preloadAudio().then(() => {
    engine.rebuild();
    render();
  });
  render();
}

function undo() {
  if (!state.undo.length) return;
  state.redo.push(JSON.stringify(state.session));
  adoptSession(JSON.parse(state.undo.pop()));
}

function redo() {
  if (!state.redo.length) return;
  state.undo.push(JSON.stringify(state.session));
  adoptSession(JSON.parse(state.redo.pop()));
}

// ---------- Audio buffers ----------

function computePeaks(buffer, buckets = 480) {
  const data = buffer.getChannelData(0);
  const peaks = new Float32Array(buckets);
  const step = Math.max(1, Math.floor(data.length / buckets));
  for (let bucket = 0; bucket < buckets; bucket += 1) {
    let peak = 0;
    const start = bucket * step;
    for (let i = 0; i < step; i += 4) {
      const value = Math.abs(data[start + i] || 0);
      if (value > peak) peak = value;
    }
    peaks[bucket] = peak;
  }
  return peaks;
}

function hasAudibleContent(buffer) {
  for (let channel = 0; channel < buffer.numberOfChannels; channel += 1) {
    const samples = buffer.getChannelData(channel);
    for (let index = 0; index < samples.length; index += 64) {
      if (Math.abs(samples[index]) > 0.0001) return true;
    }
  }
  return false;
}

async function ensureBuffer(fileId) {
  if (!fileId) return null;
  if (state.buffers.has(fileId)) {
    engine.buffers.set(fileId, state.buffers.get(fileId));
    return state.buffers.get(fileId);
  }
  const entry = await model.loadFile(fileId);
  if (!entry) return null;
  try {
    const arrayBuffer = await entry.blob.arrayBuffer();
    const buffer = await engine.decode(arrayBuffer);
    state.buffers.set(fileId, buffer);
    engine.buffers.set(fileId, buffer);
    if (!state.peaks.has(fileId)) state.peaks.set(fileId, computePeaks(buffer));
    return buffer;
  } catch (error) {
    console.warn('Could not decode stored audio', error);
    return null;
  }
}

async function preloadAudio() {
  const ids = new Set();
  for (const track of state.session.tracks) {
    for (const clip of model.playbackClips(track)) ids.add(clip.fileId);
    if (track.frozen?.fileId) ids.add(track.frozen.fileId);
  }
  for (const id of ids) await ensureBuffer(id);
}

// ---------- Studio mode ----------

function applyStudioMode() {
  document.body.classList.toggle('mode-simple', state.mode === 'simple');
  document.body.classList.toggle('mode-pro', state.mode === 'pro');
  [el.modeSimpleBtn, el.modeProBtn].forEach((button) => {
    if (!button) return;
    const active = button.dataset.mode === state.mode;
    button.classList.toggle('on', active);
    button.setAttribute('aria-pressed', String(active));
  });
}

function setStudioMode(mode) {
  const next = mode === 'pro' ? 'pro' : 'simple';
  if (state.mode === next) return;
  state.mode = next;
  localStorage.setItem('studio.mode', next);
  if (next === 'simple') {
    state.automationTrack = null;
    state.selectedAutomationPoint = null;
    state.groupSelectionMode = false;
    state.selectedGroupTrackIDs = [];
  }
  applyStudioMode();
  render();
}

// ---------- Take lane ----------

function ensureTakes(track) {
  if (!Array.isArray(track.takes)) track.takes = [];
  return track.takes;
}

function registerTake(track, { name, fileId, start, duration }) {
  const takes = ensureTakes(track);
  const take = {
    id: model.uid(),
    name: `${name} ${takes.length + 1}`,
    fileId,
    start: Math.max(0, Number(start) || 0),
    duration: Math.max(0, Number(duration) || 0)
  };

  if (track.activeTakeId) {
    track.clips = track.clips.filter((clip) => clip.id !== `take:${track.activeTakeId}`);
  }
  takes.push(take);
  track.activeTakeId = take.id;
  track.clips.push({
    id: `take:${take.id}`,
    takeId: take.id,
    name: take.name,
    fileId: take.fileId,
    start: take.start,
    duration: take.duration,
    sourceStart: 0,
    sourceDuration: take.duration
  });
  track.clips.sort((left, right) => left.start - right.start);
  return take;
}

function setActiveTake(track, takeId) {
  const take = ensureTakes(track).find((item) => item.id === takeId);
  if (!take) return;
  if (track.activeTakeId) {
    track.clips = track.clips.filter((clip) => clip.id !== `take:${track.activeTakeId}`);
  }
  track.activeTakeId = take.id;
  track.clips.push({
    id: `take:${take.id}`,
    takeId: take.id,
    name: take.name,
    fileId: take.fileId,
    start: take.start,
    duration: take.duration,
    sourceStart: 0,
    sourceDuration: take.duration
  });
  track.clips.sort((left, right) => left.start - right.start);
}

async function openTakeLane(trackId) {
  const track = trackById(trackId);
  if (!track) return;
  state.modal = 'takes';
  state.takeLaneTrackId = trackId;

  const takes = ensureTakes(track);
  const previews = [];
  for (const take of takes) {
    const entry = await model.loadFile(take.fileId).catch(() => null);
    previews.push(entry ? URL.createObjectURL(entry.blob) : '');
  }
  if (state.modal !== 'takes' || state.takeLaneTrackId !== trackId) {
    previews.forEach((url) => url && URL.revokeObjectURL(url));
    return;
  }
  (state.takePreviewURLs || []).forEach((url) => url && URL.revokeObjectURL(url));
  state.takePreviewURLs = previews;

  const rows = takes.map((take, index) => {
    const isActive = track.activeTakeId === take.id;
    return `<article class="take-row ${isActive ? 'active' : ''}">
      <div class="take-number">T${index + 1}</div>
      <div class="take-meta">
        <strong>${escapeHtml(take.name)}</strong>
        <span>${model.formatTime(take.duration)} · starts ${model.formatTime(take.start)}</span>
      </div>
      ${isActive ? '<span class="take-active-chip">ACTIVE</span>' : ''}
      <audio class="take-preview" controls preload="none" src="${escapeHtml(previews[index] || '')}" aria-label="Audition ${escapeHtml(take.name)}"></audio>
      <div class="take-actions">
        <button class="tool" data-take-promote="${take.id}" ${isActive ? 'disabled' : ''}>${isActive ? 'On Timeline' : 'Promote'}</button>
        <button class="icon-btn" data-take-rename="${take.id}" title="Rename">✎</button>
        <button class="icon-btn" data-take-delete="${take.id}" title="Delete">×</button>
      </div>
    </article>`;
  }).join('');

  openModal(`
    <header class="modal-header">
      <div style="flex:1;min-width:0">
        <h2>Take Lane</h2>
        <div class="sub">${escapeHtml(track.name.toUpperCase())} · ${takes.length} ${takes.length === 1 ? 'TAKE' : 'TAKES'}</div>
      </div>
      <button class="modal-close" data-close>Done</button>
    </header>
    <div class="modal-body">
      ${rows || '<p class="export-empty">No takes yet. Record onto this track and every pass will be kept here.</p>'}
    </div>`, { tall: true });

  el.modalRoot.querySelectorAll('[data-take-promote]').forEach((button) => {
    button.addEventListener('click', () => {
      snapshot();
      setActiveTake(track, button.dataset.takePromote);
      persist();
      engine.rebuild();
      render();
      openTakeLane(trackId);
      toast('Take placed on the timeline');
    });
  });

  el.modalRoot.querySelectorAll('[data-take-rename]').forEach((button) => {
    button.addEventListener('click', () => {
      const take = takes.find((item) => item.id === button.dataset.takeRename);
      if (!take) return;
      const entered = window.prompt('Take name', take.name);
      if (entered === null) return;
      const name = entered.trim();
      if (!name) return;
      snapshot();
      take.name = name;
      track.clips.forEach((clip) => {
        if (clip.takeId === take.id) clip.name = name;
      });
      persist();
      engine.rebuild();
      render();
      openTakeLane(trackId);
    });
  });

  el.modalRoot.querySelectorAll('[data-take-delete]').forEach((button) => {
    button.addEventListener('click', () => {
      const takeId = button.dataset.takeDelete;
      const take = takes.find((item) => item.id === takeId);
      if (!take || !window.confirm(`Delete "${take.name}"?`)) return;
      snapshot();
      track.takes = takes.filter((item) => item.id !== takeId);
      if (track.activeTakeId === takeId) {
        track.clips = track.clips.filter((clip) => clip.id !== `take:${takeId}`);
        track.activeTakeId = null;
        const fallback = track.takes[track.takes.length - 1];
        if (fallback) setActiveTake(track, fallback.id);
      }
      persist();
      engine.rebuild();
      render();
      openTakeLane(trackId);
      toast('Take deleted');
    });
  });
}

// ---------- Rendering: header + transport ----------

function renderHeader() {
  const session = state.session;
  el.sessionName.textContent = session.name;
  const count = session.tracks.length;
  el.sessionSubtitle.textContent = `${count} ${count === 1 ? 'TRACK' : 'TRACKS'} · ${model.formatTime(sessionDuration())}`;
}

function renderTransport() {
  const session = state.session;
  if (!session) return;
  const duration = sessionDuration();
  const position = currentPosition();

  if (state.countInActive) {
    el.timecode.textContent = `COUNT-IN ${state.countInRemaining}`;
  } else {
    el.timecode.textContent = model.formatTime(position);
  }
  el.durationLabel.textContent = model.formatTime(duration);
  el.progressFill.style.width = duration > 0 ? `${Math.min(100, (position / duration) * 100)}%` : '0%';
  el.playBtn.textContent = engine.isPlaying || state.countInActive ? '❚❚' : '▶';
  el.playBtn.disabled = session.tracks.length === 0;

  el.loopBtn.classList.toggle('on', session.loop.enabled);
  el.loopBtn.disabled = !model.hasLoopRange(session);
  el.loopRangeLabel.textContent = model.hasLoopRange(session)
    ? `${model.formatTime(session.loop.start)} – ${model.formatTime(session.loop.end)}`
    : 'Drag markers on the ruler';

  el.punchBtn.classList.toggle('on', session.punch.enabled);
  el.punchBtn.disabled = !hasPunchRange();
  el.punchRangeLabel.textContent = hasPunchRange()
    ? `${model.formatTime(session.punch.in)} – ${model.formatTime(session.punch.out)}`
    : 'Set IN and OUT';
  const armSignature = session.tracks.map((track) => `${track.id}:${track.name}`).join('|');
  if (el.punchArm.dataset.signature !== armSignature) {
    el.punchArm.innerHTML = '<option value="">ARM TRACK</option>'
      + session.tracks.map((track) => `<option value="${track.id}">${escapeHtml(track.name)}</option>`).join('');
    el.punchArm.dataset.signature = armSignature;
  }
  el.punchArm.value = session.punch.armedTrackId || '';

  el.metronomeBtn.classList.toggle('on', session.metronome.enabled);
  if (document.activeElement !== el.metronomeLevel) {
    el.metronomeLevel.value = String(session.metronome.level);
  }
  el.countInBtn.classList.toggle('on', session.metronome.countIn);
  el.tempoValue.textContent = `${session.tempo} BPM`;

  el.undoBtn.disabled = state.undo.length === 0;
  el.redoBtn.disabled = state.redo.length === 0;
  el.bounceBtn.disabled = state.bouncing || session.tracks.length === 0;
}

// ---------- Rendering: timeline ----------

let layoutWidth = 0;
let viewportTimer = null;
let viewportTicks = 0;

/// Re-measures the arrangement after the window changes shape, which happens
/// when a phone is turned sideways or the browser bars appear and disappear.
function handleViewportChange() {
  if (viewportTimer) window.clearTimeout(viewportTimer);
  viewportTimer = window.setTimeout(() => {
    viewportTimer = null;
    if (!state.session || !el.arrScroll) return;
    const width = el.arrScroll.clientWidth;
    if (!width || width === layoutWidth) return;
    const scrollLeft = el.arrScroll.scrollLeft;
    const scrollTop = el.arrScroll.scrollTop;
    renderTimeline();
    renderTransport();
    el.arrScroll.scrollLeft = scrollLeft;
    el.arrScroll.scrollTop = scrollTop;
  }, 120);
}

function renderTimeline() {
  const session = state.session;
  const hasTracks = session.tracks.length > 0;
  el.emptyState.classList.toggle('visible', !hasTracks);
  el.arrGrid.style.display = hasTracks ? 'flex' : 'none';
  const scrollWidth = el.arrScroll.clientWidth || 320;
  layoutWidth = scrollWidth;
  if (!hasTracks) {
    updatePlayhead();
    return;
  }

  const pps = state.zoom;
  const duration = sessionDuration();
  const contentWidth = Math.max(scrollWidth, duration * pps + 240, 480);
  const beatPx = beatDuration() * pps;
  el.arrContent.style.width = `${contentWidth}px`;
  el.lanes.style.setProperty('--beat-width', `${beatPx}px`);

  renderHeads();
  renderRuler(contentWidth, beatPx);
  renderLanes(contentWidth, pps, beatPx);
  renderLoopStrip(contentWidth, pps);
  renderPunchStrip(pps);
  renderSections(pps);
  updatePlayhead();
  updateClipToolbar();
}

function renderHeads() {
  const session = state.session;
  const parts = [];
  parts.push(`<div class="heads-spacer"><span class="meter-label">4/4</span><span>TRACKS</span><span style="margin-left:auto">${session.tracks.length}</span></div>`);

  session.tracks.forEach((track, index) => {
    const color = trackColorFor(track, index);
    const group = session.groups?.find((item) => item.trackIDs.includes(track.id));
    const frozen = Boolean(track.frozen?.fileId);
    const takes = track.takes || [];
    const activeTakeNumber = Math.max(1, takes.findIndex((take) => take.id === track.activeTakeId) + 1);
    parts.push(`
      <div class="track-head" style="--track-color:${color}">
        <div class="track-head-top">
          <span class="track-index">${String(index + 1).padStart(2, '0')}</span>
          <span class="track-name">${escapeHtml(track.name)}</span>
          ${takes.length ? `<button class="take-badge" data-act="takes" data-track="${track.id}" title="Take lane">T${activeTakeNumber} · ${takes.length}</button>` : ''}
          <button class="icon-btn" data-act="eq" data-track="${track.id}" title="Equalizer">≡</button>
          <button class="icon-btn ${frozen ? 'off' : ''}" data-act="roll" data-track="${track.id}" title="Piano roll" ${frozen ? 'disabled' : ''}>♫</button>
          ${state.mode === 'pro' ? `
            <button class="icon-btn ${state.automationTrack === track.id && state.automationParam === 'volume' ? '' : 'off'}" data-act="automation" data-track="${track.id}" title="Volume automation">⋀</button>
            <button class="icon-btn ${state.automationTrack === track.id && state.automationParam === 'pan' ? '' : 'off'}" data-act="automation-pan" data-track="${track.id}" title="Pan automation">⇄</button>
          ` : ''}
        </div>
        <div class="track-head-row">
          ${group && state.mode === 'pro' ? `<span class="group-badge" style="--group-color:${color}" title="${escapeHtml(group.name)}">${escapeHtml(group.name)}</span>` : ''}
          <div style="display:flex;flex-direction:column;gap:4px">
            <button class="mini ${track.muted ? 'on' : ''}" data-act="mute" data-track="${track.id}" title="Mute">M</button>
            <button class="mini ${track.soloed ? 'on' : ''}" data-act="solo" data-track="${track.id}" title="Solo">S</button>
          </div>
          ${state.mode === 'pro' ? `
            <button class="mini snow ${frozen ? 'frozen' : ''}" data-act="freeze" data-track="${track.id}" title="${frozen ? 'Unfreeze' : 'Freeze to audio'}">❄</button>
            <button class="mini instrument-open" data-act="instrument" data-track="${track.id}" title="Open instruments for ${escapeHtml(track.name)}">♫</button>
          ` : ''}
          <div class="spacer"></div>
          <input type="range" class="fader" min="0" max="1" step="0.01" value="${track.volume}" data-act="volume" data-track="${track.id}" aria-label="Volume for ${escapeHtml(track.name)}">
          <div class="meter" data-meter="${track.id}"><div class="meter-fill"></div></div>
        </div>
      </div>`);
  });

  el.arrHeads.innerHTML = parts.join('');
}

function renderPunchStrip(pps) {
  const region = el.punchRegion;
  if (!region) return;
  const punch = state.session.punch;
  if (!punch.enabled || !hasPunchRange()) {
    region.style.display = 'none';
    return;
  }
  region.style.display = 'block';
  region.style.left = `${Math.max(0, punch.in) * pps}px`;
  region.style.width = `${Math.max(1, (punch.out - punch.in) * pps)}px`;
}

function renderRuler(width, beatPx) {
  const dpr = window.devicePixelRatio || 1;
  el.rulerCanvas.width = Math.max(1, Math.floor(width * dpr));
  el.rulerCanvas.height = Math.floor(RULER_HEIGHT * dpr);
  el.rulerCanvas.style.width = `${width}px`;
  el.rulerCanvas.style.height = `${RULER_HEIGHT}px`;

  const ctx = el.rulerCanvas.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, width, RULER_HEIGHT);

  ctx.fillStyle = 'rgba(255,255,255,0.02)';
  ctx.fillRect(0, SECTION_TOP, width, SECTION_HEIGHT);

  const sections = state.session.sections || [];
  ctx.strokeStyle = 'rgba(245, 158, 42, 0.45)';
  ctx.lineWidth = 1;
  sections.forEach((section) => {
    const x = section.time * state.zoom;
    if (x > width) return;
    ctx.beginPath();
    ctx.moveTo(x, SECTION_TOP);
    ctx.lineTo(x, RULER_HEIGHT);
    ctx.stroke();
  });

  const beatCount = Math.ceil(width / Math.max(1, beatPx)) + 1;
  for (let index = 0; index < beatCount; index += 1) {
    const x = index * beatPx;
    const isBar = index % 4 === 0;
    ctx.strokeStyle = isBar ? 'rgba(255,255,255,0.62)' : 'rgba(255,255,255,0.22)';
    ctx.lineWidth = isBar ? 1.2 : 1;
    ctx.beginPath();
    ctx.moveTo(x, RULER_HEIGHT - (isBar ? 13 : 7));
    ctx.lineTo(x, RULER_HEIGHT);
    ctx.stroke();

    if (isBar || beatPx >= 11) {
      const bar = Math.floor(index / 4) + 1;
      const beat = (index % 4) + 1;
      const label = isBar ? String(bar) : beatPx >= 34 ? `${bar}.${beat}` : String(beat);
      ctx.fillStyle = isBar ? 'rgba(244,242,238,0.9)' : 'rgba(154,154,159,0.9)';
      ctx.font = `${isBar ? 9 : 8}px "SF Mono", ui-monospace, monospace`;
      ctx.fillText(label, x + 4, SECTION_TOP + SECTION_HEIGHT + 8);
    }
  }
}

function fadePath(clip) {
  const duration = Math.max(0.01, clip.duration);
  const inPercent = Math.min(50, ((Number(clip.fadeIn) || 0) / duration) * 100);
  const outPercent = Math.min(50, ((Number(clip.fadeOut) || 0) / duration) * 100);
  const startY = inPercent > 0 ? 100 : 0;
  const endY = outPercent > 0 ? 100 : 0;
  return `M 0 ${startY} L ${inPercent} 0 L ${100 - outPercent} 0 L 100 ${endY}`;
}

function renderLanes(contentWidth, pps, beatPx) {
  const session = state.session;
  const parts = [];

  session.tracks.forEach((track, index) => {
    const color = model.trackColor(index);
    const frozen = Boolean(track.frozen?.fileId);
    const clips = model.playbackClips(track);

    const clipHtml = clips.map((clip) => {
      const width = Math.max(18, clip.duration * pps);
      const selected = state.selectedClip === clip.id;
      return `<div class="clip ${selected ? 'selected' : ''} ${frozen ? 'frozen' : ''}" data-clip="${clip.id}" data-track="${track.id}" style="left:${Math.max(0, clip.start) * pps}px;width:${width}px">
        <span class="clip-label">${escapeHtml(clip.name.toUpperCase())}</span>
        <canvas class="clip-wave" data-file="${clip.fileId}"></canvas>
        ${selected && state.mode === 'pro' ? `<svg class="clip-fades" viewBox="0 0 100 100" preserveAspectRatio="none"><path d="${fadePath(clip)}"></path></svg>
        <button class="fade-handle fade-in" data-fade-edge="in" data-clip="${clip.id}" data-track="${track.id}" style="left:${Math.min(50, ((clip.fadeIn || 0) / Math.max(0.01, clip.duration)) * 100)}%" aria-label="Fade in"></button>
        <button class="fade-handle fade-out" data-fade-edge="out" data-clip="${clip.id}" data-track="${track.id}" style="left:${100 - Math.min(50, ((clip.fadeOut || 0) / Math.max(0.01, clip.duration)) * 100)}%" aria-label="Fade out"></button>` : ''}
        <span class="trim trim-left" data-edge="left"></span>
        <span class="trim trim-right" data-edge="right"></span>
      </div>`;
    }).join('');

    const automation = state.mode === 'pro' && state.automationTrack === track.id
      ? '<canvas class="automation-canvas"></canvas>'
      : '';
    const activePoints = state.mode === 'pro' && state.automationTrack === track.id
      ? activeAutomationPoints(track)
      : [];
    const points = activePoints.length
      ? [...activePoints].sort((a, b) => a.time - b.time).map((point) => (
        `<div class="auto-point ${state.selectedAutomationPoint === point.id ? 'selected' : ''}" data-act="auto-point" data-point="${point.id}" data-track="${track.id}" style="left:${point.time * pps}px;top:${automationY(state.automationParam, point[automationValueKey()])}px"></div>`
      )).join('')
      : '';

    const takeChips = state.mode === 'pro' && (track.takes || []).length
      ? `<div class="take-lane">${track.takes.map((take, index) => {
        const active = track.activeTakeId === take.id;
        return `<button class="take-chip ${active ? 'active' : ''}" data-act="audition-take" data-track="${track.id}" data-take="${take.id}" style="left:${take.start * pps}px;width:${Math.max(22, take.duration * pps)}px" title="${escapeHtml(take.name)}">T${index + 1}</button>`;
      }).join('')}</div>`
      : '';

    parts.push(`<div class="lane" data-track="${track.id}" style="--beat-width:${beatPx}px">${clipHtml}${takeChips}${automation}${points}</div>`);
  });

  el.lanes.innerHTML = parts.join('');

  el.lanes.querySelectorAll('canvas.clip-wave').forEach((canvas) => {
    drawClipWave(canvas, state.peaks.get(canvas.dataset.file));
  });

  el.lanes.querySelectorAll('[data-fade-edge]').forEach((handle) => {
    handle.addEventListener('pointerdown', (event) => {
      event.preventDefault();
      event.stopPropagation();
      const clip = model.playbackClips(trackById(handle.dataset.track)).find((item) => item.id === handle.dataset.clip);
      const clipElement = handle.closest('.clip');
      if (!clip || !clipElement) return;
      const edge = handle.dataset.fadeEdge;
      const origin = edge === 'in' ? (Number(clip.fadeIn) || 0) : (Number(clip.fadeOut) || 0);
      const startX = event.clientX;
      const path = clipElement.querySelector('.clip-fades path');

      const onMove = (moveEvent) => {
        const delta = (moveEvent.clientX - startX) / state.zoom;
        const value = Math.max(0, Math.min(clip.duration, edge === 'in' ? origin + delta : origin - delta));
        if (edge === 'in') clip.fadeIn = value;
        else clip.fadeOut = value;
        if (path) path.setAttribute('d', fadePath(clip));
        const percent = Math.min(50, (value / Math.max(0.01, clip.duration)) * 100);
        handle.style.left = `${edge === 'in' ? percent : 100 - percent}%`;
      };

      const onUp = () => {
        window.removeEventListener('pointermove', onMove);
        window.removeEventListener('pointerup', onUp);
        persist();
        engine.rebuild();
        render();
      };

      window.addEventListener('pointermove', onMove);
      window.addEventListener('pointerup', onUp, { once: true });
    });
  });

  if (state.automationTrack) {
    const track = trackById(state.automationTrack);
    const canvas = el.lanes.querySelector('.automation-canvas');
    if (track && canvas) drawAutomation(canvas, track, contentWidth, pps, state.automationParam);
  }
}

function drawClipWave(canvas, peaks) {
  const width = 400;
  const height = 48;
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, width, height);
  if (!peaks || !peaks.length) return;
  ctx.strokeStyle = 'rgba(245, 158, 42, 0.95)';
  ctx.lineWidth = 1.1;
  ctx.beginPath();
  const mid = height / 2;
  for (let x = 0; x < width; x += 1) {
    const bucket = Math.min(peaks.length - 1, Math.floor((x / width) * peaks.length));
    const half = Math.min(1, peaks[bucket]) * (mid - 2);
    ctx.moveTo(x, mid - half);
    ctx.lineTo(x, mid + half);
  }
  ctx.stroke();
}

function drawAutomation(canvas, track, contentWidth, pps, param) {
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.max(1, Math.floor(contentWidth * dpr));
  canvas.height = Math.floor(ROW_HEIGHT * dpr);
  const ctx = canvas.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, contentWidth, ROW_HEIGHT);

  if (param === 'pan') {
    ctx.strokeStyle = 'rgba(255,255,255,0.16)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, ROW_HEIGHT / 2);
    ctx.lineTo(contentWidth, ROW_HEIGHT / 2);
    ctx.stroke();
  }

  const drawCurve = (points, key, curveParam, stroke, lineWidth) => {
    if (!points || !points.length) return;
    const ordered = [...points].sort((a, b) => a.time - b.time);
    const yFor = (value) => automationY(curveParam, value);

    ctx.strokeStyle = stroke;
    ctx.lineWidth = lineWidth;
    ctx.beginPath();
    const firstX = ordered[0].time * pps;
    ctx.moveTo(0, yFor(ordered[0][key]));
    ctx.lineTo(firstX, yFor(ordered[0][key]));

    for (let i = 1; i < ordered.length; i += 1) {
      const left = ordered[i - 1];
      const right = ordered[i];
      const steps = 16;
      for (let step = 1; step <= steps; step += 1) {
        const progress = step / steps;
        const eased = progress * progress * (3 - 2 * progress);
        const value = left[key] + (right[key] - left[key]) * eased;
        const time = left.time + (right.time - left.time) * progress;
        ctx.lineTo(time * pps, yFor(value));
      }
    }

    ctx.lineTo(contentWidth, yFor(ordered[ordered.length - 1][key]));
    ctx.stroke();

    if (lineWidth > 1.5) {
      ctx.fillStyle = stroke;
      ordered.forEach((point) => {
        ctx.beginPath();
        ctx.arc(point.time * pps, yFor(point[key]), 3, 0, Math.PI * 2);
        ctx.fill();
      });
    }
  };

  if (param === 'pan') {
    drawCurve(track.automation, 'gain', 'volume', 'rgba(255,255,255,0.22)', 1.5);
    drawCurve(track.panAutomation, 'pan', 'pan', 'rgba(92,143,237,0.95)', 2);
  } else {
    drawCurve(track.panAutomation, 'pan', 'pan', 'rgba(255,255,255,0.22)', 1.5);
    drawCurve(track.automation, 'gain', 'volume', 'rgba(245,158,42,0.95)', 2);
  }
}

function renderLoopStrip(contentWidth, pps) {
  const session = state.session;
  const has = model.hasLoopRange(session);
  const width = Math.max(0, (session.loop.end - session.loop.start) * pps);

  el.loopRegion.classList.toggle('on', session.loop.enabled);
  el.loopRegion.style.display = has ? 'block' : 'none';
  if (has) {
    el.loopRegion.style.left = `${session.loop.start * pps}px`;
    el.loopRegion.style.width = `${Math.max(4, width)}px`;
    el.loopStartHandle.style.left = `${session.loop.start * pps}px`;
    el.loopEndHandle.style.left = `${session.loop.end * pps}px`;
  }
  el.loopStartHandle.classList.toggle('on', has);
  el.loopEndHandle.classList.toggle('on', has);
  el.loopHint.style.display = has ? 'none' : 'flex';
  el.loopStrip.style.width = `${contentWidth}px`;
}

function updatePlayhead() {
  const pps = state.zoom;
  const session = state.session;
  if (!session) return;
  const position = state.playhead;
  el.playhead.style.left = `${position * pps}px`;
  el.playhead.style.height = `${RULER_HEIGHT + session.tracks.length * ROW_HEIGHT}px`;

  const duration = sessionDuration();
  el.timecode.textContent = state.countInActive
    ? `COUNT-IN ${state.countInRemaining}`
    : model.formatTime(position);
  el.progressFill.style.width = duration > 0 ? `${Math.min(100, (position / duration) * 100)}%` : '0%';

  const rollPlayhead = document.querySelector('.roll-playhead');
  if (rollPlayhead) rollPlayhead.style.left = `${position * ROLL_BEAT_WIDTH / beatDuration()}px`;
}

function updateMeters() {
  document.querySelectorAll('.meter[data-meter]').forEach((meter) => {
    const fill = meter.querySelector('.meter-fill');
    if (!fill) return;
    const level = engine.getTrackLevel(meter.dataset.meter);
    fill.style.height = `${Math.min(100, level * 100)}%`;
  });

  document.querySelectorAll('[data-mix-meter]').forEach((meter) => {
    const fill = meter.querySelector('.meter-fill');
    if (!fill) return;
    const id = meter.dataset.mixMeter;
    const level = id === 'master' ? engine.getMasterLevel() : engine.getTrackLevel(id);
    fill.style.height = `${Math.min(100, level * 100)}%`;
  });

  const masterMeter = document.querySelector('[data-master-meter]');
  if (masterMeter) {
    const fill = masterMeter.querySelector('.meter-fill');
    if (fill) fill.style.height = `${Math.min(100, engine.getMasterLevel() * 100)}%`;
  }
}

// ---------- Animation frame ----------

function frame() {
  if (state.session) {
    const playing = engine.isPlaying;
    state.playhead = playing ? engine.getPosition() : engine.position;
    engine.updateMix(state.playhead);

    const duration = sessionDuration();
    if (playing && !engine.activeLoop() && duration > 0 && state.playhead >= duration - 0.02) {
      engine.stop();
      state.playhead = 0;
      renderTransport();
    }

    updatePlayhead();
    updateDrumSequencerPlayhead();
    updateMeters();
    if (state.modal === 'mastering') {
      updateMasteringMeters();
    }
    if (state.countInActive) {
      renderTransport();
    }

    // A few web views do not fire a resize event when the device turns, so
    // the arrangement width is also checked a couple of times a second.
    viewportTicks += 1;
    if (viewportTicks >= 30) {
      viewportTicks = 0;
      const width = el.arrScroll ? el.arrScroll.clientWidth : 0;
      if (width > 0 && width !== layoutWidth) handleViewportChange();
    }
  }
  requestAnimationFrame(frame);
}

// ---------- Playback controls ----------

function cancelCountIn() {
  if (!state.countInActive) return;
  state.countInActive = false;
  state.countInRemaining = 0;
  clearTimeout(state.countInTimer);
  clearInterval(state.countInInterval);
  state.countInTimer = null;
  state.countInInterval = null;
  engine.stopAll();
  renderTransport();
}

function togglePlay() {
  const session = state.session;
  if (!session || session.tracks.length === 0) return;

  if (engine.isPlaying) {
    engine.pause();
    renderTransport();
    return;
  }

  if (state.countInActive) {
    cancelCountIn();
    return;
  }

  if (session.metronome.countIn) {
    state.countInActive = true;
    state.countInRemaining = 4;
    renderTransport();

    const beatSeconds = 60 / (session.tempo || 120);
    state.countInInterval = setInterval(() => {
      if (!state.countInActive) return;
      state.countInRemaining = Math.max(0, state.countInRemaining - 1);
      renderTransport();
    }, beatSeconds * 1000);

    const length = engine.playCountIn(4);
    state.countInTimer = setTimeout(() => {
      clearInterval(state.countInInterval);
      state.countInInterval = null;
      state.countInActive = false;
      state.countInRemaining = 0;
      engine.play(engine.position);
      renderTransport();
    }, length * 1000);
    return;
  }

  engine.play(engine.position);
  renderTransport();
}

function stopPlayback() {
  cancelCountIn();
  engine.stop();
  state.playhead = 0;
  renderTransport();
  updatePlayhead();
}

// ---------- Track actions ----------

function setTrackVolume(track, value) {
  track.volume = model.clamp(value, 0, 1);
  const nodes = engine.trackNodes.get(track.id);
  if (nodes) engine.updateMix(state.playhead);
}

function setTrackPan(track, value) {
  track.pan = model.clamp(value, -1, 1);
  const nodes = engine.trackNodes.get(track.id);
  if (nodes) engine.applyTrackSettings(track, nodes);
}

function toggleMute(trackId) {
  const track = trackById(trackId);
  if (!track) return;
  snapshot();
  track.muted = !track.muted;
  persist();
  render();
}

function toggleSolo(trackId) {
  const track = trackById(trackId);
  if (!track) return;
  snapshot();
  track.soloed = !track.soloed;
  persist();
  render();
}

function toggleAutomation(trackId, param = 'volume') {
  if (state.automationTrack === trackId && state.automationParam === param) {
    state.automationTrack = null;
  } else {
    state.automationTrack = trackId;
    state.automationParam = param;
  }
  state.selectedAutomationPoint = null;
  renderTimeline();
}

async function toggleFreeze(trackId) {
  const track = trackById(trackId);
  if (!track || state.freezing) return;

  if (track.frozen?.fileId) {
    snapshot();
    track.frozen = { fileId: null, duration: 0 };
    persist();
    engine.rebuild();
    render();
    toast('Track unfrozen');
    return;
  }

  if (durationOfTrack(track) <= 0) {
    toast('This track has nothing to freeze yet');
    return;
  }

  state.freezing = true;
  toast(`Freezing ${track.name}…`);
  const wasPlaying = engine.isPlaying;
  if (wasPlaying) engine.pause();

  try {
    const buffer = await engine.renderTrackFreeze(track);
    const blob = encodeWav(buffer);
    const fileId = await model.saveFile(blob, `${track.name}-freeze.wav`);
    state.buffers.set(fileId, buffer);
    engine.buffers.set(fileId, buffer);
    state.peaks.set(fileId, computePeaks(buffer));
    snapshot();
    track.frozen = { fileId, duration: buffer.duration };
    persist();
    engine.rebuild();
    render();
    if (wasPlaying) engine.play(engine.position);
    toast('Track frozen to audio');
  } catch (error) {
    toast(error.message || 'Freeze failed');
  }

  state.freezing = false;
}

function m4aMimeType() {
  if (!window.MediaRecorder || typeof MediaRecorder.isTypeSupported !== 'function') return null;
  return ['audio/mp4;codecs=mp4a.40.2', 'audio/mp4'].find((type) => MediaRecorder.isTypeSupported(type)) || null;
}

async function encodeM4A(buffer, context = null) {
  const mimeType = m4aMimeType();
  if (!mimeType) throw new Error('This browser cannot export M4A. Choose WAV instead.');

  const ownsContext = !context;
  if (!context) {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    context = new AudioContextClass({ sampleRate: buffer.sampleRate });
  }
  const destination = context.createMediaStreamDestination();
  const source = context.createBufferSource();
  source.buffer = buffer;
  source.connect(destination);

  return new Promise((resolve, reject) => {
    let recorder;
    const chunks = [];
    const cleanup = () => {
      destination.stream.getTracks().forEach((track) => track.stop());
      if (ownsContext) context.close().catch(() => {});
    };
    try {
      recorder = new MediaRecorder(destination.stream, { mimeType });
      recorder.ondataavailable = (event) => {
        if (event.data.size) chunks.push(event.data);
      };
      recorder.onerror = (event) => {
        cleanup();
        reject(event.error || new Error('M4A encoding failed.'));
      };
      recorder.onstop = () => {
        cleanup();
        resolve(new Blob(chunks, { type: 'audio/mp4' }));
      };
      source.onended = () => setTimeout(() => {
        if (recorder.state === 'recording') recorder.stop();
      }, 120);
      context.resume().then(() => {
        recorder.start();
        source.start();
      }).catch((error) => {
        cleanup();
        reject(error);
      });
    } catch (error) {
      cleanup();
      reject(error);
    }
  });
}

function bounceSettingsSize(settings, mode) {
  const tracks = state.session.tracks.filter((track) => model.trackDuration(track) > 0);
  const duration = mode === 'stems'
    ? tracks.reduce((sum, track) => sum + model.trackDuration(track), 0)
    : sessionDuration();
  const bytes = settings.format === 'm4a'
    ? duration * 32_000
    : duration * settings.sampleRate * 2 * (settings.bitDepth / 8);
  const size = bytes >= 1_000_000 ? `${(bytes / 1_000_000).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1000))} KB`;
  return mode === 'stems' ? `ESTIMATED ${tracks.length} FILES · ${size}` : `ESTIMATED SIZE · ${size}`;
}

function openBounceSettings(mode) {
  if (state.bouncing) return;
  if (mode === 'stems' && !state.session.tracks.some((track) => model.trackDuration(track) > 0)) {
    toast('There are no tracks with audio to export');
    return;
  }

  const settings = { ...(state.bounceSettings || {}), fileName: state.bounceSettings?.fileName || state.session.name };
  if (!settings.format) settings.format = 'wav';
  if (settings.format === 'm4a' && !m4aMimeType()) settings.format = 'wav';
  if (!settings.sampleRate) settings.sampleRate = 44100;
  if (!settings.bitDepth) settings.bitDepth = 24;
  settings.normalize = Boolean(settings.normalize);

  openModal(`
    <header class="modal-header">
      <div style="flex:1;min-width:0"><h2>Bounce Settings</h2><div class="sub">${mode === 'stems' ? 'RENDER EACH TRACK' : 'RENDER THE MIX'}</div></div>
      <button class="modal-close" data-close>Cancel</button>
    </header>
    <div class="modal-body">
      <div class="panel">
        <h3>FORMAT</h3>
        <div class="field">
          <select id="bounceFormat">
            <option value="wav" ${settings.format === 'wav' ? 'selected' : ''}>WAV</option>
            <option value="m4a" ${settings.format === 'm4a' ? 'selected' : ''} ${m4aMimeType() ? '' : 'disabled'}>M4A${m4aMimeType() ? '' : ' · not supported in this browser'}</option>
          </select>
        </div>
        <div class="field">
          <div class="label-row"><span>Sample rate</span></div>
          <select id="bounceSampleRate">
            <option value="44100" ${settings.sampleRate === 44100 ? 'selected' : ''}>44.1 kHz</option>
            <option value="48000" ${settings.sampleRate === 48000 ? 'selected' : ''}>48 kHz</option>
          </select>
        </div>
        <div class="field" id="bounceBitDepthField">
          <div class="label-row"><span>Bit depth</span></div>
          <select id="bounceBitDepth" ${settings.format === 'm4a' ? 'disabled' : ''}>
            <option value="16" ${settings.bitDepth === 16 ? 'selected' : ''}>16-bit</option>
            <option value="24" ${settings.bitDepth === 24 ? 'selected' : ''}>24-bit</option>
          </select>
        </div>
      </div>
      <div class="panel">
        <label class="bounce-check"><input type="checkbox" id="bounceNormalize" ${settings.normalize ? 'checked' : ''}><span><strong>Normalize to -1 dB</strong><small>Raise the peak level after rendering.</small></span></label>
      </div>
      <div class="panel">
        <h3>FILE NAME</h3>
        <input type="text" id="bounceFileName" value="${escapeHtml(settings.fileName)}" autocomplete="off">
      </div>
      ${m4aMimeType() ? '' : '<p class="range-label">M4A export requires browser audio/mp4 recording support. WAV is available here.</p>'}
    </div>
    <footer class="modal-footer bounce-footer">
      <span class="range-label" id="bounceEstimate">${bounceSettingsSize(settings, mode)}</span>
      <button class="tool primary" id="renderBounceBtn">${mode === 'stems' ? 'Render Stems' : 'Render Mix'}</button>
    </footer>`, { tall: true });

  const format = document.getElementById('bounceFormat');
  const rate = document.getElementById('bounceSampleRate');
  const depth = document.getElementById('bounceBitDepth');
  const normalize = document.getElementById('bounceNormalize');
  const name = document.getElementById('bounceFileName');
  const estimate = document.getElementById('bounceEstimate');
  const refresh = () => {
    const current = {
      format: format.value,
      sampleRate: Number(rate.value),
      bitDepth: Number(depth.value),
      normalize: normalize.checked,
      fileName: name.value
    };
    depth.disabled = current.format === 'm4a';
    estimate.textContent = bounceSettingsSize(current, mode);
  };
  [format, rate, depth, normalize, name].forEach((input) => input.addEventListener('input', refresh));
  format.addEventListener('change', refresh);

  document.getElementById('renderBounceBtn').addEventListener('click', () => {
    const final = {
      format: format.value,
      sampleRate: Number(rate.value),
      bitDepth: Number(depth.value),
      normalize: normalize.checked,
      fileName: safeName(name.value) || safeName(state.session.name) || 'Mix'
    };
    state.bounceSettings = final;
    try { localStorage.setItem('ai-studio.web.bounce-settings.v1', JSON.stringify(final)); } catch (error) { /* use settings for this render */ }
    let exportContext = null;
    if (final.format === 'm4a') {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      exportContext = new AudioContextClass({ sampleRate: final.sampleRate });
      exportContext.resume().catch(() => {});
    }
    closeModal();
    renderBounce(mode, final, exportContext);
  });
}

async function renderBounce(mode, settings, exportContext = null) {
  if (state.bouncing) return;
  state.bouncing = true;
  renderTransport();
  toast(mode === 'stems' ? 'Rendering stems…' : 'Bouncing mix…');
  const extension = settings.format === 'm4a' ? 'm4a' : 'wav';
  const sessionID = state.session.id;
  const sessionName = state.session.name;
  let librarySaveFailed = false;
  const makeBlob = async (buffer) => settings.format === 'm4a'
    ? encodeM4A(buffer, exportContext)
    : encodeWav(buffer, settings.bitDepth);
  const saveAndDownload = async (blob, name, kind, duration) => {
    try {
      await model.saveExport({
        name,
        kind,
        format: extension.toUpperCase(),
        duration,
        sessionID,
        sessionName,
        createdAt: Date.now(),
        blob
      });
    } catch (error) {
      console.warn('Could not save bounce to the export library', error);
      librarySaveFailed = true;
    }
    download(blob, name);
  };

  try {
    if (mode === 'stems') {
      const tracks = state.session.tracks.filter((track) => model.trackDuration(track) > 0);
      for (const track of tracks) {
        const buffer = await engine.renderStem(track, { sampleRate: settings.sampleRate, normalize: settings.normalize });
        const blob = await makeBlob(buffer);
        const name = `${safeName(settings.fileName)} - ${safeName(track.name)}.${extension}`;
        await saveAndDownload(blob, name, 'stem', buffer.duration);
        await new Promise((resolve) => setTimeout(resolve, 350));
      }
      toast(librarySaveFailed ? `${tracks.length} stems exported; library save failed` : `${tracks.length} stems exported`);
    } else {
      const buffer = await engine.renderMix({
        masterVolume: state.session.masterVolume,
        sampleRate: settings.sampleRate,
        normalize: settings.normalize
      });
      const blob = await makeBlob(buffer);
      await saveAndDownload(blob, `${safeName(settings.fileName)}.${extension}`, 'mix', buffer.duration);
      toast(librarySaveFailed ? 'Bounce downloaded; library save failed' : 'Bounce complete');
    }
  } catch (error) {
    toast(error.message || 'Bounce failed');
  } finally {
    if (exportContext && exportContext.state !== 'closed') exportContext.close().catch(() => {});
    state.bouncing = false;
    renderTransport();
  }
}

function bounceStems() {
  openBounceSettings('stems');
}

function bounceMix() {
  openBounceSettings('mix');
}

// ---------- Import ----------

async function importFiles(fileList) {
  const files = Array.from(fileList || []).filter((file) => (
    (file.type || '').startsWith('audio') || /\.(wav|mp3|m4a|aif|aiff|caf|ogg)$/i.test(file.name)
  ));
  if (!files.length) {
    toast('Choose an audio file to import');
    return;
  }

  snapshot();
  toast('Importing audio…');

  for (const file of files) {
    try {
      const original = await file.arrayBuffer();
      const copy = original.slice(0);
      const buffer = await engine.decode(copy);
      const blob = new Blob([original], { type: file.type || 'audio/wav' });
      const fileId = await model.saveFile(blob, file.name);
      state.buffers.set(fileId, buffer);
      engine.buffers.set(fileId, buffer);
      state.peaks.set(fileId, computePeaks(buffer));

      const name = file.name.replace(/\.[^.]+$/, '');
      const track = model.createTrack({
        name,
        fileId,
        duration: buffer.duration,
        index: state.session.tracks.length
      });
      state.session.tracks.push(track);
    } catch (error) {
      console.warn('Import failed', error);
      toast(`${file.name} could not be imported`);
    }
  }

  persist();
  engine.rebuild();
  render();
}

function addBlankTrack() {
  snapshot();
  const track = model.createTrack({
    name: `Track ${state.session.tracks.length + 1}`,
    index: state.session.tracks.length
  });
  state.session.tracks.push(track);
  persist();
  engine.rebuild();
  render();
  toast('Blank track added · open its piano roll to add notes');
}

function addInstrumentTrack() {
  const used = new Set(state.session.tracks.map((track) => track.name.toLowerCase()));
  let number = 1;
  while (used.has(`instrument layer ${number}`)) number += 1;
  snapshot();
  const track = model.createTrack({
    name: `Instrument Layer ${number}`,
    index: state.session.tracks.length
  });
  state.session.tracks.push(track);
  state.instrumentTrackId = track.id;
  state.instrumentTab = 'drums';
  persist();
  engine.rebuild();
  render();
  openInstruments(track.id);
}

function renderSections(pps) {
  const sections = state.session.sections || [];
  el.sectionLayer.innerHTML = sections.map((section) => (
    `<div class="section-flag" data-section="${section.id}" style="left:${Math.max(0, section.time) * pps}px">
      <span class="sf-name">${escapeHtml(section.name.toUpperCase())}</span>
      <button class="sf-del" data-section-delete="${section.id}" title="Delete section">×</button>
    </div>`
  )).join('');
}

function snappedBarTime(time) {
  const bar = beatDuration() * 4;
  const snapped = Math.round(Math.max(0, time) / bar) * bar;
  const duration = sessionDuration();
  return duration > 0 ? Math.min(snapped, duration) : snapped;
}

function suggestSectionName() {
  const base = ['Intro', 'Verse', 'Chorus', 'Bridge', 'Outro'];
  const used = new Set((state.session.sections || []).map((section) => section.name.toLowerCase()));
  const free = base.find((name) => !used.has(name.toLowerCase()));
  if (free) return free;
  let index = (state.session.sections || []).length + 1;
  while (used.has(`section ${index}`)) index += 1;
  return `Section ${index}`;
}

function seekTo(time) {
  const duration = sessionDuration();
  const position = duration > 0 ? Math.min(Math.max(0, time), duration) : Math.max(0, time);
  engine.seek(position);
  state.playhead = engine.position;
  renderTransport();
  updatePlayhead();
}

function addSectionAtPlayhead() {
  const suggested = suggestSectionName();
  const entered = window.prompt('Section name', suggested);
  if (entered === null) return;
  const name = entered.trim() || suggested;
  snapshot();
  state.session.sections.push({ id: model.uid(), name, time: snappedBarTime(engine.position) });
  state.session.sections.sort((a, b) => a.time - b.time);
  persist();
  renderTimeline();
  toast(`Section "${name}" added`);
}

// ---------- Clip editing ----------

function selectedClipInfo() {
  if (!state.selectedClip) return null;
  for (const track of state.session.tracks) {
    const clip = track.clips.find((item) => item.id === state.selectedClip);
    if (clip) return { track, clip };
  }
  return null;
}

function updateClipToolbar() {
  if (!clipToolbar) return;
  const info = selectedClipInfo();
  const show = Boolean(info) && !info.track.frozen?.fileId;
  clipToolbar.style.display = show ? 'flex' : 'none';
  if (show) {
    clipToolbar.querySelector('[data-clip-name]').textContent = info.clip.name;
  }
}

function ensureClipToolbar() {
  if (clipToolbar) return;
  clipToolbar = document.createElement('div');
  clipToolbar.style.cssText = [
    'position:absolute', 'left:10px', 'right:10px', 'bottom:10px',
    'display:none', 'align-items:center', 'gap:6px', 'padding:7px 8px',
    'background:rgba(29,29,32,0.97)', 'border:1px solid rgba(255,255,255,0.09)',
    'border-radius:11px', 'z-index:20', 'flex-wrap:wrap'
  ].join(';');
  clipToolbar.innerHTML = `
    <span data-clip-name style="flex:1;min-width:60px;font-size:11px;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap"></span>
    <button class="pill" data-clip-act="split">SPLIT</button>
    <button class="pill" data-clip-act="duplicate">DUPLICATE</button>
    <button class="pill" data-clip-act="delete">DELETE</button>
    <button class="pill" data-clip-act="close">DONE</button>`;
  el.arrangement.appendChild(clipToolbar);

  clipToolbar.addEventListener('click', (event) => {
    const button = event.target.closest('[data-clip-act]');
    if (!button) return;
    const info = selectedClipInfo();
    if (!info) {
      state.selectedClip = null;
      renderTimeline();
      return;
    }
    const { track, clip } = info;
    const action = button.dataset.clipAct;

    if (action === 'close') {
      state.selectedClip = null;
      renderTimeline();
      return;
    }

    snapshot();
    if (action === 'split') {
      const at = engine.position;
      if (at > clip.start + 0.05 && at < clip.start + clip.duration - 0.05) {
        const offset = at - clip.start;
        const second = {
          ...clip,
          id: model.uid(),
          start: at,
          duration: clip.duration - offset,
          sourceStart: clip.sourceStart + offset
        };
        clip.duration = offset;
        track.clips.push(second);
        track.clips.sort((a, b) => a.start - b.start);
        state.selectedClip = second.id;
        toast('Clip split');
      } else {
        toast('Move the playhead inside the clip to split');
      }
    } else if (action === 'duplicate') {
      const copy = {
        ...clip,
        id: model.uid(),
        start: clip.start + clip.duration
      };
      track.clips.push(copy);
      track.clips.sort((a, b) => a.start - b.start);
      state.selectedClip = copy.id;
      toast('Clip duplicated');
    } else if (action === 'delete') {
      track.clips = track.clips.filter((item) => item.id !== clip.id);
      state.selectedClip = null;
      toast('Clip deleted');
    }

    persist();
    engine.rebuild();
    renderTimeline();
    updateClipToolbar();
  });
}

// ---------- Loop range ----------

function setLoopRange(start, end) {
  const session = state.session;
  const duration = sessionDuration();
  const lower = Math.max(0, Math.min(start, end));
  let upper = Math.max(start, end);
  if (duration > 0) upper = Math.min(upper, duration);
  session.loop.start = Math.max(0, Math.min(lower, Math.max(0, upper - model.MIN_LOOP)));
  session.loop.end = Math.max(session.loop.start + model.MIN_LOOP, upper);
}

function setLoopStart(time) {
  const session = state.session;
  const maximum = Math.max(0, session.loop.end - model.MIN_LOOP);
  session.loop.start = model.clamp(time, 0, maximum);
}

function setLoopEnd(time) {
  const session = state.session;
  const duration = sessionDuration();
  const limit = duration > 0 ? duration : Math.max(session.loop.end, time);
  session.loop.end = Math.min(limit, Math.max(session.loop.start + model.MIN_LOOP, time));
}

// ---------- Automation ----------

function automationUnit(param, value) {
  return param === 'pan'
    ? model.clamp((value + 1) / 2, 0, 1)
    : model.clamp(value, 0, 1);
}

function automationValueFromUnit(param, unit) {
  return param === 'pan'
    ? model.clamp(unit * 2 - 1, -1, 1)
    : model.clamp(unit, 0, 1);
}

function automationValueAt(laneEl, clientY, param) {
  const rect = laneEl.getBoundingClientRect();
  const unit = model.clamp(1 - (clientY - rect.top) / ROW_HEIGHT, 0, 1);
  return automationValueFromUnit(param, unit);
}

function automationY(param, value) {
  return (1 - automationUnit(param, value)) * ROW_HEIGHT;
}

function activeAutomationPoints(track) {
  return state.automationParam === 'pan' ? (track.panAutomation || []) : (track.automation || []);
}

function automationValueKey() {
  return state.automationParam === 'pan' ? 'pan' : 'gain';
}

function automationTimeAt(laneEl, clientX) {
  const rect = laneEl.getBoundingClientRect();
  return snapTime(Math.max(0, clientX - rect.left) / state.zoom);
}

// ---------- Piano roll ----------

function openRoll(trackId) {
  const track = trackById(trackId);
  if (!track) return;
  if (track.frozen?.fileId) {
    toast('Unfreeze the track to edit its notes');
    return;
  }
  const arp = { ...model.defaultArpeggiator(), ...(track.arpeggiator || {}) };
  state.modal = 'roll';
  state.rollTrackId = trackId;
  state.selectedNote = null;
  state.selectedNotes = [];
  renderRollModal();
}

function rollSnap() {
  return beatDuration() / state.rollDivision;
}

function rollChordIntervals(type) {
  switch (type) {
    case 'major': return [0, 4, 7];
    case 'minor': return [0, 3, 7];
    case 'seventh': return [0, 4, 7, 10];
    default: return [0];
  }
}

function renderRollModal() {
  const track = trackById(state.rollTrackId);
  if (!track) {
    closeModal();
    return;
  }

  const beatPx = ROLL_BEAT_WIDTH;
  const duration = Math.max(sessionDuration(), beatDuration() * 16);
  const contentWidth = Math.max(16, Math.ceil(duration / beatDuration()) + 4) * beatPx;
  const gridHeight = (model.NOTE_HIGH - model.NOTE_LOW + 1) * NOTE_HEIGHT;

  const keys = [];
  for (let pitch = model.NOTE_HIGH; pitch >= model.NOTE_LOW; pitch -= 1) {
    const black = model.isBlackKey(pitch);
    keys.push(`<div class="roll-key ${black ? 'black' : ''}">${pitch % 12 === 0 ? model.noteName(pitch) : ''}</div>`);
  }

  openModal(`
    <header class="modal-header">
      <div style="flex:1;min-width:0">
        <h2>Piano Roll</h2>
        <div class="sub">${escapeHtml(track.name.toUpperCase())} · ${state.session.tempo} BPM</div>
      </div>
      <button class="icon-btn" id="rollPlayBtn">${engine.isPlaying ? '❚❚' : '▶'}</button>
      <button class="icon-btn" id="rollDeleteBtn" ${state.selectedNotes.length ? '' : 'disabled'}>🗑</button>
      <button class="modal-close" data-close>Done</button>
    </header>
    <div class="modal-body">
      <div class="roll">
        <div class="roll-toolbar">
          <span class="range-label">Tap to add · drag to move · shift-tap to select multiple</span>
          <div style="margin-left:auto;display:flex;gap:4px">
            <button class="pill ${state.rollDivision === 1 ? 'on' : ''}" data-roll-div="1">1/4</button>
            <button class="pill ${state.rollDivision === 2 ? 'on' : ''}" data-roll-div="2">1/8</button>
            <button class="pill ${state.rollDivision === 4 ? 'on' : ''}" data-roll-div="4">1/16</button>
          </div>
        </div>
        <div class="roll-toolbar">
          <span class="range-label">CHORD</span>
          <div style="display:flex;gap:4px">
            ${[['single', 'SINGLE'], ['major', 'MAJOR'], ['minor', 'MINOR'], ['seventh', '7TH']].map(([id, label]) => `<button class="pill ${state.rollChord === id ? 'on' : ''}" data-roll-chord="${id}">${label}</button>`).join('')}
          </div>
        </div>
        <div class="roll-toolbar">
          <button class="pill ${arp.enabled ? 'on' : ''}" id="rollArpToggle">ARP</button>
          <div style="display:flex;gap:4px">
            ${model.ARPEGGIATOR_PATTERNS.map((pattern) => `<button class="pill ${arp.pattern === pattern.id ? 'on' : ''}" data-arp-pattern="${pattern.id}">${pattern.name}</button>`).join('')}
          </div>
          <span class="range-label">RATE</span>
          <div style="display:flex;gap:4px">
            ${model.ARPEGGIATOR_RATES.map((rate) => `<button class="pill ${arp.rate === rate.id ? 'on' : ''}" data-arp-rate="${rate.id}">${rate.name}</button>`).join('')}
          </div>
        </div>
        <div class="roll-toolbar">
          <label class="range-label" for="rollArpOctaves">OCT</label>
          <select id="rollArpOctaves" style="height:26px;border-radius:7px;border:1px solid var(--line);background:var(--panel-highlight);color:var(--text);padding:0 6px;font-family:'SF Mono',ui-monospace,monospace;font-size:10px">
            ${[1, 2, 3, 4].map((value) => `<option value="${value}" ${arp.octaves === value ? 'selected' : ''}>${value}</option>`).join('')}
          </select>
          <label class="range-label" for="rollArpGate">GATE</label>
          <input type="range" id="rollArpGate" min="0.05" max="1" step="0.05" value="${arp.gate}">
          <span class="range-label" id="rollArpGateValue">${Math.round(arp.gate * 100)}%</span>
          <label class="range-label" for="rollArpSwing">SWING</label>
          <input type="range" id="rollArpSwing" min="0" max="0.4" step="0.01" value="${arp.swing}">
          <span class="range-label" id="rollArpSwingValue">${Math.round(arp.swing * 100)}%</span>
        </div>
        <div class="roll-toolbar quantize-toolbar">
          <button class="pill" id="rollQuantizeBtn" ${state.selectedNotes.length ? '' : 'disabled'}>QUANTIZE SELECTED</button>
          <label class="range-label" for="rollQuantizeStrength">STRENGTH</label>
          <input type="range" id="rollQuantizeStrength" min="0" max="1" step="0.05" value="${state.rollQuantizeStrength}">
          <span class="range-label" id="rollQuantizeValue">${Math.round(state.rollQuantizeStrength * 100)}%</span>
        </div>
        <div class="roll-toolbar">
          <button class="pill" id="rollMidiImport">IMPORT MIDI</button>
          <button class="pill" id="rollMidiExport">EXPORT MIDI</button>
          <span class="range-label">Named after the track · ${state.session.tempo} BPM</span>
        </div>
        <div class="roll-grid-wrap"><div class="roll-keys">${keys.join('')}</div>
          <div class="roll-scroll" id="rollScroll">
            <div class="roll-grid" id="rollGrid" style="width:${contentWidth}px;height:${gridHeight}px">
              <canvas class="automation-canvas" id="rollCanvas"></canvas>
              <div class="roll-playhead"></div>
            </div>
          </div>
        </div>
      </div>
    </div>`, { tall: true });

  const grid = document.getElementById('rollGrid');
  drawRollGrid(grid, contentWidth, gridHeight, beatPx);
  track.notes.forEach((note) => grid.appendChild(buildRollNote(track, note, beatPx)));

  document.getElementById('rollPlayBtn').addEventListener('click', () => {
    togglePlay();
    const button = document.getElementById('rollPlayBtn');
    if (button) button.textContent = engine.isPlaying ? '❚❚' : '▶';
  });

  document.getElementById('rollDeleteBtn').addEventListener('click', () => {
    const selected = new Set(state.selectedNotes);
    if (!selected.size) return;
    snapshot();
    track.notes = track.notes.filter((note) => !selected.has(note.id));
    state.selectedNote = null;
    state.selectedNotes = [];
    persist();
    engine.rebuild();
    renderRollModal();
  });

  document.getElementById('rollQuantizeBtn').addEventListener('click', () => {
    quantizeSelectedNotes(track);
  });
  const strength = document.getElementById('rollQuantizeStrength');
  strength.addEventListener('input', () => {
    state.rollQuantizeStrength = Number(strength.value);
    document.getElementById('rollQuantizeValue').textContent = `${Math.round(state.rollQuantizeStrength * 100)}%`;
  });

  document.getElementById('rollMidiImport').addEventListener('click', () => {
    el.midiImportInput.click();
  });
  document.getElementById('rollMidiExport').addEventListener('click', () => {
    exportTrackMidi(track);
  });

  document.querySelectorAll('[data-roll-div]').forEach((button) => {
    button.addEventListener('click', () => {
      state.rollDivision = Number(button.dataset.rollDiv);
      renderRollModal();
    });
  });
  document.querySelectorAll('[data-roll-chord]').forEach((button) => {
    button.addEventListener('click', () => {
      state.rollChord = button.dataset.rollChord;
      renderRollModal();
    });
  });

  document.getElementById('rollArpToggle').addEventListener('click', () => {
    updateArpeggiator(track, { enabled: !arp.enabled });
  });
  document.querySelectorAll('[data-arp-pattern]').forEach((button) => {
    button.addEventListener('click', () => {
      updateArpeggiator(track, { pattern: button.dataset.arpPattern });
    });
  });
  document.querySelectorAll('[data-arp-rate]').forEach((button) => {
    button.addEventListener('click', () => {
      updateArpeggiator(track, { rate: button.dataset.arpRate });
    });
  });

  const arpOctaves = document.getElementById('rollArpOctaves');
  arpOctaves.addEventListener('change', () => {
    updateArpeggiator(track, { octaves: Number(arpOctaves.value) });
  });

  const arpGate = document.getElementById('rollArpGate');
  arpGate.addEventListener('input', () => {
    updateArpeggiator(track, { gate: Number(arpGate.value) }, { rerender: false, reschedule: false });
    document.getElementById('rollArpGateValue').textContent = `${Math.round(Number(arpGate.value) * 100)}%`;
  });
  arpGate.addEventListener('change', () => engine.rebuild());

  const arpSwing = document.getElementById('rollArpSwing');
  arpSwing.addEventListener('input', () => {
    updateArpeggiator(track, { swing: Number(arpSwing.value) }, { rerender: false, reschedule: false });
    document.getElementById('rollArpSwingValue').textContent = `${Math.round(Number(arpSwing.value) * 100)}%`;
  });
  arpSwing.addEventListener('change', () => engine.rebuild());

  grid.addEventListener('pointerdown', (event) => {
    const noteEl = event.target.closest('.roll-note');
    const rect = grid.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;

    if (!noteEl) {
      const pitch = model.clamp(model.NOTE_HIGH - Math.floor(y / NOTE_HEIGHT), model.NOTE_LOW, model.NOTE_HIGH);
      const start = Math.max(0, snapTime(x / (beatPx / beatDuration())));
      const length = Math.round(start / rollSnap()) * rollSnap();
      snapshot();
      const addedIds = [];
      rollChordIntervals(state.rollChord).forEach((interval) => {
        const chordPitch = pitch + interval;
        if (chordPitch < model.NOTE_LOW || chordPitch > model.NOTE_HIGH) return;
        const note = { id: model.uid(), pitch: chordPitch, start: length, duration: rollSnap(), velocity: 0.8 };
        track.notes.push(note);
        addedIds.push(note.id);
      });
      if (!addedIds.length) return;
      track.notes.sort((a, b) => a.start - b.start);
      state.selectedNote = addedIds[0];
      state.selectedNotes = addedIds;
      persist();
      engine.rebuild();
      renderRollModal();
      return;
    }

    const note = track.notes.find((item) => item.id === noteEl.dataset.note);
    if (!note) return;
    const modifierSelect = event.shiftKey || event.metaKey || event.ctrlKey;
    if (modifierSelect) {
      state.selectedNotes = state.selectedNotes.includes(note.id)
        ? state.selectedNotes.filter((id) => id !== note.id)
        : [...state.selectedNotes, note.id];
      state.selectedNote = state.selectedNotes[0] || null;
      renderRollModal();
      return;
    }
    if (!state.selectedNotes.includes(note.id)) state.selectedNotes = [note.id];
    state.selectedNote = note.id;
    grid.querySelectorAll('.roll-note').forEach((element) => {
      element.classList.toggle('selected', state.selectedNotes.includes(element.dataset.note));
    });

    const isVelocity = event.target.classList.contains('velocity-handle');
    const isResize = event.target.classList.contains('resize');
    const startX = event.clientX;
    const startY = event.clientY;
    const selected = new Set(state.selectedNotes);
    const movingNotes = isResize || isVelocity
      ? [{ note, origin: { ...note }, element: noteEl }]
      : track.notes.filter((item) => selected.has(item.id)).map((item) => ({
        note: item,
        origin: { ...item },
        element: grid.querySelector(`[data-note="${item.id}"]`)
      }));
    snapshot();

    startDrag((moveEvent) => {
      const dx = moveEvent.clientX - startX;
      const dy = moveEvent.clientY - startY;
      if (isVelocity) {
        note.velocity = model.clamp(originVelocity(movingNotes[0].origin.velocity) - dy / 60, 0.05, 1);
      } else if (isResize) {
        note.duration = Math.max(rollSnap(), movingNotes[0].origin.duration + dx / (beatPx / beatDuration()));
        note.duration = Math.round(note.duration / rollSnap()) * rollSnap();
      } else {
        for (const item of movingNotes) {
          const time = item.origin.start + dx / (beatPx / beatDuration());
          item.note.start = Math.max(0, Math.round(time / rollSnap()) * rollSnap());
          const pitchDelta = -Math.round(dy / NOTE_HEIGHT);
          item.note.pitch = model.clamp(item.origin.pitch + pitchDelta, model.NOTE_LOW, model.NOTE_HIGH);
        }
      }
      movingNotes.forEach((item) => positionRollNote(item.element, item.note, beatPx));
    }, () => {
      track.notes.sort((a, b) => a.start - b.start);
      persist();
      engine.rebuild();
      renderRollModal();
    });
  });
}

function updateArpeggiator(track, patch, { rerender = true, reschedule = true } = {}) {
  track.arpeggiator = {
    ...model.defaultArpeggiator(),
    ...(track.arpeggiator || {}),
    ...patch
  };
  persist();
  if (reschedule) engine.rebuild();
  if (rerender) renderRollModal();
}

function originVelocity(value) {
  return model.clamp(Number(value ?? 0.8), 0.05, 1);
}

function quantizeSelectedNotes(track) {
  const selected = new Set(state.selectedNotes);
  if (!selected.size) return;
  const snap = rollSnap();
  const strength = model.clamp(state.rollQuantizeStrength, 0, 1);
  snapshot();
  track.notes.forEach((note) => {
    if (!selected.has(note.id)) return;
    const target = Math.round(note.start / snap) * snap;
    note.start = Math.max(0, note.start + (target - note.start) * strength);
  });
  track.notes.sort((a, b) => a.start - b.start);
  persist();
  engine.rebuild();
  renderRollModal();
  toast('Selected notes quantized');
}

function exportTrackMidi(track) {
  if (!track || !track.notes || !track.notes.length) {
    toast('This track has no notes to export yet');
    return;
  }
  const data = model.encodeMidi(track, state.session.tempo);
  download(new Blob([data], { type: 'audio/midi' }), model.midiFileName(track.name));
  toast('MIDI file exported');
}

async function importMidiFile(file) {
  try {
    const parsed = model.parseMidi(await file.arrayBuffer());
    const track = state.rollTrackId ? trackById(state.rollTrackId) : null;
    const notesLabel = parsed.notes.length === 1 ? '1 note' : `${parsed.notes.length} notes`;
    const replaceNotes = track
      ? window.confirm(`“${file.name}” has ${notesLabel}. Press OK to replace the notes on “${track.name}”, or Cancel to add them as a new track.`)
      : true;

    snapshot();
    if (replaceNotes && track) {
      track.notes = parsed.notes;
      state.selectedNote = null;
      state.selectedNotes = [];
    } else {
      const newTrack = model.createTrack({
        name: parsed.name || file.name.replace(/\.[^.]+$/, '') || 'MIDI Track',
        index: state.session.tracks.length
      });
      newTrack.notes = parsed.notes;
      state.session.tracks.push(newTrack);
      state.rollTrackId = newTrack.id;
      state.selectedNote = null;
      state.selectedNotes = [];
    }

    if (parsed.tempo) {
      state.session.tempo = model.clamp(parsed.tempo, 60, 200);
    }

    persist();
    engine.rebuild();
    if (state.modal === 'roll') {
      renderRollModal();
    } else {
      render();
    }
    toast(`${notesLabel} imported from ${file.name}`);
  } catch (error) {
    console.warn('MIDI import failed', error);
    toast(error && error.message ? error.message : 'That MIDI file could not be read');
  }
}

function drawRollGrid(grid, width, height, beatPx) {
  const canvas = document.getElementById('rollCanvas');
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.floor(width * dpr);
  canvas.height = Math.floor(height * dpr);
  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;
  const ctx = canvas.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, width, height);

  for (let pitch = model.NOTE_LOW; pitch <= model.NOTE_HIGH; pitch += 1) {
    const y = (model.NOTE_HIGH - pitch) * NOTE_HEIGHT;
    if (model.isBlackKey(pitch)) {
      ctx.fillStyle = 'rgba(255,255,255,0.03)';
      ctx.fillRect(0, y, width, NOTE_HEIGHT);
    }
    ctx.strokeStyle = 'rgba(255,255,255,0.05)';
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(width, y);
    ctx.stroke();
  }

  const beats = Math.ceil(width / beatPx);
  for (let index = 0; index < beats; index += 1) {
    const x = index * beatPx;
    const isBar = index % 4 === 0;
    ctx.strokeStyle = isBar ? 'rgba(255,255,255,0.22)' : 'rgba(255,255,255,0.08)';
    ctx.lineWidth = isBar ? 1.2 : 1;
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, height);
    ctx.stroke();
    if (isBar) {
      ctx.fillStyle = 'rgba(154,154,159,0.9)';
      ctx.font = '8px "SF Mono", ui-monospace, monospace';
      ctx.fillText(String(Math.floor(index / 4) + 1), x + 3, 9);
    }
  }
}

function buildRollNote(track, note, beatPx) {
  const element = document.createElement('div');
  element.className = `roll-note ${state.selectedNotes.includes(note.id) ? 'selected' : ''}`;
  element.dataset.note = note.id;
  element.innerHTML = `${model.noteName(note.pitch)}<span class="velocity-bar"><span></span></span><span class="velocity-handle" title="Drag to change velocity"></span><span class="resize"></span>`;
  positionRollNote(element, note, beatPx);
  return element;
}

function positionRollNote(element, note, beatPx) {
  const pps = beatPx / beatDuration();
  const velocity = originVelocity(note.velocity);
  element.style.left = `${Math.max(0, note.start) * pps}px`;
  element.style.top = `${(model.NOTE_HIGH - note.pitch) * NOTE_HEIGHT + 1.5}px`;
  element.style.width = `${Math.max(14, note.duration * pps)}px`;
  element.style.setProperty('--note-velocity', `${velocity * 100}%`);
}

// ---------- Modal shells ----------

function openModal(html, { tall = false } = {}) {
  el.modalRoot.innerHTML = `<div class="modal-backdrop"></div><section class="modal ${tall ? 'tall' : ''} ${state.modal === 'instruments' ? 'instrument-rack-modal' : ''}">${html}</section>`;
  el.modalRoot.querySelector('.modal-backdrop').addEventListener('click', closeModal);
  el.modalRoot.querySelectorAll('[data-close]').forEach((button) => {
    button.addEventListener('click', closeModal);
  });
  el.modalRoot.style.pointerEvents = 'auto';
}

function closeModal() {
  if (state.instrumentRecording) stopInstrumentRecording(false);
  if (state.microphoneRequesting) {
    state.microphoneRequesting = false;
    state.microphoneRequestID += 1;
  }
  if (state.microphoneRecording) stopMicrophoneRecording(false);
  state.sessionsRequestID = (state.sessionsRequestID || 0) + 1;
  (state.exportPreviewURLs || []).forEach((url) => URL.revokeObjectURL(url));
  state.exportPreviewURLs = [];
  (state.takePreviewURLs || []).forEach((url) => url && URL.revokeObjectURL(url));
  state.takePreviewURLs = [];
  state.takeLaneTrackId = null;
  state.modal = null;
  el.modalRoot.innerHTML = '';
  el.modalRoot.style.pointerEvents = 'none';
  if (instrumentVoice) instrumentVoice.stopAll();
}

// ---------- Mixer ----------

function openMixer() {
  const session = state.session;
  if (!session) return;
  state.modal = 'mixer';

  if (!session.auxA || !session.auxB) {
    const defaults = model.defaultAuxBuses();
    session.auxA = session.auxA || defaults.auxA;
    session.auxB = session.auxB || defaults.auxB;
  }

  const auxSendRow = (track, bus) => {
    const stem = bus.toLowerCase();
    const value = bus === 'A' ? (track.sendA ?? 0) : (track.sendB ?? 0);
    return `<div class="send-row">
        <span class="send-label">${bus}</span>
        <input type="range" class="send-slider" min="0" max="1" step="0.01" value="${value}" data-send-${stem}="${track.id}" aria-label="Aux ${bus} send for ${escapeHtml(track.name)}" title="Aux ${bus} send">
        <span class="send-value" data-send-label="${stem}-${track.id}">${Math.round(value * 100)}%</span>
      </div>`;
  };

  const auxReturnRow = (bus, id) => {
    const fxLabel = bus.effect === 'delay' ? 'DELAY' : 'REVERB';
    return `<div class="aux-return">
        <div class="aux-return-head">
          <strong>${escapeHtml(bus.name.toUpperCase())}</strong>
          <span class="aux-effect">${fxLabel}</span>
        </div>
        <input type="range" class="aux-level" min="0" max="1" step="0.01" value="${bus.level}" data-aux-level="${id}" aria-label="${escapeHtml(bus.name)} return level">
        <span class="db" data-aux-db="${id}">${model.dbLabel(bus.level)}</span>
        <button class="mini ${bus.bypassed ? '' : 'on'}" data-aux-bypass="${id}">${bus.bypassed ? 'BYP' : 'ON'}</button>
      </div>`;
  };

  const strips = session.tracks.map((track, index) => {
    const color = trackColorFor(track, index);
    const selected = state.selectedGroupTrackIDs.includes(track.id);
    return `<div class="strip ${state.groupSelectionMode && selected ? 'group-selected' : ''}" style="--track-color:${color}">
      <div class="strip-name">${escapeHtml(track.name.toUpperCase())}</div>
      ${state.groupSelectionMode ? `<button class="pill ${selected ? 'on' : ''}" data-group-select="${track.id}">${selected ? 'SELECTED' : 'ADD TO BUS'}</button>` : ''}
      ${state.mode === 'pro' ? `
      <input type="range" class="pan-slider" min="-1" max="1" step="0.05" value="${track.pan}" data-mix-pan="${track.id}" style="width:64px" aria-label="Pan for ${escapeHtml(track.name)}">
      <div class="pan-label" data-pan-label="${track.id}">${model.panLabel(track.pan)}</div>` : ''}
      <div class="fader-block">
        <input type="range" class="fader" min="0" max="1" step="0.01" value="${track.volume}" data-mix-volume="${track.id}" aria-label="Volume for ${escapeHtml(track.name)}">
        <div class="meter" data-mix-meter="${track.id}"><div class="meter-fill"></div></div>
      </div>
      <div class="db" data-db-label="${track.id}">${model.dbLabel(track.volume)}</div>
      <div class="sends">
        ${auxSendRow(track, 'A')}
        ${state.mode === 'pro' ? auxSendRow(track, 'B') : ''}
      </div>
      <div class="mini-row">
        <button class="mini ${track.muted ? 'on' : ''}" data-mix-mute="${track.id}">M</button>
        <button class="mini ${track.soloed ? 'on' : ''}" data-mix-solo="${track.id}">S</button>
      </div>
    </div>`;
  }).join('');

  const buses = (session.groups || []).map((group) => {
    const color = model.trackColor(group.colorIndex);
    const members = session.tracks.filter((track) => group.trackIDs.includes(track.id)).map((track) => track.name).join(' · ');
    return `<div class="group-bus" style="--group-color:${color}">
      <div class="group-bus-meta"><strong>${escapeHtml(group.name)}</strong><span>${escapeHtml(members)}</span></div>
      <input type="range" class="group-volume" min="0" max="1" step="0.01" value="${group.volume}" data-group-volume="${group.id}" aria-label="${escapeHtml(group.name)} bus level">
      <span class="db" data-group-db="${group.id}">${model.dbLabel(group.volume)}</span>
      <div class="mini-row">
        <button class="mini ${group.muted ? 'on' : ''}" data-group-mute="${group.id}">M</button>
        <button class="mini ${group.soloed ? 'on' : ''}" data-group-solo="${group.id}">S</button>
      </div>
      <button class="icon-btn" data-group-rename="${group.id}" title="Rename bus">✎</button>
      <button class="icon-btn" data-group-delete="${group.id}" title="Dissolve bus">×</button>
    </div>`;
  }).join('');

  const selectionTools = state.groupSelectionMode
    ? `<div class="group-select-bar"><span>${state.selectedGroupTrackIDs.length} tracks selected</span><button class="pill" id="cancelGroupSelection">Cancel</button><button class="pill on" id="createGroupBtn" ${state.selectedGroupTrackIDs.length < 2 ? 'disabled' : ''}>Create Bus</button></div>`
    : '';

  openModal(`
    <header class="modal-header">
      <div style="flex:1;min-width:0">
        <h2>Mixer</h2>
        <div class="sub">${escapeHtml(session.name.toUpperCase())} · ${session.tracks.length} ${session.tracks.length === 1 ? 'CHANNEL' : 'CHANNELS'}</div>
      </div>
      <button class="pill ${state.groupSelectionMode ? 'on' : ''}" id="groupTracksBtn" ${state.mode === 'pro' ? '' : 'hidden'}>${state.groupSelectionMode ? 'GROUPING' : 'GROUP TRACKS'}</button>
      <button class="modal-close" data-close>Done</button>
    </header>
    <div class="modal-body">
      ${state.mode === 'pro' ? selectionTools : ''}
      ${state.mode === 'pro' && buses ? `<div class="group-bus-list"><h3>BUSES</h3>${buses}</div>` : ''}
      <div class="mixer-board">
        ${strips}
        <div class="strip master">
          <div class="strip-name" style="color:var(--accent)">MASTER</div>
          <div class="pan-label">OUTPUT</div>
          <div class="fader-block">
            <input type="range" class="fader" min="0" max="1" step="0.01" value="${session.masterVolume}" data-mix-master aria-label="Master level">
            <div class="meter" data-master-meter><div class="meter-fill"></div></div>
          </div>
          <div class="db" data-db-label="master">${model.dbLabel(session.masterVolume)}</div>
          <div class="mini-row"><button class="mini on">ST</button></div>
        </div>
      </div>
      <div class="aux-returns">
        <h3>AUX RETURNS</h3>
        <div class="aux-return-list">
          ${auxReturnRow(session.auxA, 'A')}
          ${state.mode === 'pro' ? auxReturnRow(session.auxB, 'B') : ''}
        </div>
      </div>
    </div>
    <footer class="modal-footer">
      <button class="tool" id="mixerPlayBtn">${engine.isPlaying ? 'Pause' : 'Play'}</button>
      <button class="tool" id="mixerStopBtn">Stop</button>
      <span class="range-label" style="margin-left:auto" id="mixerTime">${model.formatTime(currentPosition())}</span>
    </footer>`, { tall: true });

  const groupToggle = document.getElementById('groupTracksBtn');
  groupToggle.addEventListener('click', () => {
    state.groupSelectionMode = !state.groupSelectionMode;
    state.selectedGroupTrackIDs = [];
    openMixer();
  });
  const cancelSelection = document.getElementById('cancelGroupSelection');
  cancelSelection?.addEventListener('click', () => {
    state.groupSelectionMode = false;
    state.selectedGroupTrackIDs = [];
    openMixer();
  });
  document.getElementById('createGroupBtn')?.addEventListener('click', createSelectedTrackGroup);
  el.modalRoot.querySelectorAll('[data-group-select]').forEach((button) => {
    button.addEventListener('click', () => {
      const id = button.dataset.groupSelect;
      state.selectedGroupTrackIDs = state.selectedGroupTrackIDs.includes(id)
        ? state.selectedGroupTrackIDs.filter((item) => item !== id)
        : [...state.selectedGroupTrackIDs, id];
      openMixer();
    });
  });

  el.modalRoot.querySelectorAll('[data-group-volume]').forEach((input) => {
    input.addEventListener('pointerdown', () => snapshot());
    input.addEventListener('input', () => {
      const group = session.groups.find((item) => item.id === input.dataset.groupVolume);
      if (!group) return;
      group.volume = model.clamp(Number(input.value), 0, 1);
      engine.updateGroups(session.groups);
      const label = el.modalRoot.querySelector(`[data-group-db="${group.id}"]`);
      if (label) label.textContent = model.dbLabel(group.volume);
      persist();
    });
  });
  el.modalRoot.querySelectorAll('[data-group-mute], [data-group-solo]').forEach((button) => {
    button.addEventListener('click', () => {
      const group = session.groups.find((item) => item.id === (button.dataset.groupMute || button.dataset.groupSolo));
      if (!group) return;
      if (button.hasAttribute('data-group-mute')) group.muted = !group.muted;
      else group.soloed = !group.soloed;
      engine.updateGroups(session.groups);
      persist();
      openMixer();
    });
  });
  el.modalRoot.querySelectorAll('[data-group-rename]').forEach((button) => {
    button.addEventListener('click', () => {
      const group = session.groups.find((item) => item.id === button.dataset.groupRename);
      if (!group) return;
      const name = window.prompt('Bus name', group.name);
      if (name === null || !name.trim()) return;
      group.name = name.trim();
      persist();
      render();
      openMixer();
    });
  });
  el.modalRoot.querySelectorAll('[data-group-delete]').forEach((button) => {
    button.addEventListener('click', () => {
      const group = session.groups.find((item) => item.id === button.dataset.groupDelete);
      if (!group || !window.confirm(`Dissolve bus "${group.name}"? Its tracks will remain in the session.`)) return;
      session.groups = session.groups.filter((item) => item.id !== group.id);
      engine.updateGroups(session.groups);
      persist();
      render();
      openMixer();
    });
  });

  el.modalRoot.querySelectorAll('[data-mix-volume]').forEach((input) => {
    input.addEventListener('pointerdown', () => snapshot());
    input.addEventListener('input', () => {
      const track = trackById(input.dataset.mixVolume);
      if (!track) return;
      track.volume = model.clamp(Number(input.value), 0, 1);
      engine.updateMix(state.playhead);
      const dbLabel = el.modalRoot.querySelector(`[data-db-label="${track.id}"]`);
      if (dbLabel) dbLabel.textContent = model.dbLabel(track.volume);
      persist();
    });
  });

  el.modalRoot.querySelectorAll('[data-mix-pan]').forEach((input) => {
    input.addEventListener('pointerdown', () => snapshot());
    input.addEventListener('input', () => {
      const track = trackById(input.dataset.mixPan);
      if (!track) return;
      setTrackPan(track, Number(input.value));
      const label = el.modalRoot.querySelector(`[data-pan-label="${track.id}"]`);
      if (label) label.textContent = model.panLabel(track.pan);
      persist();
    });
  });

  const master = el.modalRoot.querySelector('[data-mix-master]');
  if (master) {
    master.addEventListener('pointerdown', () => snapshot());
    master.addEventListener('input', () => {
      session.masterVolume = model.clamp(Number(master.value), 0, 1);
      engine.updateMix(state.playhead);
      const dbLabel = el.modalRoot.querySelector('[data-db-label="master"]');
      if (dbLabel) dbLabel.textContent = model.dbLabel(session.masterVolume);
      persist();
    });
  }

  el.modalRoot.querySelectorAll('[data-mix-mute]').forEach((button) => {
    button.addEventListener('click', () => {
      toggleMute(button.dataset.mixMute);
      openMixer();
    });
  });

  el.modalRoot.querySelectorAll('[data-mix-solo]').forEach((button) => {
    button.addEventListener('click', () => {
      toggleSolo(button.dataset.mixSolo);
      openMixer();
    });
  });

  el.modalRoot.querySelectorAll('[data-send-a], [data-send-b]').forEach((input) => {
    input.addEventListener('pointerdown', () => snapshot());
    input.addEventListener('input', () => {
      const isA = input.hasAttribute('data-send-a');
      const track = trackById(isA ? input.dataset.sendA : input.dataset.sendB);
      if (!track) return;
      const value = model.clamp(Number(input.value), 0, 1);
      if (isA) track.sendA = value;
      else track.sendB = value;
      const label = el.modalRoot.querySelector(`[data-send-label="${isA ? 'a' : 'b'}-${track.id}"]`);
      if (label) label.textContent = `${Math.round(value * 100)}%`;
      engine.updateMix(state.playhead);
      persist();
    });
  });

  el.modalRoot.querySelectorAll('[data-aux-level]').forEach((input) => {
    input.addEventListener('pointerdown', () => snapshot());
    input.addEventListener('input', () => {
      const id = input.dataset.auxLevel;
      const bus = id === 'B' ? session.auxB : session.auxA;
      if (!bus) return;
      bus.level = model.clamp(Number(input.value), 0, 1);
      const label = el.modalRoot.querySelector(`[data-aux-db="${id}"]`);
      if (label) label.textContent = model.dbLabel(bus.level);
      engine.applyAuxBuses();
      persist();
    });
  });

  el.modalRoot.querySelectorAll('[data-aux-bypass]').forEach((button) => {
    button.addEventListener('click', () => {
      const id = button.dataset.auxBypass;
      const bus = id === 'B' ? session.auxB : session.auxA;
      if (!bus) return;
      snapshot();
      bus.bypassed = !bus.bypassed;
      engine.applyAuxBuses();
      persist();
      openMixer();
    });
  });

  document.getElementById('mixerPlayBtn').addEventListener('click', () => {
    togglePlay();
    const button = document.getElementById('mixerPlayBtn');
    if (button) button.textContent = engine.isPlaying ? 'Pause' : 'Play';
  });

  document.getElementById('mixerStopBtn').addEventListener('click', () => {
    stopPlayback();
    const button = document.getElementById('mixerPlayBtn');
    if (button) button.textContent = 'Play';
  });
}

function createSelectedTrackGroup() {
  const ids = [...state.selectedGroupTrackIDs];
  if (ids.length < 2) return;
  const entered = window.prompt('Bus name', `Group ${(state.session.groups || []).length + 1}`);
  if (entered === null) return;
  const name = entered.trim() || `Group ${(state.session.groups || []).length + 1}`;
  snapshot();
  const groups = state.session.groups || (state.session.groups = []);
  groups.forEach((group) => {
    group.trackIDs = group.trackIDs.filter((id) => !ids.includes(id));
  });
  state.session.groups = groups.filter((group) => group.trackIDs.length > 0);
  const usedColors = new Set(state.session.groups.map((group) => group.colorIndex));
  const colorIndex = [0, 1, 2, 3].find((index) => !usedColors.has(index)) ?? state.session.groups.length % 4;
  state.session.groups.push({
    id: model.uid(),
    name,
    colorIndex,
    trackIDs: ids,
    volume: 1,
    muted: false,
    soloed: false
  });
  state.groupSelectionMode = false;
  state.selectedGroupTrackIDs = [];
  engine.updateGroups(state.session.groups);
  persist();
  render();
  openMixer();
}


// ---------- Equalizer + compressor ----------

function openEQ(trackId) {
  const track = trackById(trackId);
  if (!track) return;
  state.modal = 'eq';

  const band = (key, title, gainRange) => `
    ${state.mode === 'pro' ? `
    <div class="field">
      <div class="label-row"><span>${title} frequency</span><span data-eq-value="${key}-frequency">${Math.round(track.eq[key].frequency)} Hz</span></div>
      <input type="range" min="30" max="16000" step="10" value="${track.eq[key].frequency}" data-eq="${key}-frequency" data-track="${track.id}">
    </div>` : ''}
    <div class="field">
      <div class="label-row"><span>${title} gain</span><span data-eq-value="${key}-gain">${track.eq[key].gain.toFixed(1)} dB</span></div>
      <input type="range" min="${gainRange[0]}" max="${gainRange[1]}" step="0.5" value="${track.eq[key].gain}" data-eq="${key}-gain" data-track="${track.id}">
    </div>`;

  openModal(`
    <header class="modal-header">
      <div style="flex:1;min-width:0">
        <h2>Equalizer</h2>
        <div class="sub">${escapeHtml(track.name.toUpperCase())}</div>
      </div>
      <button class="modal-close" data-close>Done</button>
    </header>
    <div class="modal-body">
      <div class="panel">
        <div class="switch-row" style="margin-bottom:12px">
          <h3 style="margin:0">EQUA</h3>
          <button class="switch ${track.eq.bypassed ? '' : 'on'}" data-eq-bypass="${track.id}" aria-label="Toggle equalizer"></button>
        </div>
        ${band('low', 'Low shelf', [-24, 24])}
        ${band('mid', 'Mid', [-24, 24])}
        ${band('high', 'High shelf', [-24, 24])}
      </div>
      ${state.mode === 'pro' ? `
      <div class="panel">
        <div class="switch-row" style="margin-bottom:12px">
          <h3 style="margin:0">COMPRESSOR</h3>
          <button class="switch ${track.comp.bypassed ? '' : 'on'}" data-comp-bypass="${track.id}" aria-label="Toggle compressor"></button>
        </div>
        <div class="field">
          <div class="label-row"><span>Threshold</span><span data-comp-value="threshold">${track.comp.threshold.toFixed(0)} dB</span></div>
          <input type="range" min="-60" max="0" step="1" value="${track.comp.threshold}" data-comp="threshold" data-track="${track.id}">
        </div>
        <div class="field">
          <div class="label-row"><span>Ratio</span><span data-comp-value="ratio">${track.comp.ratio.toFixed(1)} : 1</span></div>
          <input type="range" min="1" max="20" step="0.5" value="${track.comp.ratio}" data-comp="ratio" data-track="${track.id}">
        </div>
        <div class="field">
          <div class="label-row"><span>Attack</span><span data-comp-value="attack">${Math.round(track.comp.attack * 1000)} ms</span></div>
          <input type="range" min="0.001" max="0.2" step="0.001" value="${track.comp.attack}" data-comp="attack" data-track="${track.id}">
        </div>
        <div class="field">
          <div class="label-row"><span>Release</span><span data-comp-value="release">${Math.round(track.comp.release * 1000)} ms</span></div>
          <input type="range" min="0.02" max="1" step="0.01" value="${track.comp.release}" data-comp="release" data-track="${track.id}">
        </div>
      </div>` : ''}
    </div>`, { tall: true });

  el.modalRoot.querySelectorAll('[data-eq]').forEach((input) => {
    input.addEventListener('pointerdown', () => snapshot());
    input.addEventListener('input', () => {
      const current = trackById(input.dataset.track);
      if (!current) return;
      const [key, property] = input.dataset.eq.split('-');
      current.eq[key][property] = Number(input.value);
      const label = el.modalRoot.querySelector(`[data-eq-value="${key}-${property}"]`);
      if (label) {
        label.textContent = property === 'gain'
          ? `${Number(input.value).toFixed(1)} dB`
          : `${Math.round(Number(input.value))} Hz`;
      }
      const nodes = engine.trackNodes.get(current.id);
      if (nodes) engine.applyTrackSettings(current, nodes);
      persist();
    });
  });

  el.modalRoot.querySelectorAll('[data-comp]').forEach((input) => {
    input.addEventListener('pointerdown', () => snapshot());
    input.addEventListener('input', () => {
      const current = trackById(input.dataset.track);
      if (!current) return;
      const key = input.dataset.comp;
      current.comp[key] = Number(input.value);
      const label = el.modalRoot.querySelector(`[data-comp-value="${key}"]`);
      if (label) {
        if (key === 'threshold') label.textContent = `${Number(input.value).toFixed(0)} dB`;
        else if (key === 'ratio') label.textContent = `${Number(input.value).toFixed(1)} : 1`;
        else label.textContent = `${Math.round(Number(input.value) * 1000)} ms`;
      }
      const nodes = engine.trackNodes.get(current.id);
      if (nodes) engine.applyTrackSettings(current, nodes);
      persist();
    });
  });

  const eqBypass = el.modalRoot.querySelector('[data-eq-bypass]');
  if (eqBypass) {
    eqBypass.addEventListener('click', () => {
      const current = trackById(eqBypass.dataset.eqBypass);
      if (!current) return;
      snapshot();
      current.eq.bypassed = !current.eq.bypassed;
      eqBypass.classList.toggle('on', !current.eq.bypassed);
      const nodes = engine.trackNodes.get(current.id);
      if (nodes) engine.applyTrackSettings(current, nodes);
      persist();
    });
  }

  const compBypass = el.modalRoot.querySelector('[data-comp-bypass]');
  if (compBypass) {
    compBypass.addEventListener('click', () => {
      const current = trackById(compBypass.dataset.compBypass);
      if (!current) return;
      snapshot();
      current.comp.bypassed = !current.comp.bypassed;
      compBypass.classList.toggle('on', !current.comp.bypassed);
      const nodes = engine.trackNodes.get(current.id);
      if (nodes) engine.applyTrackSettings(current, nodes);
      persist();
    });
  }
}

// ---------- Master effects ----------

function delayBeatLabel(beats) {
  const choices = [0.25, 0.5, 0.75, 1, 1.5, 2];
  const closest = choices.reduce((best, value) => (
    Math.abs(value - beats) < Math.abs(best - beats) ? value : best
  ), choices[0]);
  return { 0.25: '1/16', 0.5: '1/8', 0.75: '1/8.', 1: '1/4', 1.5: '1/4.' }[closest] || '1/2';
}

function reverbRoomName(decay) {
  if (decay < 0.6) return 'Small Room';
  if (decay < 1.2) return 'Medium Room';
  if (decay < 2) return 'Large Room';
  if (decay < 2.8) return 'Medium Hall';
  if (decay < 3.8) return 'Large Hall';
  return 'Cathedral';
}

function openMasterEffects() {
  const session = state.session;
  if (!session) return;
  state.modal = 'masterfx';
  let fx = session.masterEffects;

  openModal(`
    <header class="modal-header">
      <div style="flex:1;min-width:0">
        <h2>Master Effects</h2>
        <div class="sub">${escapeHtml(session.name.toUpperCase())} · MASTER BUS</div>
      </div>
      <button class="modal-close" data-close>Done</button>
    </header>
    <div class="modal-body">
      <div class="panel">
        <div class="switch-row">
          <div>
            <h3 style="margin:0 0 4px">MASTER FX</h3>
            <span class="range-label">${fx.bypassed ? 'Bypassed · playback and bounce stay dry' : 'Reverb and delay on the master output'}</span>
          </div>
          <button class="switch ${fx.bypassed ? '' : 'on'}" id="fxBypass" aria-label="Toggle master effects"></button>
        </div>
      </div>
      <div class="panel">
        <h3>REVERB · ${reverbRoomName(fx.reverbDecay)}</h3>
        <div class="field">
          <div class="label-row"><span>Mix</span><span data-fx-value="reverbMix">${Math.round(fx.reverbMix * 100)}%</span></div>
          <input type="range" min="0" max="1" step="0.01" value="${fx.reverbMix}" data-fx="reverbMix">
        </div>
        ${state.mode === 'pro' ? `
        <div class="field">
          <div class="label-row"><span>Decay</span><span data-fx-value="reverbDecay">${fx.reverbDecay.toFixed(1)} s</span></div>
          <input type="range" min="0.2" max="5" step="0.1" value="${fx.reverbDecay}" data-fx="reverbDecay">
        </div>` : ''}
      </div>
      <div class="panel">
        <h3>DELAY</h3>
        <div class="field">
          <div class="label-row"><span>Time</span><span data-fx-value="delayBeats">${delayBeatLabel(fx.delayBeats)}</span></div>
          <select data-fx-select="delayBeats" style="height:34px;border-radius:8px;border:1px solid var(--line);background:var(--panel-highlight);color:var(--text);padding:0 8px;font-family:'SF Mono',ui-monospace,monospace;font-size:11px">
            <option value="0.25" ${fx.delayBeats === 0.25 ? 'selected' : ''}>1/16</option>
            <option value="0.5" ${fx.delayBeats === 0.5 ? 'selected' : ''}>1/8</option>
            <option value="0.75" ${fx.delayBeats === 0.75 ? 'selected' : ''}>1/8 dotted</option>
            <option value="1" ${fx.delayBeats === 1 ? 'selected' : ''}>1/4</option>
            <option value="1.5" ${fx.delayBeats === 1.5 ? 'selected' : ''}>1/4 dotted</option>
            <option value="2" ${fx.delayBeats === 2 ? 'selected' : ''}>1/2</option>
          </select>
        </div>
        ${state.mode === 'pro' ? `
        <div class="field">
          <div class="label-row"><span>Feedback</span><span data-fx-value="delayFeedback">${Math.round(fx.delayFeedback * 100)}%</span></div>
          <input type="range" min="0" max="0.9" step="0.01" value="${fx.delayFeedback}" data-fx="delayFeedback">
        </div>` : ''}
        <div class="field">
          <div class="label-row"><span>Mix</span><span data-fx-value="delayMix">${Math.round(fx.delayMix * 100)}%</span></div>
          <input type="range" min="0" max="1" step="0.01" value="${fx.delayMix}" data-fx="delayMix">
        </div>
      </div>
      <p class="range-label" style="text-align:center">Applied to playback and the mix bounce.</p>
    </div>`, { tall: true });

  const bypass = document.getElementById('fxBypass');
  bypass.addEventListener('click', () => {
    snapshot();
    fx.bypassed = !fx.bypassed;
    bypass.classList.toggle('on', !fx.bypassed);
    engine.applyMasterEffects();
    persist();
    openMasterEffects();
  });

  el.modalRoot.querySelectorAll('[data-fx]').forEach((input) => {
    input.addEventListener('input', () => {
      const key = input.dataset.fx;
      fx[key] = Number(input.value);
      const label = el.modalRoot.querySelector(`[data-fx-value="${key}"]`);
      if (label) {
        label.textContent = key === 'reverbDecay'
          ? `${Number(input.value).toFixed(1)} s`
          : `${Math.round(Number(input.value) * 100)}%`;
      }
      engine.applyMasterEffects();
      persist();
    });
  });

  const select = el.modalRoot.querySelector('[data-fx-select="delayBeats"]');
  if (select) {
    select.addEventListener('change', () => {
      fx.delayBeats = Number(select.value);
      const label = el.modalRoot.querySelector('[data-fx-value="delayBeats"]');
      if (label) label.textContent = delayBeatLabel(fx.delayBeats);
      engine.applyMasterEffects();
      persist();
    });
  }
}

// ---------- Mastering ----------

function formatMasterValue(key, value) {
  if (key.endsWith('attack') || key.endsWith('release')) return `${Math.round(value * 1000)} ms`;
  if (key === 'eq.midFrequency') return `${Math.round(value)} Hz`;
  if (key === 'compressor.ratio') return `${value.toFixed(1)}:1`;
  if (key === 'limiter.ceiling') return `${value.toFixed(1)} dB`;
  return `${value >= 0 ? '+' : ''}${value.toFixed(1)} dB`;
}

function updateMasteringMeters() {
  const session = state.session;
  if (!session || state.modal !== 'mastering' || !el.modalRoot) return;
  const chain = session.mastering || model.defaultMastering();
  const target = model.loudnessTarget(chain.target);
  const reading = engine.readLoudness();
  const values = {
    integrated: reading.integrated,
    shortTerm: reading.shortTerm,
    truePeak: reading.truePeak
  };

  el.modalRoot.querySelectorAll('[data-loudness]').forEach((node) => {
    const key = node.dataset.loudness;
    const value = values[key];
    node.textContent = value == null ? '—' : value.toFixed(1);
    node.classList.toggle('over', key === 'truePeak' && value != null && value > target.truePeak);
  });

  el.modalRoot.querySelectorAll('[data-loudness-bar]').forEach((node) => {
    const key = node.dataset.loudnessBar;
    const value = values[key];
    const isPeak = key === 'truePeak';
    const base = isPeak ? -12 : -36;
    const span = isPeak ? 12 : 36;
    const progress = value == null ? 0 : model.clamp((value - base) / span, 0, 1);
    node.style.width = `${Math.round(progress * 100)}%`;
    node.classList.toggle('over', isPeak && value != null && value > target.truePeak);
  });
}

function openMastering() {
  const session = state.session;
  if (!session) return;
  state.modal = 'mastering';

  if (!session.mastering) session.mastering = model.defaultMastering();
  const chain = session.mastering;
  const target = model.loudnessTarget(chain.target);
  const eqOff = chain.bypassed || chain.eq.bypassed;
  const compOff = chain.bypassed || chain.compressor.bypassed;
  const limiterOff = chain.bypassed || chain.limiter.bypassed;

  const targetButtons = model.LOUDNESS_TARGETS.map((item) => `
      <button class="mastering-target ${chain.target === item.id ? 'on' : ''}" data-target="${item.id}">
        <strong>${item.name}</strong>
        <span>${item.loudness} LUFS</span>
      </button>`).join('');

  const control = (key, label, min, max, step) => {
    const [group, field] = key.split('.');
    const value = chain[group][field];
    return `<div class="field">
        <div class="label-row"><span>${label}</span><span data-master-value="${key}">${formatMasterValue(key, value)}</span></div>
        <input type="range" min="${min}" max="${max}" step="${step}" value="${value}" data-master="${key}">
      </div>`;
  };

  openModal(`
    <header class="modal-header">
      <div style="flex:1;min-width:0">
        <h2>Mastering</h2>
        <div class="sub">${escapeHtml(session.name.toUpperCase())} · MASTER CHAIN</div>
      </div>
      <button class="modal-close" data-close>Done</button>
    </header>
    <div class="modal-body">
      <div class="panel">
        <div class="switch-row">
          <div>
            <h3 style="margin:0 0 4px">MASTER CHAIN</h3>
            <span class="range-label">${chain.bypassed ? 'Bypassed · EQ, compressor and limiter are off' : 'EQ · bus compressor · limiter'}</span>
          </div>
          <button class="switch ${chain.bypassed ? '' : 'on'}" id="masteringBypass" aria-label="Toggle master chain"></button>
        </div>
      </div>

      <div class="panel">
        <h3>TARGET</h3>
        <div class="mastering-targets">${targetButtons}</div>
        <p class="range-label" style="margin:8px 0 0">${target.name} · ${target.loudness} LUFS · ${target.truePeak} dBTP · ${target.detail}</p>
      </div>

      <div class="panel">
        <div class="label-row" style="margin-bottom:8px">
          <h3 style="margin:0">LOUDNESS</h3>
          <button class="pill" id="masteringReset">RESET</button>
        </div>
        <div class="loudness-grid">
          <div class="loudness-cell">
            <span class="loudness-title">INTEGRATED</span>
            <strong class="loudness-value" data-loudness="integrated">—</strong>
            <span class="loudness-unit">LUFS</span>
            <div class="loudness-bar"><div class="loudness-fill" data-loudness-bar="integrated"></div></div>
          </div>
          <div class="loudness-cell">
            <span class="loudness-title">SHORT-TERM</span>
            <strong class="loudness-value" data-loudness="shortTerm">—</strong>
            <span class="loudness-unit">LUFS</span>
            <div class="loudness-bar"><div class="loudness-fill" data-loudness-bar="shortTerm"></div></div>
          </div>
          <div class="loudness-cell">
            <span class="loudness-title">TRUE PEAK</span>
            <strong class="loudness-value" data-loudness="truePeak">—</strong>
            <span class="loudness-unit">dBTP</span>
            <div class="loudness-bar"><div class="loudness-fill" data-loudness-bar="truePeak"></div></div>
          </div>
        </div>
      </div>

      <div class="panel">
        <div class="label-row">
          <h3 style="margin:0">MASTER EQ</h3>
          <button class="mini ${eqOff ? '' : 'on'}" data-master-bypass="eq">${eqOff ? 'BYP' : 'ON'}</button>
        </div>
        ${control('eq.lowGain', 'Low', -12, 12, 0.5)}
        ${control('eq.midFrequency', 'Mid frequency', 200, 6000, 10)}
        ${control('eq.midGain', 'Mid gain', -12, 12, 0.5)}
        ${control('eq.highGain', 'High', -12, 12, 0.5)}
      </div>

      <div class="panel">
        <div class="label-row">
          <h3 style="margin:0">BUS COMPRESSOR</h3>
          <button class="mini ${compOff ? '' : 'on'}" data-master-bypass="compressor">${compOff ? 'BYP' : 'ON'}</button>
        </div>
        <div class="field">
          <div class="label-row"><span>Threshold</span><span data-master-value="compressor.threshold">${formatMasterValue('compressor.threshold', chain.compressor.threshold)}</span></div>
          <input type="range" min="-40" max="0" step="0.5" value="${chain.compressor.threshold}" data-master="compressor.threshold">
        </div>
        <div class="field">
          <div class="label-row"><span>Ratio</span><span data-master-value="compressor.ratio">${formatMasterValue('compressor.ratio', chain.compressor.ratio)}</span></div>
          <input type="range" min="1" max="8" step="0.1" value="${chain.compressor.ratio}" data-master="compressor.ratio">
        </div>
        ${control('compressor.attack', 'Attack', 0.001, 0.1, 0.001)}
        ${control('compressor.release', 'Release', 0.05, 1, 0.01)}
      </div>

      <div class="panel">
        <div class="label-row">
          <h3 style="margin:0">LIMITER</h3>
          <button class="mini ${limiterOff ? '' : 'on'}" data-master-bypass="limiter">${limiterOff ? 'BYP' : 'ON'}</button>
        </div>
        ${control('limiter.drive', 'Drive', -12, 12, 0.5)}
        ${control('limiter.ceiling', 'Ceiling', -6, 0, 0.1)}
        ${control('limiter.release', 'Release', 0.02, 0.5, 0.01)}
      </div>

      <p class="range-label" style="text-align:center">Applied to playback, the mix bounce and stems.</p>
    </div>`, { tall: true });

  document.getElementById('masteringBypass').addEventListener('click', () => {
    snapshot();
    chain.bypassed = !chain.bypassed;
    engine.applyMastering();
    persist();
    openMastering();
  });

  el.modalRoot.querySelectorAll('[data-target]').forEach((button) => {
    button.addEventListener('click', () => {
      snapshot();
      chain.target = button.dataset.target;
      chain.limiter.ceiling = model.loudnessTarget(chain.target).truePeak;
      engine.applyMastering();
      persist();
      openMastering();
    });
  });

  el.modalRoot.querySelectorAll('[data-master]').forEach((input) => {
    input.addEventListener('input', () => {
      const [group, field] = input.dataset.master.split('.');
      const value = Number(input.value);
      chain[group][field] = value;
      const label = el.modalRoot.querySelector(`[data-master-value="${input.dataset.master}"]`);
      if (label) label.textContent = formatMasterValue(input.dataset.master, value);
      engine.applyMastering();
      persist();
    });
  });

  el.modalRoot.querySelectorAll('[data-master-bypass]').forEach((button) => {
    button.addEventListener('click', () => {
      snapshot();
      const group = button.dataset.masterBypass;
      chain[group].bypassed = !chain[group].bypassed;
      engine.applyMastering();
      persist();
      openMastering();
    });
  });

  document.getElementById('masteringReset').addEventListener('click', () => {
    engine.resetLoudness();
    updateMasteringMeters();
  });

  updateMasteringMeters();
}

// ---------- Session backup and import ----------

function sessionFileIds(session) {
  const ids = new Set();
  for (const track of session.tracks || []) {
    for (const clip of track.clips || []) {
      if (clip.fileId) ids.add(clip.fileId);
    }
    for (const take of track.takes || []) {
      if (take.fileId) ids.add(take.fileId);
    }
    if (track.frozen?.fileId) ids.add(track.frozen.fileId);
  }
  return [...ids];
}

function blobToBase64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(',')[1] || '');
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });
}

function base64ToBlob(base64, type) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return new Blob([bytes], { type: type || 'audio/wav' });
}

function showTransfer(label) {
  if (!el.transferOverlay) return;
  if (el.transferLabel) el.transferLabel.textContent = label;
  if (el.transferFill) el.transferFill.style.width = '0%';
  el.transferOverlay.hidden = false;
}

function updateTransfer(fraction) {
  if (!el.transferFill) return;
  const value = Math.max(0, Math.min(1, fraction));
  el.transferFill.style.width = `${Math.round(value * 100)}%`;
}

function hideTransfer() {
  if (el.transferOverlay) el.transferOverlay.hidden = true;
}

function safeSessionFileName(name) {
  const cleaned = String(name || 'Session')
    .replace(/[^a-z0-9-_]+/gi, '-')
    .replace(/^-+|-+$/g, '');
  return cleaned || 'Session';
}

async function exportSessionBundle(sessionId) {
  const session = state.store.sessions.find((item) => item.id === sessionId);
  if (!session) return;
  if (state.transferBusy) {
    toast('Wait for the current transfer to finish');
    return;
  }
  state.transferBusy = true;
  showTransfer('Packing session…');

  try {
    const ids = sessionFileIds(session);
    const files = [];
    for (let index = 0; index < ids.length; index += 1) {
      const id = ids[index];
      const entry = await model.loadFile(id);
      if (!entry || !entry.blob) continue;
      files.push({
        id,
        name: entry.name || `audio-${index}.wav`,
        type: entry.blob.type || 'audio/wav',
        data: await blobToBase64(entry.blob)
      });
      updateTransfer((index + 1) / Math.max(1, ids.length));
      await new Promise((resolve) => setTimeout(resolve, 0));
    }

    const payload = {
      format: 'ai-studio-session',
      version: 1,
      exportedAt: Date.now(),
      session: JSON.parse(JSON.stringify(session)),
      files
    };
    const blob = new Blob([JSON.stringify(payload)], { type: 'application/json' });
    download(blob, `${safeSessionFileName(session.name)}.aimsession`);
    toast(`Session backup downloaded (${files.length} audio ${files.length === 1 ? 'file' : 'files'})`);
  } catch (error) {
    console.warn('Could not export the session', error);
    toast('Could not pack this session');
  } finally {
    state.transferBusy = false;
    hideTransfer();
  }
}

async function importSessionBundle(file) {
  if (!file) return;
  if (state.transferBusy) {
    toast('Wait for the current transfer to finish');
    return;
  }
  state.transferBusy = true;
  showTransfer('Reading backup…');

  try {
    const payload = JSON.parse(await file.text());
    if (!payload || payload.format !== 'ai-studio-session' || !payload.session) {
      throw new Error('Not a session backup');
    }

    const imported = model.normalizeSession(JSON.parse(JSON.stringify(payload.session)));
    const existing = state.store.sessions.find(
      (item) => item.name.toLowerCase() === imported.name.toLowerCase()
    );
    let replaceExisting = false;
    if (existing) {
      replaceExisting = window.confirm(
        `A session called “${imported.name}” already exists. Press OK to replace it, or Cancel to import it as a copy.`
      );
      if (!replaceExisting) imported.name = uniqueSessionName(imported.name);
    }

    const files = Array.isArray(payload.files) ? payload.files : [];
    const mapping = new Map();
    showTransfer('Unpacking audio…');
    for (let index = 0; index < files.length; index += 1) {
      const entry = files[index];
      if (entry && entry.id && entry.data) {
        const blob = base64ToBlob(entry.data, entry.type || 'audio/wav');
        const newId = await model.saveFile(blob, entry.name || `audio-${index}.wav`);
        mapping.set(entry.id, newId);
      }
      updateTransfer((index + 1) / Math.max(1, files.length));
      await new Promise((resolve) => setTimeout(resolve, 0));
    }

    for (const track of imported.tracks) {
      for (const clip of track.clips) {
        if (clip.fileId && mapping.has(clip.fileId)) clip.fileId = mapping.get(clip.fileId);
      }
      for (const take of track.takes || []) {
        if (take.fileId && mapping.has(take.fileId)) take.fileId = mapping.get(take.fileId);
      }
      if (track.frozen?.fileId && mapping.has(track.frozen.fileId)) {
        track.frozen.fileId = mapping.get(track.frozen.fileId);
      }
    }

    if (replaceExisting && existing) {
      state.store.sessions = state.store.sessions.filter((item) => item.id !== existing.id);
      void model.removeVersionsForSession(existing.id);
    }

    imported.id = model.uid();
    imported.editedAt = Date.now();
    state.store.sessions.push(imported);
    state.store.activeId = imported.id;
    model.saveStore(state.store);
    closeModal();
    adoptSession(imported);
    toast('Session imported');
  } catch (error) {
    console.warn('Could not import the session', error);
    toast('That file is not a readable session backup');
  } finally {
    state.transferBusy = false;
    hideTransfer();
  }
}

// ---------- Channel presets ----------

const PRESET_KEY = 'ai-studio.web.presets.v1';

function loadPresets() {
  try {
    const raw = localStorage.getItem(PRESET_KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) return parsed;
    }
  } catch (error) {
    console.warn('Could not read presets', error);
  }
  return [];
}

function savePresets() {
  try {
    localStorage.setItem(PRESET_KEY, JSON.stringify(state.presets));
  } catch (error) {
    console.warn('Could not save presets', error);
  }
}

function presetSummary(preset) {
  const compression = preset.comp?.bypassed === false ? 'COMP' : 'NO COMP';
  return `FROM ${String(preset.source || '').toUpperCase()} · 3 BANDS · ${compression}`;
}

function openChannelPresets() {
  const session = state.session;
  if (!session) return;
  state.modal = 'presets';
  let selectedPreset = null;
  let sourceTrackId = session.tracks[0]?.id ?? null;
  let targetTrackId = session.tracks.find((track) => track.id !== sourceTrackId)?.id
    ?? session.tracks[0]?.id
    ?? null;

  const trackOptions = (selected) => session.tracks.map((track) => (
    `<option value="${track.id}" ${track.id === selected ? 'selected' : ''}>${escapeHtml(track.name)}</option>`
  )).join('');

  const presetRows = state.presets.map((preset) => `
    <div class="list-row" data-preset-row="${preset.id}" style="cursor:pointer">
      <div class="icon">❐</div>
      <div class="meta">
        <strong>${escapeHtml(preset.name)}</strong>
        <span>${escapeHtml(presetSummary(preset))}</span>
      </div>
      <button class="icon-btn" data-preset-rename="${preset.id}" title="Rename">✎</button>
      <button class="icon-btn" data-preset-delete="${preset.id}" title="Delete">🗑</button>
    </div>`).join('');

  openModal(`
    <header class="modal-header">
      <div style="flex:1;min-width:0">
        <h2>Channel Presets</h2>
        <div class="sub">SAVED EQ, COMPRESSOR, PAN AND LEVEL</div>
      </div>
      <button class="modal-close" data-close>Done</button>
    </header>
    <div class="modal-body">
      <div class="panel">
        <h3>SAVE THIS CHANNEL</h3>
        <div class="field">
          <div class="label-row"><span>Source track</span></div>
          <select id="presetSource" style="height:34px;border-radius:8px;border:1px solid var(--line);background:var(--panel-highlight);color:var(--text);padding:0 8px;font-family:'SF Mono',ui-monospace,monospace;font-size:11px">
            ${trackOptions(sourceTrackId)}
          </select>
        </div>
        <button class="tool primary" id="presetSaveBtn" style="width:100%">Save Preset</button>
      </div>
      <div class="panel">
        <h3>LIBRARY</h3>
        ${state.presets.length ? `<div class="list">${presetRows}</div>` : '<p class="range-label">No presets yet. Save a channel above to reuse its EQ, compressor, pan and level.</p>'}
      </div>
      <div class="panel">
        <h3>APPLY TO</h3>
        <div class="field">
          <select id="presetTarget" style="height:34px;border-radius:8px;border:1px solid var(--line);background:var(--panel-highlight);color:var(--text);padding:0 8px;font-family:'SF Mono',ui-monospace,monospace;font-size:11px">
            ${trackOptions(targetTrackId)}
          </select>
        </div>
        <button class="tool" id="presetApplyBtn" style="width:100%;background:var(--accent);color:#151515">Apply Preset</button>
        <p class="range-label" id="presetStatus" style="margin:8px 0 0">Select a preset in the library first.</p>
      </div>
    </div>`, { tall: true });

  const sourceSelect = document.getElementById('presetSource');
  const targetSelect = document.getElementById('presetTarget');
  const status = document.getElementById('presetStatus');

  if (sourceSelect) {
    sourceSelect.addEventListener('change', () => {
      sourceTrackId = sourceSelect.value;
    });
  }
  if (targetSelect) {
    targetSelect.addEventListener('change', () => {
      targetTrackId = targetSelect.value;
    });
  }

  const saveBtn = document.getElementById('presetSaveBtn');
  if (saveBtn) {
    saveBtn.addEventListener('click', () => {
      const track = session.tracks.find((item) => item.id === sourceTrackId);
      if (!track) return;
      const entered = window.prompt('Preset name', `${track.name} Preset`);
      if (entered === null) return;
      const preset = {
        id: model.uid(),
        name: entered.trim() || `${track.name} Preset`,
        source: track.name,
        volume: track.volume,
        pan: track.pan,
        eq: JSON.parse(JSON.stringify(track.eq)),
        comp: JSON.parse(JSON.stringify(track.comp)),
        createdAt: Date.now()
      };
      state.presets.unshift(preset);
      savePresets();
      selectedPreset = preset.id;
      openChannelPresets();
      toast(`Preset "${preset.name}" saved`);
    });
  }

  el.modalRoot.querySelectorAll('[data-preset-row]').forEach((row) => {
    row.addEventListener('click', (event) => {
      if (event.target.closest('button')) return;
      selectedPreset = row.dataset.presetRow;
      el.modalRoot.querySelectorAll('[data-preset-row]').forEach((item) => {
        item.classList.toggle('open', item === row);
      });
      if (status) {
        const preset = state.presets.find((item) => item.id === selectedPreset);
        status.textContent = preset ? `Selected "${preset.name}"` : 'Select a preset in the library first.';
      }
    });
  });

  el.modalRoot.querySelectorAll('[data-preset-rename]').forEach((button) => {
    button.addEventListener('click', () => {
      const preset = state.presets.find((item) => item.id === button.dataset.presetRename);
      if (!preset) return;
      const entered = window.prompt('Preset name', preset.name);
      if (entered === null) return;
      const name = entered.trim();
      if (!name) return;
      preset.name = name;
      savePresets();
      openChannelPresets();
    });
  });

  el.modalRoot.querySelectorAll('[data-preset-delete]').forEach((button) => {
    button.addEventListener('click', () => {
      const preset = state.presets.find((item) => item.id === button.dataset.presetDelete);
      if (!preset) return;
      if (!window.confirm(`Delete preset "${preset.name}"?`)) return;
      state.presets = state.presets.filter((item) => item.id !== preset.id);
      savePresets();
      openChannelPresets();
    });
  });

  const applyBtn = document.getElementById('presetApplyBtn');
  if (applyBtn) {
    applyBtn.addEventListener('click', () => {
      const preset = state.presets.find((item) => item.id === selectedPreset);
      const track = session.tracks.find((item) => item.id === targetTrackId);
      if (!preset || !track) {
        if (status) status.textContent = 'Select a preset and a track first.';
        return;
      }
      snapshot();
      track.volume = model.clamp(preset.volume ?? 1, 0, 1);
      track.pan = model.clamp(preset.pan ?? 0, -1, 1);
      track.eq = JSON.parse(JSON.stringify(preset.eq || track.eq));
      track.comp = JSON.parse(JSON.stringify(preset.comp || track.comp));
      const nodes = engine.trackNodes.get(track.id);
      if (nodes) engine.applyTrackSettings(track, nodes);
      persist();
      render();
      if (status) status.textContent = `Applied to ${track.name}`;
      toast(`Applied "${preset.name}" to ${track.name}`);
    });
  }
}

// ---------- Instruments ----------

function instrumentEngineInstance() {
  engine.ensureContext();
  if (!instrumentVoice || instrumentVoice.ctx !== engine.ctx) {
    instrumentVoice = new InstrumentEngine(engine.ctx);
  }
  return instrumentVoice;
}

function instrumentDestination() {
  const context = engine.ensureContext();
  if (!state.instrumentBus || state.instrumentBusContext !== context) {
    state.instrumentBus = context.createGain();
    state.instrumentBusContext = context;
    state.instrumentBusTarget = null;
  }

  const nodes = state.instrumentTrackId ? engine.trackNodes.get(state.instrumentTrackId) : null;
  const target = nodes ? nodes.input : engine.masterGain;
  if (state.instrumentBusTarget !== target) {
    state.instrumentBus.disconnect();
    state.instrumentBus.connect(target);
    if (state.instrumentRecordDestination) state.instrumentBus.connect(state.instrumentRecordDestination);
    state.instrumentBusTarget = target;
  }
  return state.instrumentBus;
}

function instrumentRecordingMimeType() {
  const Recorder = window.MediaRecorder;
  if (!Recorder) return null;
  if (typeof Recorder.isTypeSupported !== 'function') return '';
  return ['audio/mp4', 'audio/webm;codecs=opus', 'audio/webm']
    .find((type) => Recorder.isTypeSupported(type)) || '';
}

function startInstrumentRecording() {
  const track = trackById(state.instrumentTrackId);
  if (!track) {
    toast('Choose a session track as the recording destination');
    return;
  }
  if (state.instrumentTab === 'sampler' && !state.samplerBuffer) {
    toast('Load a sample before recording');
    return;
  }

  const Recorder = window.MediaRecorder;
  if (!Recorder) {
    toast('Instrument recording is not supported in this browser');
    return;
  }

  const mimeType = instrumentRecordingMimeType();
  const context = engine.ensureContext();
  const bus = instrumentDestination();
  const capture = context.createMediaStreamDestination();
  bus.connect(capture);

  let recorder;
  try {
    recorder = mimeType ? new Recorder(capture.stream, { mimeType }) : new Recorder(capture.stream);
  } catch (error) {
    bus.disconnect(capture);
    capture.stream.getTracks().forEach((streamTrack) => streamTrack.stop());
    toast('Instrument recording could not start in this browser');
    return;
  }

  const sessionID = state.session.id;
  const trackID = track.id;
  const startPosition = engine.isPlaying ? engine.getPosition() : engine.position;
  const position = engine.duration() > 0 && startPosition >= engine.duration() ? 0 : startPosition;
  const instrumentNames = { synth: 'Synth', drums: 'Drums', tb303: 'TB-303', sampler: state.samplerName || 'Sampler' };
  const takeName = `${instrumentNames[state.instrumentTab] || 'Instrument'} Take`;
  const chunks = [];

  recorder.ondataavailable = (event) => {
    if (event.data?.size) chunks.push(event.data);
  };
  recorder.onerror = (event) => {
    bus.disconnect(capture);
    capture.stream.getTracks().forEach((streamTrack) => streamTrack.stop());
    clearInterval(state.instrumentRecordTimer);
    state.instrumentRecordTimer = null;
    state.instrumentRecording = false;
    state.instrumentRecorder = null;
    state.instrumentRecordDestination = null;
    toast(event.error?.message || 'Instrument recording failed');
    if (state.modal === 'instruments') openInstruments();
  };
  recorder.onstop = async () => {
    bus.disconnect(capture);
    capture.stream.getTracks().forEach((streamTrack) => streamTrack.stop());
    state.instrumentRecorder = null;
    state.instrumentRecordDestination = null;
    state.instrumentRecording = false;
    clearInterval(state.instrumentRecordTimer);
    state.instrumentRecordTimer = null;
    if (state.modal === 'instruments') openInstruments();

    const type = recorder.mimeType || mimeType || 'audio/webm';
    const blob = new Blob(chunks, { type });
    if (!blob.size) {
      toast('No instrument audio was captured');
      return;
    }

    try {
      const buffer = await engine.decode(await blob.arrayBuffer());
      const peaks = computePeaks(buffer);
      if (!hasAudibleContent(buffer)) {
        toast('Play an instrument before stopping the take');
        return;
      }
      const session = state.store.sessions.find((item) => item.id === sessionID);
      const destinationTrack = session?.tracks.find((item) => item.id === trackID);
      if (!session || !destinationTrack) {
        toast('The recording destination is no longer available');
        return;
      }

      if (state.session.id === sessionID) snapshot();
      const extension = type.includes('mp4') ? 'm4a' : 'webm';
      const fileName = `${safeName(takeName)}-${Date.now()}.${extension}`;
      let recordedName = 'Take';
      const punched = await applyPunchRecording(destinationTrack, buffer, position, takeName);
      if (punched) {
        recordedName = punched.name;
      } else {
        const fileId = await model.saveFile(blob, fileName);
        const take = registerTake(destinationTrack, {
          name: takeName,
          fileId,
          start: position,
          duration: buffer.duration
        });
        state.buffers.set(fileId, buffer);
        engine.buffers.set(fileId, buffer);
        state.peaks.set(fileId, peaks);
        recordedName = take.name;
      }
      session.editedAt = Date.now();
      model.saveStore(state.store);
      if (state.session.id === sessionID) {
        persist();
        engine.rebuild();
        render();
      }
      toast(`Recorded ${recordedName} at ${model.formatTime(position)}`);
    } catch (error) {
      toast(error.message || 'The instrument take could not be added to the session');
    }
  };

  const startedAt = Date.now();
  state.instrumentRecorder = recorder;
  state.instrumentRecordDestination = capture;
  state.instrumentRecordChunks = chunks;
  state.instrumentRecordTrackId = trackID;
  state.instrumentRecordStartTime = position;
  state.instrumentRecordStartWall = startedAt;
  state.instrumentRecordTakeName = takeName;
  state.instrumentRecordDuration = 0;

  try {
    recorder.start();
  } catch (error) {
    bus.disconnect(capture);
    capture.stream.getTracks().forEach((streamTrack) => streamTrack.stop());
    state.instrumentRecorder = null;
    state.instrumentRecordDestination = null;
    toast('Instrument recording could not start');
    return;
  }

  state.instrumentRecording = true;
  if (!engine.isPlaying) engine.play(position);
  state.instrumentRecordTimer = setInterval(() => {
    state.instrumentRecordDuration = Math.max(0, (Date.now() - startedAt) / 1000);
    const time = document.getElementById('instrumentRecordTime');
    if (time) time.textContent = model.formatTime(state.instrumentRecordDuration);
  }, 100);
  openInstruments();
  toast(`Recording to ${track.name}`);
}

function stopInstrumentRecording(refresh = true) {
  if (!state.instrumentRecording || !state.instrumentRecorder) return;
  state.instrumentRecording = false;
  state.instrumentRecordDuration = Math.max(0, (Date.now() - state.instrumentRecordStartWall) / 1000);
  clearInterval(state.instrumentRecordTimer);
  state.instrumentRecordTimer = null;
  try {
    if (state.instrumentRecorder.state === 'recording') state.instrumentRecorder.stop();
  } catch (error) {
    toast('Instrument recording could not be stopped cleanly');
  }
  if (refresh && state.modal === 'instruments') openInstruments();
}

async function startMicrophoneRecording() {
  if (state.microphoneRecording || state.microphoneFinalizing || state.microphoneRequesting || state.microphoneRecorder) return;

  const track = trackById(state.instrumentTrackId);
  if (!track) {
    toast('Choose a session track as the microphone destination');
    return;
  }
  if (state.instrumentRecording) {
    toast('Stop the instrument take before recording the microphone');
    return;
  }

  const mediaDevices = navigator.mediaDevices;
  const Recorder = window.MediaRecorder;
  if (!mediaDevices || typeof mediaDevices.getUserMedia !== 'function' || !Recorder) {
    toast('Microphone recording requires a supported browser over HTTPS');
    return;
  }

  const sessionID = state.session.id;
  const trackID = track.id;
  const requestID = state.microphoneRequestID + 1;
  state.microphoneRequestID = requestID;
  state.microphoneRequesting = true;
  if (state.modal === 'instruments') openInstruments();

  let stream;
  try {
    stream = await mediaDevices.getUserMedia({ audio: true, video: false });
  } catch (error) {
    if (requestID !== state.microphoneRequestID) return;
    state.microphoneRequesting = false;
    if (state.modal === 'instruments') openInstruments();
    const denied = error?.name === 'NotAllowedError' || error?.name === 'PermissionDeniedError' || error?.name === 'SecurityError';
    toast(denied ? 'Microphone access was denied. Allow it in your browser settings to record.' : 'Could not access a microphone');
    return;
  }

  if (requestID !== state.microphoneRequestID) {
    stream.getTracks().forEach((mediaTrack) => mediaTrack.stop());
    return;
  }
  state.microphoneRequesting = false;

  const session = state.store.sessions.find((item) => item.id === sessionID);
  const destinationTrack = session?.tracks.find((item) => item.id === trackID);
  if (!session || !destinationTrack || state.session.id !== sessionID) {
    stream.getTracks().forEach((mediaTrack) => mediaTrack.stop());
    if (state.modal === 'instruments') openInstruments();
    toast('The microphone destination is no longer available');
    return;
  }
  if (!stream.getAudioTracks().length) {
    stream.getTracks().forEach((mediaTrack) => mediaTrack.stop());
    if (state.modal === 'instruments') openInstruments();
    toast('No microphone input is available');
    return;
  }

  const mimeType = instrumentRecordingMimeType();
  let recorder;
  try {
    recorder = mimeType ? new Recorder(stream, { mimeType }) : new Recorder(stream);
  } catch (error) {
    stream.getTracks().forEach((mediaTrack) => mediaTrack.stop());
    if (state.modal === 'instruments') openInstruments();
    toast('Microphone recording could not start in this browser');
    return;
  }

  const startPosition = engine.isPlaying ? engine.getPosition() : engine.position;
  const position = engine.duration() > 0 && startPosition >= engine.duration() ? 0 : Math.max(0, startPosition);
  const chunks = [];
  let recordingFailed = false;
  const releaseStream = () => {
    stream.getTracks().forEach((mediaTrack) => mediaTrack.stop());
    if (state.microphoneStream === stream) state.microphoneStream = null;
  };

  recorder.ondataavailable = (event) => {
    if (event.data?.size) chunks.push(event.data);
  };
  const finishMicrophoneFinalization = () => {
    if (state.microphoneRecorder !== recorder) return;
    state.microphoneRecorder = null;
    state.microphoneFinalizing = false;
    if (state.modal === 'instruments') openInstruments();
  };
  recorder.onerror = (event) => {
    recordingFailed = true;
    releaseStream();
    clearInterval(state.microphoneRecordTimer);
    state.microphoneRecordTimer = null;
    if (state.microphoneRecorder === recorder) {
      state.microphoneRecording = false;
      state.microphoneFinalizing = true;
    }
    if (state.modal === 'instruments') openInstruments();
    toast(event.error?.message || 'Microphone recording failed');
  };
  recorder.onstop = async () => {
    releaseStream();
    if (state.microphoneRecorder === recorder) {
      state.microphoneRecording = false;
      state.microphoneFinalizing = true;
      state.microphoneRecordDuration = Math.max(0, (Date.now() - state.microphoneRecordStartWall) / 1000);
      clearInterval(state.microphoneRecordTimer);
      state.microphoneRecordTimer = null;
      if (state.modal === 'instruments') openInstruments();
    }
    if (recordingFailed) {
      finishMicrophoneFinalization();
      return;
    }

    const type = recorder.mimeType || mimeType || 'audio/webm';
    const blob = new Blob(chunks, { type });
    if (!blob.size) {
      finishMicrophoneFinalization();
      toast('No microphone audio was captured');
      return;
    }

    try {
      const buffer = await engine.decode(await blob.arrayBuffer());
      const currentSession = state.store.sessions.find((item) => item.id === sessionID);
      const currentTrack = currentSession?.tracks.find((item) => item.id === trackID);
      if (!currentSession || !currentTrack) {
        toast('The microphone destination is no longer available');
        return;
      }

      const extension = type.includes('mp4') ? 'm4a' : type.includes('ogg') ? 'ogg' : 'webm';
      const fileName = `Microphone-Take-${Date.now()}.${extension}`;
      const takeName = 'Microphone Take';
      if (state.session.id === sessionID) snapshot();
      let recordedName = 'Take';
      const punched = await applyPunchRecording(currentTrack, buffer, position, takeName);
      if (punched) {
        recordedName = punched.name;
      } else {
        const fileId = await model.saveFile(blob, fileName);
        const take = registerTake(currentTrack, {
          name: takeName,
          fileId,
          start: position,
          duration: buffer.duration
        });
        state.buffers.set(fileId, buffer);
        engine.buffers.set(fileId, buffer);
        state.peaks.set(fileId, computePeaks(buffer));
        recordedName = take.name;
      }
      currentSession.editedAt = Date.now();
      model.saveStore(state.store);
      if (state.session.id === sessionID) {
        persist();
        engine.rebuild();
        render();
      }
      toast(`Recorded ${recordedName} at ${model.formatTime(position)}`);
    } catch (error) {
      toast(error.message || 'The microphone take could not be added to the session');
    } finally {
      finishMicrophoneFinalization();
    }
  };

  const startedAt = Date.now();
  state.microphoneRecorder = recorder;
  state.microphoneStream = stream;
  state.microphoneRecordDuration = 0;
  state.microphoneRecordStartWall = startedAt;
  try {
    recorder.start();
  } catch (error) {
    releaseStream();
    state.microphoneRecorder = null;
    if (state.modal === 'instruments') openInstruments();
    toast('Microphone recording could not start');
    return;
  }

  state.microphoneRecording = true;
  if (!engine.isPlaying) engine.play(position);
  state.microphoneRecordTimer = setInterval(() => {
    state.microphoneRecordDuration = Math.max(0, (Date.now() - startedAt) / 1000);
    const time = document.getElementById('microphoneRecordTime');
    if (time) time.textContent = model.formatTime(state.microphoneRecordDuration);
  }, 100);
  if (state.modal === 'instruments') openInstruments();
  toast(`Recording microphone to ${destinationTrack.name}`);
}

function stopMicrophoneRecording(refresh = true) {
  if (!state.microphoneRecording || !state.microphoneRecorder) return;
  state.microphoneRecording = false;
  state.microphoneFinalizing = true;
  state.microphoneRecordDuration = Math.max(0, (Date.now() - state.microphoneRecordStartWall) / 1000);
  clearInterval(state.microphoneRecordTimer);
  state.microphoneRecordTimer = null;
  try {
    if (state.microphoneRecorder.state === 'recording') state.microphoneRecorder.stop();
  } catch (error) {
    toast('Microphone recording could not be stopped cleanly');
  }
  if (refresh && state.modal === 'instruments') openInstruments();
}

function instrumentValueLabel(key) {
  switch (key) {
    case 'synthCutoff': return `${Math.round(state.synthCutoff)} Hz`;
    case 'synthAttack': return `${Math.round(state.synthAttack * 1000)} ms`;
    case 'synthRelease': return `${Math.round(state.synthRelease * 1000)} ms`;
    case 'tb303Cutoff': return `${Math.round(state.tb303Cutoff)} Hz`;
    case 'tb303Resonance': return `${Math.round(state.tb303Resonance * 100)}%`;
    case 'tb303Envelope': return `${Math.round(state.tb303Envelope * 100)}%`;
    case 'tb303Decay': return `${Math.round(state.tb303Decay * 1000)} ms`;
    case 'tb303Tuning': return `${Number(state.tb303Tuning).toFixed(2)}×`;
    case 'tb303Level': return `${Math.round(state.tb303Level * 100)}%`;
    case 'drumVolume': return `${Math.round(state.drumVolume * 100)}%`;
    case 'drumTuning': return `${Number(state.drumTuning).toFixed(2)}×`;
    case 'drumDecay': return `${Math.round(state.drumDecay * 100)}%`;
    case 'drumTone': return `${Math.round(state.drumTone * 100)}%`;
    default: return '';
  }
}

function instrumentSliderField(title, key, min, max, step) {
  return `<div class="field">
    <div class="label-row"><span>${title}</span><span data-instrument-value="${key}">${instrumentValueLabel(key)}</span></div>
    <input type="range" min="${min}" max="${max}" step="${step}" value="${state[key]}" data-instrument-slider="${key}">
  </div>`;
}

function instrumentKnobField(title, key, min, max, step) {
  const progress = model.clamp((state[key] - min) / (max - min), 0, 1);
  const angle = -135 + progress * 270;
  return `<div class="hardware-knob" data-hardware-knob="${key}">
    <div class="knob-face" data-knob-face="${key}" style="--knob-angle:${angle}deg"><span class="knob-marker"></span><span class="knob-hub"></span></div>
    <span class="knob-label">${title}</span>
    <span class="knob-value" data-instrument-value="${key}">${instrumentValueLabel(key)}</span>
    <input class="knob-accessibility-input" type="range" min="${min}" max="${max}" step="${step}" value="${state[key]}" data-instrument-slider="${key}" aria-label="${title}">
  </div>`;
}

function instrumentNoteButtons(from, to, attribute) {
  const notes = [];
  for (let pitch = from; pitch <= to; pitch += 1) {
    const black = model.isBlackKey(pitch);
    notes.push(`<button class="key ${black ? 'black' : ''}" data-${attribute}="${pitch}">${model.noteName(pitch)}</button>`);
  }
  return notes.join('');
}

function drumSequencerMarkup() {
  const stepCount = 16;
  const stepNumbers = Array.from({ length: stepCount }, (_, step) => (
    `<span class="drum-step-number ${step % 4 === 0 ? 'downbeat' : ''}">${String(step + 1).padStart(2, '0')}</span>`
  )).join('');
  const rows = DRUM_PADS.map((pad) => {
    const activeSteps = state.session.drumPattern[pad.id] || [];
    const cells = Array.from({ length: stepCount }, (_, step) => {
      const isActive = Boolean(activeSteps[step]);
      return `<button type="button" class="drum-step ${isActive ? 'active' : ''} ${step % 4 === 0 ? 'downbeat' : ''}" data-drum-step-voice="${pad.id}" data-drum-step-index="${step}" aria-pressed="${isActive}" aria-label="${pad.name}, step ${step + 1}, ${isActive ? 'on' : 'off'}"></button>`;
    }).join('');
    return `<div class="drum-step-row">
      <span class="drum-voice-label">${pad.name}</span>
      <div class="drum-step-cells">${cells}</div>
    </div>`;
  }).join('');

  return `<div class="drum-sequencer-section">
    <div class="drum-sequencer-title"><h4>16-STEP SEQUENCER</h4><span>SESSION SYNC</span></div>
    <div class="drum-sequencer-scroll" aria-label="Drum pattern steps">
      <div class="drum-sequencer" data-drum-sequencer data-playhead-step="">
        <div class="drum-step-row drum-step-header">
          <span class="drum-voice-label">VOICE</span>
          <div class="drum-step-cells">${stepNumbers}</div>
        </div>
        ${rows}
      </div>
    </div>
    <p class="drum-sequencer-hint">Tap steps to toggle hits · repeats every bar during transport playback</p>
  </div>`;
}

function updateDrumSequencerPlayhead() {
  const sequencer = el.modalRoot.querySelector('[data-drum-sequencer]');
  if (!sequencer) return;

  const stepDuration = 60 / (state.session?.tempo || 120) / 4;
  const step = engine.isPlaying && stepDuration > 0
    ? Math.floor((state.playhead + 1e-6) / stepDuration) % 16
    : null;
  const nextStep = step === null ? '' : String(step);
  if (sequencer.dataset.playheadStep === nextStep) return;

  sequencer.dataset.playheadStep = nextStep;
  sequencer.querySelectorAll('[data-drum-step-index]').forEach((button) => {
    button.classList.toggle('playhead', Number(button.dataset.drumStepIndex) === step);
  });
}

function instrumentTabContent() {
  if (state.instrumentTab === 'drums') {
    return `<div class="panel">
      <h3>808 RHYTHM COMPOSER</h3>
      <div class="hardware-knob-bank drum-knob-bank">
        ${instrumentKnobField('LEVEL', 'drumVolume', 0, 1, 0.01)}
        ${instrumentKnobField('TUNE', 'drumTuning', 0.5, 1.5, 0.01)}
        ${instrumentKnobField('DECAY', 'drumDecay', 0.4, 2, 0.01)}
        ${instrumentKnobField('TONE', 'drumTone', 0, 1, 0.01)}
      </div>
      <div class="pads">
        ${DRUM_PADS.map((pad) => `<button class="pad" data-drum="${pad.id}">${pad.name}</button>`).join('')}
      </div>
      ${drumSequencerMarkup()}
    </div>`;
  }

  if (state.instrumentTab === 'tb303') {
    return `<div class="panel">
      <h3>TB-303 ACID BASS</h3>
      <div class="control-row" style="padding:0 0 10px">
        ${['sawtooth', 'square'].map((wave) => `<button class="pill ${state.tb303Waveform === wave ? 'on' : ''}" data-tb-wave="${wave}">${wave === 'sawtooth' ? 'SAW' : 'SQUARE'}</button>`).join('')}
        <button class="pill ${state.tb303Accent ? 'on' : ''}" data-tb-accent>ACCENT</button>
      </div>
      <div class="hardware-knob-bank tb303-knob-bank">
        ${instrumentKnobField('TUNE', 'tb303Tuning', 0.5, 1.5, 0.01)}
        ${instrumentKnobField('CUTOFF', 'tb303Cutoff', 100, 6000, 10)}
        ${instrumentKnobField('RESONANCE', 'tb303Resonance', 0, 1, 0.01)}
        ${instrumentKnobField('ENV MOD', 'tb303Envelope', 0, 1, 0.01)}
        ${instrumentKnobField('DECAY', 'tb303Decay', 0.16, 1.2, 0.01)}
        ${instrumentKnobField('LEVEL', 'tb303Level', 0, 1, 0.01)}
      </div>
      <div class="keys" style="margin-top:10px">
        ${instrumentNoteButtons(36, 48, 'tb-note')}
      </div>
    </div>`;
  }

  if (state.instrumentTab === 'sampler') {
    const loaded = state.samplerBuffer ? (state.samplerName || 'Sample') : 'Nothing loaded';
    return `<div class="panel">
      <h3>SAMPLER</h3>
      <div class="label-row" style="margin-bottom:8px"><span>Loaded</span><span>${escapeHtml(loaded)}</span></div>
      <input type="file" id="samplerFile" accept="audio/*,.mp3,.wav" hidden>
      <div class="control-row" style="padding:0 0 12px">
        <button class="pill" id="samplerChooseBtn">CHOOSE FILE</button>
        <button class="pill ${state.samplerBuffer ? 'on' : ''}" id="samplerTriggerBtn" ${state.samplerBuffer ? '' : 'disabled'}>TRIGGER</button>
      </div>
      <div class="label-row"><span>Starter sounds</span></div>
      <div style="margin:8px 0 12px">
        ${STARTER_SOUNDS.map((sound) => `<button class="sound-button ${state.samplerSoundId === sound.file ? 'loaded' : ''}" data-sampler-sound="${sound.file}">${sound.name}</button>`).join('')}
      </div>
      ${sessionSoundButtons()}
    </div>`;
  }

  return `<div class="panel">
    <h3>SYNTH</h3>
    <div class="control-row" style="padding:0 0 10px">
      ${['sine', 'triangle', 'sawtooth', 'square'].map((wave) => `<button class="pill ${state.synthWaveform === wave ? 'on' : ''}" data-synth-wave="${wave}">${wave === 'sawtooth' ? 'SAW' : wave.toUpperCase()}</button>`).join('')}
    </div>
    ${instrumentSliderField('Cutoff', 'synthCutoff', 100, 12000, 10)}
    ${instrumentSliderField('Attack', 'synthAttack', 0.005, 1, 0.005)}
    ${instrumentSliderField('Release', 'synthRelease', 0.02, 2, 0.01)}
    <div class="keys" style="margin-top:10px">
      ${instrumentNoteButtons(60, 72, 'synth-note')}
    </div>
  </div>`;
}

function sessionSoundButtons() {
  const seen = new Map();
  for (const track of state.session.tracks) {
    for (const clip of model.playbackClips(track)) {
      if (engine.buffers.has(clip.fileId)) seen.set(clip.fileId, clip.name);
    }
  }
  if (!seen.size) return '';
  const buttons = Array.from(seen.entries()).map(([id, name]) => (
    `<button class="sound-button ${state.samplerSoundId === id ? 'loaded' : ''}" data-sampler-file="${id}">${escapeHtml(name)}</button>`
  )).join('');
  return `<div class="label-row"><span>Session audio</span></div><div style="margin:8px 0 0">${buttons}</div>`;
}

function openInstruments(destinationTrackID = null) {
  if (!state.session) return;
  state.modal = 'instruments';
  if (destinationTrackID && state.session.tracks.some((track) => track.id === destinationTrackID)) {
    state.instrumentTrackId = destinationTrackID;
  }
  if (!state.instrumentTrackId && state.session.tracks.length) {
    state.instrumentTrackId = state.session.tracks[0].id;
  }

  if (!state.session.tracks.some((track) => track.id === state.instrumentTrackId)) {
    state.instrumentTrackId = state.session.tracks[0]?.id ?? null;
  }

  const destinationOptions = [
    `<option value="" ${state.instrumentTrackId ? '' : 'selected'}>Master Output</option>`,
    ...state.session.tracks.map((track) => (
      `<option value="${track.id}" ${track.id === state.instrumentTrackId ? 'selected' : ''}>${escapeHtml(track.name)}</option>`
    ))
  ].join('');

  const tabs = [['synth', 'SYNTH'], ['drums', 'DRUMS'], ['tb303', '303'], ['sampler', 'SAMPLER']]
    .map(([id, label]) => `<button class="pill ${state.instrumentTab === id ? 'on' : ''}" data-instrument-tab="${id}">${label}</button>`)
    .join('');
  const recordTrack = trackById(state.instrumentTrackId);
  const canRecord = Boolean(recordTrack)
    && (state.instrumentTab !== 'sampler' || Boolean(state.samplerBuffer))
    && !state.microphoneRecording
    && !state.microphoneFinalizing
    && !state.microphoneRequesting;
  const punchArmed = Boolean(recordTrack) && isPunchActiveFor(recordTrack.id);
  const canRecordMicrophone = Boolean(recordTrack) && !state.instrumentRecording && !state.microphoneFinalizing;
  const microphoneButtonDisabled = !state.microphoneRecording
    && (state.microphoneRequesting || state.microphoneFinalizing || !canRecordMicrophone);
  const recordStatus = state.instrumentRecording
    ? `CAPTURING TO ${recordTrack?.name || 'TRACK'}`
    : recordTrack ? `ARMED FOR ${recordTrack.name.toUpperCase()}` : 'CHOOSE A TRACK TO RECORD';
  const microphoneStatus = state.microphoneRecording
    ? `CAPTURING TO ${recordTrack?.name || 'TRACK'}`
    : state.microphoneRequesting
      ? 'WAITING FOR MICROPHONE ACCESS'
      : state.microphoneFinalizing
        ? 'ADDING TAKE TO THE SESSION'
        : recordTrack ? `READY FOR ${recordTrack.name.toUpperCase()}` : 'CHOOSE A TRACK TO RECORD';

  openModal(`
    <header class="modal-header">
      <div style="flex:1;min-width:0">
        <h2>Instruments</h2>
        <div class="sub">PLAY THROUGH THE SELECTED TRACK</div>
      </div>
      <button class="modal-close" data-close>Done</button>
    </header>
    <div class="modal-body">
      <div class="field">
        <div class="label-row"><span>Destination</span></div>
        <select id="instrumentDestination" ${state.instrumentRecording || state.microphoneRecording || state.microphoneFinalizing || state.microphoneRequesting ? 'disabled' : ''} style="height:34px;border-radius:8px;border:1px solid var(--line);background:var(--panel-highlight);color:var(--text);padding:0 8px;font-family:'SF Mono',ui-monospace,monospace;font-size:11px">
          ${destinationOptions}
        </select>
      </div>
      <div class="instrument-record-bar ${state.instrumentRecording ? 'recording' : ''}">
        <span class="record-light"></span>
        <div class="instrument-record-meta">
          <strong>${state.instrumentRecording ? 'RECORDING PERFORMANCE' : 'RECORD TO SONG'}</strong>
          <span>${escapeHtml(recordStatus)}</span>
        </div>
        <span class="instrument-record-time" id="instrumentRecordTime">${model.formatTime(state.instrumentRecordDuration)}</span>
        <button class="instrument-record-button ${state.instrumentRecording ? 'recording' : ''}" data-instrument-record ${state.instrumentRecording || canRecord ? '' : 'disabled'}>${state.instrumentRecording ? 'STOP' : punchArmed ? 'PUNCH' : 'REC'}</button>
      </div>
      <p class="instrument-record-hint">${punchArmed ? 'Punch is armed: only the IN–OUT range will be captured.' : 'Play any instrument; your take is placed at the current playhead.'}</p>
      <div class="instrument-record-bar microphone-record-bar ${state.microphoneRecording ? 'recording' : ''}">
        <span class="record-light"></span>
        <div class="instrument-record-meta">
          <strong>${state.microphoneRecording ? 'RECORDING MICROPHONE' : state.microphoneRequesting ? 'REQUESTING MICROPHONE ACCESS' : state.microphoneFinalizing ? 'SAVING MICROPHONE TAKE' : 'RECORD FROM MICROPHONE'}</strong>
          <span>${escapeHtml(microphoneStatus)}</span>
        </div>
        <span class="instrument-record-time" id="microphoneRecordTime">${model.formatTime(state.microphoneRecordDuration)}</span>
        <button class="instrument-record-button ${state.microphoneRecording ? 'recording' : ''}" data-microphone-record ${microphoneButtonDisabled ? 'disabled' : ''}>${state.microphoneRecording ? 'STOP' : state.microphoneRequesting || state.microphoneFinalizing ? 'WAIT' : 'REC'}</button>
      </div>
      <p class="instrument-record-hint microphone-record-hint">Microphone access is requested only after you tap Record. The take starts at the current transport position.</p>
      <div class="control-row" style="padding:0 0 10px">${tabs}</div>
      ${instrumentTabContent()}
    </div>`, { tall: true });

  bindInstrumentControls();
}

function bindInstrumentControls() {
  const destination = document.getElementById('instrumentDestination');
  if (destination) {
    destination.addEventListener('change', () => {
      state.instrumentTrackId = destination.value || null;
    });
  }

  const recordButton = el.modalRoot.querySelector('[data-instrument-record]');
  if (recordButton) {
    recordButton.addEventListener('click', () => {
      if (state.instrumentRecording) stopInstrumentRecording();
      else startInstrumentRecording();
    });
  }

  const microphoneButton = el.modalRoot.querySelector('[data-microphone-record]');
  if (microphoneButton) {
    microphoneButton.addEventListener('click', () => {
      if (state.microphoneRecording) stopMicrophoneRecording();
      else startMicrophoneRecording();
    });
  }

  el.modalRoot.querySelectorAll('[data-instrument-tab]').forEach((button) => {
    button.addEventListener('click', () => {
      state.instrumentTab = button.dataset.instrumentTab;
      openInstruments();
    });
  });

  el.modalRoot.querySelectorAll('[data-synth-wave]').forEach((button) => {
    button.addEventListener('click', () => {
      state.synthWaveform = button.dataset.synthWave;
      openInstruments();
    });
  });

  el.modalRoot.querySelectorAll('[data-tb-wave]').forEach((button) => {
    button.addEventListener('click', () => {
      state.tb303Waveform = button.dataset.tbWave;
      openInstruments();
    });
  });

  el.modalRoot.querySelectorAll('[data-instrument-slider]').forEach((input) => {
    input.addEventListener('input', () => {
      const key = input.dataset.instrumentSlider;
      state[key] = Number(input.value);
      const label = el.modalRoot.querySelector(`[data-instrument-value="${key}"]`);
      if (label) label.textContent = instrumentValueLabel(key);
      const face = el.modalRoot.querySelector(`[data-knob-face="${key}"]`);
      if (face) {
        const minimum = Number(input.min);
        const maximum = Number(input.max);
        const progress = model.clamp((Number(input.value) - minimum) / (maximum - minimum), 0, 1);
        face.style.setProperty('--knob-angle', `${-135 + progress * 270}deg`);
      }
    });
  });

  el.modalRoot.querySelectorAll('[data-hardware-knob]').forEach((knob) => {
    knob.addEventListener('pointerdown', (event) => {
      const input = knob.querySelector('[data-instrument-slider]');
      if (!input || event.target === input) return;
      event.preventDefault();
      const startY = event.clientY;
      const origin = Number(input.value);
      const minimum = Number(input.min);
      const maximum = Number(input.max);
      startDrag((moveEvent) => {
        const change = (startY - moveEvent.clientY) / 125 * (maximum - minimum);
        input.value = String(model.clamp(origin + change, minimum, maximum));
        input.dispatchEvent(new Event('input', { bubbles: true }));
      });
    });
  });

  const accent = el.modalRoot.querySelector('[data-tb-accent]');
  if (accent) {
    accent.addEventListener('click', () => {
      state.tb303Accent = !state.tb303Accent;
      accent.classList.toggle('on', state.tb303Accent);
    });
  }

  el.modalRoot.querySelectorAll('[data-synth-note]').forEach((button) => {
    button.addEventListener('click', () => playSynth(Number(button.dataset.synthNote)));
  });

  el.modalRoot.querySelectorAll('[data-tb-note]').forEach((button) => {
    button.addEventListener('click', () => playTB303(Number(button.dataset.tbNote)));
  });

  el.modalRoot.querySelectorAll('[data-drum-step-voice]').forEach((button) => {
    button.addEventListener('click', () => {
      const voice = button.dataset.drumStepVoice;
      const step = Number(button.dataset.drumStepIndex);
      if (!state.session.drumPattern[voice] || !Number.isInteger(step) || step < 0 || step >= 16) return;

      const steps = state.session.drumPattern[voice];
      steps[step] = !steps[step];
      button.classList.toggle('active', steps[step]);
      button.setAttribute('aria-pressed', String(steps[step]));
      const pad = DRUM_PADS.find((item) => item.id === voice);
      if (pad) button.setAttribute('aria-label', `${pad.name}, step ${step + 1}, ${steps[step] ? 'on' : 'off'}`);
      persist();
    });
  });

  el.modalRoot.querySelectorAll('[data-drum]').forEach((button) => {
    button.addEventListener('click', () => {
      instrumentEngineInstance().playDrum(button.dataset.drum, instrumentDestination(), {
        volume: state.drumVolume,
        tuning: state.drumTuning,
        decay: state.drumDecay,
        tone: state.drumTone
      });
    });
  });

  const choose = document.getElementById('samplerChooseBtn');
  const fileInput = document.getElementById('samplerFile');
  if (choose && fileInput) {
    choose.addEventListener('click', () => fileInput.click());
    fileInput.addEventListener('change', async () => {
      const file = fileInput.files && fileInput.files[0];
      if (!file) return;
      try {
        const arrayBuffer = await file.arrayBuffer();
        const buffer = await engine.decode(arrayBuffer);
        state.samplerBuffer = buffer;
        state.samplerName = file.name.replace(/\.[^.]+$/, '');
        state.samplerSoundId = 'device-file';
        openInstruments();
      } catch (error) {
        toast('That audio file could not be loaded');
      }
    });
  }

  el.modalRoot.querySelectorAll('[data-sampler-sound]').forEach((button) => {
    button.addEventListener('click', () => loadStarterSound(button.dataset.samplerSound));
  });

  el.modalRoot.querySelectorAll('[data-sampler-file]').forEach((button) => {
    button.addEventListener('click', () => {
      const buffer = engine.buffers.get(button.dataset.samplerFile);
      if (!buffer) {
        toast('That sound is not loaded yet');
        return;
      }
      state.samplerBuffer = buffer;
      state.samplerName = button.textContent.trim();
      state.samplerSoundId = button.dataset.samplerFile;
      openInstruments();
    });
  });

  const trigger = document.getElementById('samplerTriggerBtn');
  if (trigger) {
    trigger.addEventListener('click', () => {
      if (!state.samplerBuffer) return;
      instrumentEngineInstance().playBuffer(state.samplerBuffer, instrumentDestination());
    });
  }
}

function playSynth(pitch) {
  instrumentEngineInstance().playSynthNote(model.noteFrequency(pitch), {
    waveform: state.synthWaveform,
    cutoff: state.synthCutoff,
    attack: state.synthAttack,
    release: state.synthRelease,
    duration: 0.8
  }, instrumentDestination());
}

function playTB303(pitch) {
  instrumentEngineInstance().playTB303(model.noteFrequency(pitch), {
    waveform: state.tb303Waveform,
    cutoff: state.tb303Cutoff,
    resonance: state.tb303Resonance,
    envelopeAmount: state.tb303Envelope,
    decay: state.tb303Decay,
    accent: state.tb303Accent,
    tuning: state.tb303Tuning,
    level: state.tb303Level
  }, instrumentDestination());
}

async function loadStarterSound(file) {
  try {
    const response = await fetch(`sounds/${file}`);
    if (!response.ok) throw new Error('missing sound');
    const arrayBuffer = await response.arrayBuffer();
    const buffer = await engine.decode(arrayBuffer);
    state.samplerBuffer = buffer;
    state.samplerName = STARTER_SOUNDS.find((sound) => sound.file === file)?.name ?? file;
    state.samplerSoundId = file;
    openInstruments();
  } catch (error) {
    toast('That sound could not be loaded');
  }
}

// ---------- Sessions ----------

function openTemplates() {
  state.modal = 'templates';
  const templates = [...state.customTemplates, ...model.SESSION_TEMPLATES];
  const cards = templates.map((template) => {
    const lanes = template.tracks.map((slot, index) => `
      <div class="tpl-lane" style="--lane:${model.trackColor(slot.colorIndex ?? index)}">
        <span class="tpl-lane-name">${escapeHtml(slot.name)}</span>
        <span class="tpl-lane-meta">${model.dbLabel(slot.volume)} ${model.panLabel(slot.pan ?? 0)}</span>
      </div>`).join('');
    const count = template.tracks.length;
    return `<article class="tpl-card">
      <div class="tpl-head">
        <div class="tpl-name">
          <strong>${escapeHtml(template.name)}</strong>
          ${template.custom ? '<span class="tpl-tag">CUSTOM</span>' : (template.suggested ? '<span class="tpl-tag">SUGGESTED</span>' : '')}
        </div>
        <span class="tpl-meta">${count} ${count === 1 ? 'TRACK' : 'TRACKS'} · ${template.tempo} BPM</span>
      </div>
      <p class="tpl-desc">${escapeHtml(template.summary)}</p>
      <div class="tpl-lanes">${lanes}</div>
      <div class="tpl-actions">
        <button class="tpl-create" data-template="${template.id}">Create Session →</button>
        ${template.custom ? `<button class="tpl-delete" data-template-delete="${template.id}" aria-label="Delete ${escapeHtml(template.name)}">Delete</button>` : ''}
      </div>
    </article>`;
  }).join('');

  openModal(`
    <header class="modal-header">
      <div style="flex:1;min-width:0">
        <h2>Templates</h2>
        <div class="sub">TRACKS · COLOURS · MIXER SETTINGS</div>
      </div>
      <button class="modal-close" data-close>Cancel</button>
    </header>
    <div class="modal-body">
      <p class="tpl-intro">Start from a layout that already has its tracks, colours and mixer settings dialled in.</p>
      <div class="tpl-grid">${cards}</div>
    </div>`, { tall: true });

  el.modalRoot.querySelectorAll('[data-template]').forEach((button) => {
    button.addEventListener('click', () => {
      const template = templates.find((item) => item.id === button.dataset.template);
      if (!template) return;
      const session = model.createSessionFromTemplate(template, uniqueSessionName(template.name));
      state.store.sessions.push(session);
      state.store.activeId = session.id;
      model.saveStore(state.store);
      closeModal();
      adoptSession(session);
      toast(`${template.name} session created`);
    });
  });
  el.modalRoot.querySelectorAll('[data-template-delete]').forEach((button) => {
    button.addEventListener('click', () => {
      const template = state.customTemplates.find((item) => item.id === button.dataset.templateDelete);
      if (!template || !window.confirm(`Delete template "${template.name}"?`)) return;
      state.customTemplates = state.customTemplates.filter((item) => item.id !== template.id);
      model.saveCustomTemplates(state.customTemplates);
      openTemplates();
    });
  });
}

async function openSessions() {
  state.modal = 'sessions';
  const requestID = (state.sessionsRequestID || 0) + 1;
  state.sessionsRequestID = requestID;
  (state.exportPreviewURLs || []).forEach((url) => URL.revokeObjectURL(url));
  state.exportPreviewURLs = [];
  let exports = [];
  try {
    exports = await model.listExports();
  } catch (error) {
    console.warn('Could not load the export library', error);
  }

  let versions = [];
  try {
    versions = await model.listVersions();
  } catch (error) {
    console.warn('Could not load session versions', error);
  }
  const sessionVersions = versions
    .filter((version) => version.sessionId === state.session.id)
    .sort((left, right) => right.createdAt - left.createdAt)
    .slice(0, SESSION_VERSION_LIMIT);

  if (state.sessionsRequestID !== requestID || state.modal !== 'sessions') return;

  const versionLookup = new Map(sessionVersions.map((version) => [version.id, version]));

  const versionRowsMarkup = () => {
    if (!sessionVersions.length) {
      return '<p class="export-empty">No versions yet. Change the session and a snapshot appears here a couple of seconds later.</p>';
    }
    return sessionVersions.map((version, index) => `
      <article class="version-row">
        <div class="version-main">
          <div class="version-head">
            <strong>${escapeHtml(versionTimeLabel(version.createdAt))}</strong>
            <span class="version-date">${escapeHtml(versionDateLabel(version.createdAt))}</span>
            ${index === 0 ? '<span class="tpl-tag">LATEST</span>' : ''}
          </div>
          <span class="version-meta">${version.trackCount} ${version.trackCount === 1 ? 'track' : 'tracks'} · ${model.formatTime(version.duration)}</span>
          <div class="version-tracks" data-version-tracks="${escapeHtml(version.id)}" hidden>
            ${(version.session.tracks || []).map((track, trackIndex) => `<span class="version-track" style="--track-color:${model.trackColor(track.colorIndex ?? trackIndex)}">${escapeHtml(track.name)}</span>`).join('') || '<span class="version-track">No tracks</span>'}
          </div>
        </div>
        <div class="version-actions">
          <button class="icon-btn" data-version-preview="${escapeHtml(version.id)}" title="Preview" aria-label="Preview version">◉</button>
          <button class="icon-btn" data-version-restore="${escapeHtml(version.id)}" title="Restore">↺</button>
          <button class="icon-btn" data-version-duplicate="${escapeHtml(version.id)}" title="Open as a copy">⧉</button>
        </div>
      </article>`).join('');
  };

  const rows = state.store.sessions.map((session) => {
    const count = session.tracks.length;
    return `<div class="list-row ${session.id === state.session.id ? 'open' : ''}">
      <div class="icon">◫</div>
      <div class="meta">
        <strong>${escapeHtml(session.name)}</strong>
        <span>${count} ${count === 1 ? 'track' : 'tracks'} · ${model.formatTime(model.sessionDuration(session))}</span>
      </div>
      <div class="row-actions">
        <button class="icon-btn" data-session-open="${session.id}" title="Open">▶</button>
        <button class="icon-btn" data-session-rename="${session.id}" title="Rename">✎</button>
        <button class="icon-btn" data-session-duplicate="${session.id}" title="Duplicate">⧉</button>
        <button class="icon-btn" data-session-export="${session.id}" title="Export session">⤓</button>
        <button class="icon-btn" data-session-delete="${session.id}" title="Delete">🗑</button>
      </div>
    </div>`;
  }).join('');
  const previewURLs = new Map();
  exports.forEach((item) => {
    const previewURL = URL.createObjectURL(item.blob);
    previewURLs.set(item.id, previewURL);
    state.exportPreviewURLs.push(previewURL);
  });

  let exportQuery = '';
  let exportFilter = 'all';

  const exportTerm = () => exportQuery.trim().toLowerCase();

  const matchesExportFilter = (item) => exportFilter === 'all'
    || (exportFilter === 'mix' && item.kind !== 'stem')
    || (exportFilter === 'stem' && item.kind === 'stem');

  const visibleExports = () => exports
    .filter((item) => {
      if (!matchesExportFilter(item)) return false;
      const term = exportTerm();
      if (!term) return true;
      const haystack = `${item.name || ''} ${item.sessionName || ''}`.toLowerCase();
      return haystack.includes(term);
    })
    .sort((left, right) => (right.createdAt || 0) - (left.createdAt || 0));

  const exportEmptyMarkup = () => {
    if (!exports.length) {
      return '<p class="export-empty">No bounces yet. Render a mix or stems to build your library.</p>';
    }
    if (exportTerm()) {
      return `<p class="export-empty">No exports match “${escapeHtml(exportQuery.trim())}”. Try another name or switch the filter.</p>`;
    }
    if (exportFilter !== 'all') {
      const label = exportFilter === 'stem' ? 'stems' : 'mixes';
      return `<p class="export-empty">No ${label} saved yet. Switch the filter to see the rest of your library.</p>`;
    }
    return '<p class="export-empty">Nothing to show right now.</p>';
  };

  const exportExtension = (item) => {
    const match = /\.([a-z0-9]+)$/i.exec(item.name || '');
    if (match) return match[1].toLowerCase();
    return (item.format || 'wav').toLowerCase();
  };

  const exportBaseName = (item) => (item.name || 'export').replace(/\.[a-z0-9]+$/i, '');

  const exportRowsMarkup = () => visibleExports().map((item) => {
    const previewURL = previewURLs.get(item.id) || '';
    const kind = item.kind === 'stem' ? 'STEM' : 'MIX';
    const name = item.name || `${kind.toLowerCase()} export`;
    return `<article class="export-row">
      <div class="export-icon" aria-hidden="true">♫</div>
      <div class="export-meta">
        <strong title="${escapeHtml(name)}">${escapeHtml(name)}</strong>
        <span>${kind} · ${escapeHtml(item.format || 'AUDIO')} · ${model.formatTime(item.duration)}</span>
        <span class="export-session">${escapeHtml(item.sessionName || 'Untitled Session')}</span>
      </div>
      <audio class="export-preview" controls preload="none" src="${escapeHtml(previewURL)}" aria-label="Preview ${escapeHtml(name)}"></audio>
      <div class="export-actions">
        <button class="icon-btn export-rename" data-export-rename="${escapeHtml(item.id)}" title="Rename" aria-label="Rename ${escapeHtml(name)}">✎</button>
        <button class="tool" data-export-download="${escapeHtml(item.id)}">Download</button>
        <button class="icon-btn" data-export-delete="${escapeHtml(item.id)}" title="Delete" aria-label="Delete ${escapeHtml(name)}">×</button>
      </div>
    </article>`;
  }).join('');

  const exportCountText = () => {
    const shown = visibleExports().length;
    const total = exports.length;
    return shown === total ? `${total} SAVED` : `${shown} OF ${total} SHOWN`;
  };

  const bindExportRowActions = () => {
    el.modalRoot.querySelectorAll('[data-export-rename]').forEach((button) => {
      button.addEventListener('click', async () => {
        const item = exports.find((entry) => entry.id === button.dataset.exportRename);
        if (!item) return;

        const extension = exportExtension(item);
        const entered = window.prompt('Export name', exportBaseName(item));
        if (entered === null) return;

        const trimmed = entered.trim().replace(/\.[a-z0-9]+$/i, '').trim();
        if (!trimmed) return;

        const name = `${trimmed}.${extension}`;
        if (name === item.name) return;

        try {
          const renamed = await model.renameExport(item.id, name);
          if (!renamed) {
            toast('This export is no longer in the library');
            return;
          }
          item.name = name;
          updateExportList();
          toast(`Export renamed to ${name}`);
        } catch (error) {
          toast('Could not rename this export');
        }
      });
    });

    el.modalRoot.querySelectorAll('[data-export-download]').forEach((button) => {
      button.addEventListener('click', () => {
        const item = exports.find((entry) => entry.id === button.dataset.exportDownload);
        if (item?.blob) download(item.blob, item.name || 'audio-export');
      });
    });

    el.modalRoot.querySelectorAll('[data-export-delete]').forEach((button) => {
      button.addEventListener('click', async () => {
        const item = exports.find((entry) => entry.id === button.dataset.exportDelete);
        if (!item || !window.confirm(`Delete export "${item.name}"?`)) return;
        try {
          await model.removeExport(item.id);
          exports = exports.filter((entry) => entry.id !== item.id);
          const previewURL = previewURLs.get(item.id);
          if (previewURL) {
            URL.revokeObjectURL(previewURL);
            previewURLs.delete(item.id);
            state.exportPreviewURLs = state.exportPreviewURLs.filter((url) => url !== previewURL);
          }
          updateExportList();
          toast('Export deleted');
        } catch (error) {
          toast('Could not delete this export');
        }
      });
    });
  };

  const updateExportList = () => {
    const list = el.modalRoot.querySelector('#exportList');
    if (!list) return;
    list.innerHTML = exportRowsMarkup() || exportEmptyMarkup();
    const count = el.modalRoot.querySelector('#exportCount');
    if (count) count.textContent = exportCountText();
    bindExportRowActions();
  };

  openModal(`
    <header class="modal-header">
      <h2>Sessions</h2>
      <button class="modal-close" data-close>Done</button>
    </header>
    <div class="modal-body">
      <div class="list">${rows}</div>
      <section class="versions-section">
        <div class="exports-heading"><h3>Versions</h3><span id="versionCount">${sessionVersions.length} SAVED</span></div>
        <p class="version-hint">Autosaved a couple of seconds after each change. The open session is kept when you restore.</p>
        <div class="version-list" id="versionList">${versionRowsMarkup()}</div>
      </section>
      <section class="exports-section">
        <div class="exports-heading"><h3>Exports</h3><span id="exportCount">${exportCountText()}</span></div>
        <div class="export-toolbar">
          <input
            id="exportSearch"
            class="export-search"
            type="search"
            placeholder="Search exports and sessions"
            aria-label="Search exports and sessions"
            autocomplete="off"
            spellcheck="false" />
          <div class="export-filters" role="group" aria-label="Filter exports by type">
            <button class="pill on" data-export-filter="all" aria-pressed="true">All</button>
            <button class="pill" data-export-filter="mix" aria-pressed="false">Mixes</button>
            <button class="pill" data-export-filter="stem" aria-pressed="false">Stems</button>
          </div>
        </div>
        <div class="export-list" id="exportList">${exportRowsMarkup() || exportEmptyMarkup()}</div>
      </section>
    </div>
    <footer class="modal-footer">
      <button class="tool" id="importSessionBtn">Import Session</button>
      <button class="tool" id="saveSessionTemplateBtn" ${state.session.tracks.length ? '' : 'disabled'}>Save as Template</button>
      <button class="tool primary" id="newSessionBtn">+ New Session</button>
    </footer>`);

  document.getElementById('newSessionBtn').addEventListener('click', () => {
    const session = model.createSession(uniqueSessionName('Untitled Session'));
    state.store.sessions.push(session);
    state.store.activeId = session.id;
    model.saveStore(state.store);
    closeModal();
    adoptSession(session);
    toast('New session created');
  });

  document.getElementById('importSessionBtn').addEventListener('click', () => {
    el.sessionImportInput.click();
  });

  el.modalRoot.querySelectorAll('[data-session-export]').forEach((button) => {
    button.addEventListener('click', () => {
      void exportSessionBundle(button.dataset.sessionExport);
    });
  });

  document.getElementById('saveSessionTemplateBtn').addEventListener('click', () => {
    const entered = window.prompt('Template name', `${state.session.name} Template`);
    if (entered === null) return;
    const template = model.createCustomTemplate(state.session, entered.trim() || `${state.session.name} Template`);
    state.customTemplates.unshift(template);
    model.saveCustomTemplates(state.customTemplates);
    openSessions();
    toast(`Template "${template.name}" saved`);
  });

  bindExportRowActions();

  const exportSearchInput = el.modalRoot.querySelector('#exportSearch');
  if (exportSearchInput) {
    exportSearchInput.addEventListener('input', () => {
      exportQuery = exportSearchInput.value;
      updateExportList();
    });
  }

  el.modalRoot.querySelectorAll('[data-export-filter]').forEach((button) => {
    button.addEventListener('click', () => {
      exportFilter = button.dataset.exportFilter || 'all';
      el.modalRoot.querySelectorAll('[data-export-filter]').forEach((other) => {
        const active = other === button;
        other.classList.toggle('on', active);
        other.setAttribute('aria-pressed', String(active));
      });
      updateExportList();
    });
  });

  el.modalRoot.querySelectorAll('[data-session-open]').forEach((button) => {
    button.addEventListener('click', () => {
      const session = state.store.sessions.find((item) => item.id === button.dataset.sessionOpen);
      if (!session) return;
      state.store.activeId = session.id;
      model.saveStore(state.store);
      closeModal();
      adoptSession(session);
    });
  });

  el.modalRoot.querySelectorAll('[data-session-rename]').forEach((button) => {
    button.addEventListener('click', () => {
      const session = state.store.sessions.find((item) => item.id === button.dataset.sessionRename);
      if (!session) return;
      const name = window.prompt('Session name', session.name);
      if (name === null) return;
      const trimmed = name.trim();
      if (!trimmed) return;
      session.name = trimmed;
      if (session.id === state.session.id) state.session.name = trimmed;
      persist();
      model.saveStore(state.store);
      openSessions();
      renderHeader();
    });
  });

  el.modalRoot.querySelectorAll('[data-session-duplicate]').forEach((button) => {
    button.addEventListener('click', () => {
      const session = state.store.sessions.find((item) => item.id === button.dataset.sessionDuplicate);
      if (!session) return;
      const copy = JSON.parse(JSON.stringify(session));
      copy.id = model.uid();
      copy.name = uniqueSessionName(`${session.name} Copy`);
      const trackIDs = new Map();
      copy.tracks = copy.tracks.map((track) => {
        const newID = model.uid();
        trackIDs.set(track.id, newID);
        return {
          ...track,
          id: newID,
          clips: track.clips.map((clip) => ({ ...clip, id: model.uid() })),
          notes: track.notes.map((note) => ({ ...note, id: model.uid() }))
        };
      });
      copy.groups = (copy.groups || []).map((group) => ({
        ...group,
        id: model.uid(),
        trackIDs: group.trackIDs.map((id) => trackIDs.get(id)).filter(Boolean)
      }));
      state.store.sessions.push(copy);
      model.saveStore(state.store);
      openSessions();
    });
  });

  el.modalRoot.querySelectorAll('[data-session-delete]').forEach((button) => {
    button.addEventListener('click', () => {
      const id = button.dataset.sessionDelete;
      if (state.store.sessions.length <= 1) {
        toast('Keep at least one session');
        return;
      }
      const session = state.store.sessions.find((item) => item.id === id);
      if (!session) return;
      if (!window.confirm(`Delete "${session.name}"?`)) return;
      state.store.sessions = state.store.sessions.filter((item) => item.id !== id);
      void model.removeVersionsForSession(id);
      if (state.store.activeId === id) {
        state.store.activeId = state.store.sessions[0].id;
        model.saveStore(state.store);
        closeModal();
        adoptSession(state.store.sessions[0]);
        return;
      }
      model.saveStore(state.store);
      openSessions();
    });
  });

  el.modalRoot.querySelectorAll('[data-version-preview]').forEach((button) => {
    button.addEventListener('click', () => {
      const detail = el.modalRoot.querySelector(`[data-version-tracks="${button.dataset.versionPreview}"]`);
      if (detail) detail.hidden = !detail.hidden;
    });
  });

  el.modalRoot.querySelectorAll('[data-version-restore]').forEach((button) => {
    button.addEventListener('click', async () => {
      const version = versionLookup.get(button.dataset.versionRestore);
      if (!version) return;
      if (!window.confirm('Restore this version? Your current session is saved as a version first.')) return;
      await restoreVersion(version);
      closeModal();
      toast('Version restored');
    });
  });

  el.modalRoot.querySelectorAll('[data-version-duplicate]').forEach((button) => {
    button.addEventListener('click', async () => {
      const version = versionLookup.get(button.dataset.versionDuplicate);
      if (!version) return;
      await duplicateVersion(version);
    });
  });
}

function uniqueSessionName(base) {
  const names = new Set(state.store.sessions.map((session) => session.name));
  if (!names.has(base)) return base;
  let index = 2;
  while (names.has(`${base} ${index}`)) index += 1;
  return `${base} ${index}`;
}

// ---------- Event wiring ----------

function bindEvents() {
  el.sessionImportInput.addEventListener('change', () => {
    const file = el.sessionImportInput.files && el.sessionImportInput.files[0];
    el.sessionImportInput.value = '';
    if (file) void importSessionBundle(file);
  });
  el.midiImportInput.addEventListener('change', () => {
    const file = el.midiImportInput.files && el.midiImportInput.files[0];
    el.midiImportInput.value = '';
    if (file) void importMidiFile(file);
  });
  window.addEventListener('resize', handleViewportChange);
  window.addEventListener('orientationchange', () => {
    handleViewportChange();
    window.setTimeout(handleViewportChange, 320);
  });
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', handleViewportChange);
  }
  el.modeSimpleBtn.addEventListener('click', () => setStudioMode('simple'));
  el.modeProBtn.addEventListener('click', () => setStudioMode('pro'));
  el.addTrackBtn.addEventListener('click', () => el.fileInput.click());
  el.emptyImportBtn.addEventListener('click', () => el.fileInput.click());
  el.fileInput.addEventListener('change', () => {
    importFiles(el.fileInput.files);
    el.fileInput.value = '';
  });
  el.blankTrackBtn.addEventListener('click', addBlankTrack);
  el.instrumentTrackBtn?.addEventListener('click', addInstrumentTrack);
  el.emptyInstrumentTrackBtn?.addEventListener('click', addInstrumentTrack);
  el.templatesBtn.addEventListener('click', openTemplates);
  el.emptyTemplatesBtn?.addEventListener('click', openTemplates);
  el.instrumentsBtn.addEventListener('click', openInstruments);
  el.stemBounceBtn?.addEventListener('click', bounceStems);
  el.bounceBtn.addEventListener('click', bounceMix);

  el.undoBtn.addEventListener('click', undo);
  el.redoBtn.addEventListener('click', redo);
  el.mixerBtn.addEventListener('click', openMixer);
  el.masteringBtn.addEventListener('click', openMastering);
  el.fxBtn.addEventListener('click', openMasterEffects);
  el.presetBtn.addEventListener('click', openChannelPresets);
  el.sessionsBtn.addEventListener('click', openSessions);

  el.playBtn.addEventListener('click', togglePlay);
  el.stopBtn.addEventListener('click', stopPlayback);
  el.rewindBtn.addEventListener('click', () => {
    engine.seek(0);
    state.playhead = 0;
    renderTransport();
    updatePlayhead();
  });

  el.loopBtn.addEventListener('click', () => {
    const session = state.session;
    if (!model.hasLoopRange(session)) return;
    snapshot();
    session.loop.enabled = !session.loop.enabled;
    persist();
    render();
  });

  el.punchBtn.addEventListener('click', () => {
    const session = state.session;
    if (!hasPunchRange()) return;
    snapshot();
    session.punch.enabled = !session.punch.enabled;
    persist();
    render();
  });

  el.punchInBtn.addEventListener('click', () => {
    const session = state.session;
    snapshot();
    const time = Math.max(0, currentPosition());
    session.punch.in = time;
    if (session.punch.out <= time + 0.05) session.punch.out = time + 1;
    persist();
    render();
  });

  el.punchOutBtn.addEventListener('click', () => {
    const session = state.session;
    snapshot();
    session.punch.out = Math.max(session.punch.in + 0.05, currentPosition());
    persist();
    render();
  });

  el.punchArm.addEventListener('change', () => {
    const session = state.session;
    snapshot();
    session.punch.armedTrackId = el.punchArm.value || null;
    persist();
    render();
  });

  if (el.sectionBtn) {
    el.sectionBtn.addEventListener('click', addSectionAtPlayhead);
  }

  el.sectionLayer.addEventListener('pointerdown', (event) => {
    const flag = event.target.closest('.section-flag');
    if (!flag) return;
    const sections = state.session.sections || [];
    const deleteButton = event.target.closest('[data-section-delete]');

    if (deleteButton) {
      event.preventDefault();
      const id = deleteButton.dataset.sectionDelete;
      const section = sections.find((item) => item.id === id);
      if (!section) return;
      if (!window.confirm(`Delete section "${section.name}"?`)) return;
      snapshot();
      state.session.sections = sections.filter((item) => item.id !== id);
      persist();
      renderTimeline();
      return;
    }

    const section = sections.find((item) => item.id === flag.dataset.section);
    if (!section) return;
    event.preventDefault();

    const startX = event.clientX;
    const origin = section.time;
    let moved = false;
    let tookSnapshot = false;

    startDrag((moveEvent) => {
      const dx = moveEvent.clientX - startX;
      if (Math.abs(dx) > 4) moved = true;
      if (!moved) return;
      if (!tookSnapshot) {
        snapshot();
        tookSnapshot = true;
      }
      section.time = snappedBarTime(origin + dx / state.zoom);
      flag.style.left = `${section.time * state.zoom}px`;
    }, () => {
      if (!tookSnapshot) {
        seekTo(section.time);
        return;
      }
      state.session.sections.sort((a, b) => a.time - b.time);
      persist();
      renderTimeline();
    });
  });

  el.sectionLayer.addEventListener('dblclick', (event) => {
    const flag = event.target.closest('.section-flag');
    if (!flag) return;
    const section = (state.session.sections || []).find((item) => item.id === flag.dataset.section);
    if (!section) return;
    const entered = window.prompt('Section name', section.name);
    if (entered === null) return;
    const name = entered.trim();
    if (!name) return;
    snapshot();
    section.name = name;
    persist();
    renderTimeline();
  });

  el.metronomeBtn.addEventListener('click', () => {
    snapshot();
    state.session.metronome.enabled = !state.session.metronome.enabled;
    persist();
    renderTransport();
  });

  el.metronomeLevel.addEventListener('input', () => {
    state.session.metronome.level = model.clamp(Number(el.metronomeLevel.value), 0, 1);
    persist();
  });

  el.countInBtn.addEventListener('click', () => {
    snapshot();
    state.session.metronome.countIn = !state.session.metronome.countIn;
    if (!state.session.metronome.countIn) cancelCountIn();
    persist();
    renderTransport();
  });

  el.tempoDown.addEventListener('click', () => changeTempo(-1));
  el.tempoUp.addEventListener('click', () => changeTempo(1));
  el.tempoValue.addEventListener('click', () => {
    const value = window.prompt('Session tempo (60–200 BPM)', String(state.session.tempo));
    if (value === null) return;
    const bpm = Number(value);
    if (!Number.isFinite(bpm)) return;
    snapshot();
    state.session.tempo = model.clamp(Math.round(bpm), 60, 200);
    engine.applyMasterEffects();
    persist();
    render();
  });

  el.arrScroll.addEventListener('scroll', () => {
    updatePlayhead();
  });

  // Track header + clip actions (delegated)
  el.arrHeads.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-act]');
    if (!button) return;
    const trackId = button.dataset.track;
    switch (button.dataset.act) {
      case 'mute': toggleMute(trackId); break;
      case 'solo': toggleSolo(trackId); break;
      case 'freeze': toggleFreeze(trackId); break;
      case 'eq': openEQ(trackId); break;
      case 'roll': openRoll(trackId); break;
      case 'instrument': openInstruments(trackId); break;
      case 'automation': toggleAutomation(trackId); break;
      case 'automation-pan': toggleAutomation(trackId, 'pan'); break;
      case 'takes': openTakeLane(trackId); break;
      case 'audition-take': openTakeLane(trackId); break;
      default: break;
    }
  });

  el.arrHeads.addEventListener('input', (event) => {
    const input = event.target.closest('input[data-act="volume"]');
    if (!input) return;
    const track = trackById(input.dataset.track);
    if (!track) return;
    setTrackVolume(track, Number(input.value));
    persist();
  });

  el.arrHeads.addEventListener('pointerdown', (event) => {
    if (event.target.closest('input[data-act="volume"]')) snapshot();
  });

  // Lane interactions
  el.lanes.addEventListener('pointerdown', (event) => {
    const lane = event.target.closest('.lane');
    if (!lane) return;
    const track = trackById(lane.dataset.track);
    if (!track) return;

    const pointEl = event.target.closest('.auto-point');
    if (pointEl) {
      const param = state.automationParam;
      const key = automationValueKey();
      const point = activeAutomationPoints(track).find((item) => item.id === pointEl.dataset.point);
      if (!point) return;
      event.preventDefault();
      state.selectedAutomationPoint = point.id;
      snapshot();
      const origin = { ...point };
      const startX = event.clientX;
      const startY = event.clientY;
      startDrag((moveEvent) => {
        const dx = moveEvent.clientX - startX;
        const dy = moveEvent.clientY - startY;
        point.time = snapTime(origin.time + dx / state.zoom);
        const unit = automationUnit(param, origin[key]) - dy / ROW_HEIGHT;
        point[key] = automationValueFromUnit(param, model.clamp(unit, 0, 1));
        pointEl.style.left = `${point.time * state.zoom}px`;
        pointEl.style.top = `${automationY(param, point[key])}px`;
        const canvas = lane.querySelector('.automation-canvas');
        if (canvas) drawAutomation(canvas, track, Number(el.arrContent.style.width.replace('px', '')), state.zoom, param);
      }, () => {
        track.automation = [...(track.automation || [])].sort((a, b) => a.time - b.time);
        track.panAutomation = [...(track.panAutomation || [])].sort((a, b) => a.time - b.time);
        persist();
        renderTimeline();
      });
      return;
    }

    const clipEl = event.target.closest('.clip');
    if (!clipEl) {
      if (state.automationTrack === track.id) {
        event.preventDefault();
        const startX = event.clientX;
        const startY = event.clientY;
        window.addEventListener('pointerup', (upEvent) => {
          const movement = Math.hypot(upEvent.clientX - startX, upEvent.clientY - startY);
          if (movement > 6) return;
          const time = automationTimeAt(lane, upEvent.clientX);
          const param = state.automationParam;
          const key = automationValueKey();
          const value = automationValueAt(lane, upEvent.clientY, param);
          snapshot();
          const point = { id: model.uid(), time };
          point[key] = value;
          const list = activeAutomationPoints(track);
          list.push(point);
          list.sort((a, b) => a.time - b.time);
          state.selectedAutomationPoint = point.id;
          persist();
          renderTimeline();
        }, { once: true });
      } else if (state.selectedClip) {
        state.selectedClip = null;
        renderTimeline();
      }
      return;
    }

    if (track.frozen?.fileId) {
      state.selectedClip = clipEl.dataset.clip;
      renderTimeline();
      toast('Unfreeze the track to edit this clip');
      return;
    }

    const clip = track.clips.find((item) => item.id === clipEl.dataset.clip);
    if (!clip) return;

    state.selectedClip = clip.id;
    state.selectedAutomationPoint = null;
    el.lanes.querySelectorAll('.clip').forEach((element) => {
      element.classList.toggle('selected', element.dataset.clip === clip.id);
    });
    updateClipToolbar();

    const isTrim = event.target.classList.contains('trim');
    const edge = event.target.dataset.edge;
    const startX = event.clientX;
    const origin = { ...clip };
    const minimum = beatDuration() / 4;

    snapshot();

    startDrag((moveEvent) => {
      const delta = (moveEvent.clientX - startX) / state.zoom;
      if (isTrim && edge === 'left') {
        const change = Math.min(origin.duration - minimum, Math.max(-origin.sourceStart, delta));
        clip.start = origin.start + change;
        clip.sourceStart = origin.sourceStart + change;
        clip.duration = origin.duration - change;
      } else if (isTrim && edge === 'right') {
        clip.duration = model.clamp(
          Math.round((origin.duration + delta) / minimum) * minimum,
          minimum,
          origin.sourceDuration - origin.sourceStart
        );
      } else {
        clip.start = snapTime(Math.max(0, origin.start + delta));
      }
      clipEl.style.left = `${Math.max(0, clip.start) * state.zoom}px`;
      clipEl.style.width = `${Math.max(18, clip.duration * state.zoom)}px`;
    }, () => {
      persist();
      renderTimeline();
      updateClipToolbar();
    });
  });

  // Double-tap an automation point to remove it
  el.lanes.addEventListener('dblclick', (event) => {
    const pointEl = event.target.closest('.auto-point');
    if (!pointEl) return;
    const track = trackById(pointEl.dataset.track);
    if (!track) return;
    snapshot();
    const pointId = pointEl.dataset.point;
    if (state.automationParam === 'pan') {
      track.panAutomation = (track.panAutomation || []).filter((point) => point.id !== pointId);
    } else {
      track.automation = (track.automation || []).filter((point) => point.id !== pointId);
    }
    state.selectedAutomationPoint = null;
    persist();
    renderTimeline();
    toast('Automation point removed');
  });

  // Ruler scrubbing
  el.rulerCanvas.addEventListener('pointerdown', (event) => {
    event.preventDefault();
    const rect = el.rulerCanvas.getBoundingClientRect();
    const wasPlaying = engine.isPlaying;
    if (wasPlaying) engine.pause();
    const apply = (clientX) => {
      const x = Math.max(0, Math.min(rect.width, clientX - rect.left));
      engine.seek(x / state.zoom);
      state.playhead = engine.position;
      updatePlayhead();
    };
    apply(event.clientX);
    startDrag((moveEvent) => apply(moveEvent.clientX), () => {
      if (wasPlaying) engine.play(engine.position);
      renderTransport();
    });
  });

  // Loop strip
  const stripRect = () => el.loopStrip.getBoundingClientRect();
  el.loopStrip.addEventListener('pointerdown', (event) => {
    if (event.target.closest('.loop-handle')) return;
    event.preventDefault();
    const rect = stripRect();
    const startX = event.clientX - rect.left;
    const anchor = snapTime(startX / state.zoom);
    let moved = false;
    let tookSnapshot = false;

    const apply = (clientX) => {
      const x = clientX - rect.left;
      if (Math.abs(x - startX) > 2) moved = true;
      if (!moved) return;
      if (!tookSnapshot) {
        snapshot();
        tookSnapshot = true;
      }
      const current = snapTime(x / state.zoom);
      setLoopRange(Math.min(anchor, current), Math.max(anchor, current));
      renderLoopStrip(parseFloat(el.arrContent.style.width) || 480, state.zoom);
    };

    startDrag((moveEvent) => apply(moveEvent.clientX), () => {
      if (tookSnapshot) {
        persist();
        render();
      }
    });
  });

  [el.loopStartHandle, el.loopEndHandle].forEach((handle) => {
    handle.addEventListener('pointerdown', (event) => {
      event.preventDefault();
      event.stopPropagation();
      const edge = handle.dataset.edge;
      const startX = event.clientX;
      const origin = { ...state.session.loop };
      snapshot();

      startDrag((moveEvent) => {
        const delta = (moveEvent.clientX - startX) / state.zoom;
        if (edge === 'start') {
          setLoopStart(origin.start + delta);
        } else {
          setLoopEnd(origin.end + delta);
        }
        renderLoopStrip(parseFloat(el.arrContent.style.width) || 480, state.zoom);
      }, () => {
        persist();
        render();
      });
    });
  });

  window.addEventListener('keydown', (event) => {
    if (event.target instanceof HTMLInputElement) return;
    if (event.code === 'Space') {
      event.preventDefault();
      togglePlay();
    } else if (event.key === 'Backspace' || event.key === 'Delete') {
      const info = selectedClipInfo();
      if (info) {
        snapshot();
        info.track.clips = info.track.clips.filter((clip) => clip.id !== info.clip.id);
        state.selectedClip = null;
        persist();
        engine.rebuild();
        renderTimeline();
      }
    }
  });
}

function changeTempo(delta) {
  snapshot();
  state.session.tempo = model.clamp(state.session.tempo + delta, 60, 200);
  engine.applyMasterEffects();
  persist();
  render();
}

async function createHouseDemoSession() {
  const sampleFiles = ['starter-kick-1.wav', 'starter-snare.wav', 'starter-clap.wav', 'starter-hat.wav'];
  const sounds = new Map();
  for (const file of sampleFiles) {
    try {
      const response = await fetch(`sounds/${file}`);
      if (!response.ok) throw new Error(`Could not load ${file}`);
      const audioData = await response.arrayBuffer();
      const buffer = await engine.decode(audioData.slice(0));
      const blob = new Blob([audioData], { type: 'audio/wav' });
      const fileId = await model.saveFile(blob, file);
      state.buffers.set(fileId, buffer);
      engine.buffers.set(fileId, buffer);
      state.peaks.set(fileId, computePeaks(buffer));
      sounds.set(file, { fileId, duration: buffer.duration });
    } catch (error) {
      console.warn('Could not load a house-demo sound', error);
    }
  }

  const session = model.createSession('Night Drive — House Demo');
  const tempo = 124;
  const beat = 60 / tempo;
  const barLength = beat * 4;
  const barCount = 8;
  session.tempo = tempo;
  session.templateId = 'house-demo';
  session.masterVolume = 0.88;
  session.masterEffects = {
    bypassed: false,
    reverbMix: 0.12,
    reverbDecay: 1.6,
    delayBeats: 0.5,
    delayFeedback: 0.24,
    delayMix: 0.1
  };

  const kickTrack = model.createTrack({ name: 'Kick', index: 0 });
  const percussionTrack = model.createTrack({ name: 'Snare & Clap', index: 1 });
  const hatTrack = model.createTrack({ name: 'Hi-Hats', index: 2 });
  const bassTrack = model.createTrack({ name: 'Bass', index: 3 });
  const chordTrack = model.createTrack({ name: 'Chords', index: 4 });
  const leadTrack = model.createTrack({ name: 'Lead', index: 5 });
  kickTrack.volume = 0.92;
  percussionTrack.volume = 0.76;
  hatTrack.volume = 0.62;
  hatTrack.pan = 0.12;
  bassTrack.volume = 0.78;
  bassTrack.eq.low.gain = 2;
  bassTrack.eq.high.gain = -1;
  bassTrack.comp.bypassed = false;
  bassTrack.comp.threshold = -20;
  bassTrack.comp.ratio = 3;
  chordTrack.volume = 0.58;
  chordTrack.pan = -0.12;
  leadTrack.volume = 0.52;
  leadTrack.pan = 0.16;

  const appendHit = (track, file, label, start, maxDuration) => {
    const sound = sounds.get(file);
    if (!sound) return;
    const duration = Math.min(sound.duration, maxDuration);
    track.clips.push({
      id: model.uid(),
      name: label,
      fileId: sound.fileId,
      start,
      duration,
      sourceStart: 0,
      sourceDuration: sound.duration
    });
  };

  for (let beatIndex = 0; beatIndex < barCount * 4; beatIndex += 1) {
    const time = beatIndex * beat;
    appendHit(kickTrack, 'starter-kick-1.wav', 'House Kick', time, beat * 0.9);
    if (beatIndex % 4 === 1 || beatIndex % 4 === 3) {
      appendHit(percussionTrack, 'starter-snare.wav', 'Snare', time, beat * 0.9);
      appendHit(percussionTrack, 'starter-clap.wav', 'Clap', time, beat * 0.7);
    }
  }
  for (let eighthIndex = 0; eighthIndex < barCount * 8; eighthIndex += 1) {
    appendHit(hatTrack, 'starter-hat.wav', 'Closed Hat', eighthIndex * beat / 2, beat * 0.22);
  }

  const bassRoots = [48, 53, 55, 50];
  for (let bar = 0; bar < barCount; bar += 1) {
    const root = bassRoots[bar % bassRoots.length];
    for (let step = 0; step < 8; step += 1) {
      bassTrack.notes.push({
        id: model.uid(),
        pitch: root + (step % 4 === 3 ? 12 : 0),
        start: bar * barLength + step * beat / 2,
        duration: beat * 0.42,
        velocity: step === 0 || step === 4 ? 0.92 : 0.72
      });
    }
  }

  const chordRoots = [57, 53, 48, 55];
  const chordIntervals = [[0, 3, 7], [0, 4, 7], [0, 4, 7], [0, 4, 7]];
  for (let bar = 0; bar < barCount; bar += 1) {
    const root = chordRoots[bar % chordRoots.length];
    for (const step of [1, 3, 5, 7]) {
      for (const interval of chordIntervals[bar % chordIntervals.length]) {
        chordTrack.notes.push({
          id: model.uid(),
          pitch: root + interval,
          start: bar * barLength + step * beat / 2,
          duration: beat * 0.34,
          velocity: 0.54
        });
      }
    }
  }

  const melody = [69, 67, 64, 67, 71, 69, 67, 64];
  for (let bar = 0; bar < barCount; bar += 1) {
    for (let step = 0; step < 4; step += 1) {
      leadTrack.notes.push({
        id: model.uid(),
        pitch: melody[(bar * 4 + step) % melody.length],
        start: bar * barLength + step * beat + beat * 0.5,
        duration: beat * 0.32,
        velocity: step === 0 ? 0.72 : 0.5
      });
    }
  }

  session.tracks = [kickTrack, percussionTrack, hatTrack, bassTrack, chordTrack, leadTrack];
  session.sections = [
    { id: model.uid(), name: 'Intro', time: 0 },
    { id: model.uid(), name: 'Build', time: barLength * 2 },
    { id: model.uid(), name: 'Drop', time: barLength * 4 },
    { id: model.uid(), name: 'Outro', time: barLength * 7 }
  ];
  return model.normalizeSession(session);
}

// ---------- Boot ----------

function render() {
  renderHeader();
  renderTimeline();
  renderTransport();
}

async function boot() {
  const stored = state.store.sessions.find((session) => session.id === state.store.activeId) || state.store.sessions[0];
  state.session = model.normalizeSession(stored);

  if (state.store.needsDemo) {
    try {
      const demo = await createHouseDemoSession();
      const replacePlaceholder = state.store.sessions.length === 1
        && state.store.sessions[0].name === 'Untitled Session'
        && state.store.sessions[0].tracks.length === 0;
      state.session = demo;
      state.store.sessions = replacePlaceholder ? [demo] : [...state.store.sessions, demo];
      state.store.activeId = demo.id;
    } catch (error) {
      console.warn('Could not prepare the house demo session', error);
    }
  }

  state.store.needsDemo = false;
  state.store.houseDemoSeeded = true;
  state.mode = localStorage.getItem('studio.mode') === 'pro' ? 'pro' : 'simple';
  applyStudioMode();
  const index = state.store.sessions.findIndex((session) => session.id === state.session.id);
  if (index >= 0) state.store.sessions[index] = state.session;
  else state.store.sessions.push(state.session);
  state.store.activeId = state.session.id;
  model.saveStore(state.store);
  engine.setSession(state.session);
  engine.setDrumHitScheduler((pad, when) => instrumentEngineInstance().playDrum(pad, instrumentDestination(), {
    volume: state.drumVolume,
    tuning: state.drumTuning,
    decay: state.drumDecay,
    tone: state.drumTone,
    when
  }));
  ensureClipToolbar();
  state.presets = loadPresets();
  state.customTemplates = model.loadCustomTemplates();
  try {
    state.bounceSettings = JSON.parse(localStorage.getItem('ai-studio.web.bounce-settings.v1') || 'null');
  } catch (error) {
    state.bounceSettings = null;
  }
  bindEvents();
  render();
  lastVersionSignature = versionSignature(state.session);
  void ensureInitialVersion();
  requestAnimationFrame(frame);

  preloadAudio().then(() => {
    engine.rebuild();
    render();
  });
}

boot();
