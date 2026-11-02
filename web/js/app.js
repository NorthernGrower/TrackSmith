// AI Music Studio — web app shell: rendering, interactions and persistence.

import * as model from './model.js';
import { StudioEngine, encodeWav } from './audio-engine.js';

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
  zoom: 70,
  playhead: 0,
  selectedClip: null,
  automationTrack: null,
  automationParam: 'volume',
  selectedAutomationPoint: null,
  rollTrackId: null,
  selectedNote: null,
  rollDivision: 2,
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
  modal: null
};

const el = {
  sessionName: document.getElementById('sessionName'),
  sessionSubtitle: document.getElementById('sessionSubtitle'),
  undoBtn: document.getElementById('undoBtn'),
  redoBtn: document.getElementById('redoBtn'),
  mixerBtn: document.getElementById('mixerBtn'),
  fxBtn: document.getElementById('fxBtn'),
  presetBtn: document.getElementById('presetBtn'),
  sessionsBtn: document.getElementById('sessionsBtn'),
  addTrackBtn: document.getElementById('addTrackBtn'),
  blankTrackBtn: document.getElementById('blankTrackBtn'),
  bounceBtn: document.getElementById('bounceBtn'),
  fileInput: document.getElementById('fileInput'),
  emptyImportBtn: document.getElementById('emptyImportBtn'),
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
  metronomeBtn: document.getElementById('metronomeBtn'),
  metronomeLevel: document.getElementById('metronomeLevel'),
  countInBtn: document.getElementById('countInBtn'),
  tempoValue: document.getElementById('tempoValue'),
  tempoDown: document.getElementById('tempoDown'),
  tempoUp: document.getElementById('tempoUp'),
  modalRoot: document.getElementById('modalRoot'),
  toast: document.getElementById('toast')
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

function currentPosition() {
  return engine.isPlaying ? engine.getPosition() : engine.position;
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
}

let saveTimer = null;

function scheduleSave() {
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    model.saveStore(state.store);
    saveTimer = null;
  }, 250);
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
  const index = state.store.sessions.findIndex((item) => item.id === state.session.id);
  if (index >= 0) state.store.sessions[index] = state.session;
  state.store.activeId = state.session.id;
  state.selectedClip = null;
  state.selectedAutomationPoint = null;
  state.selectedNote = null;
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

function renderTimeline() {
  const session = state.session;
  const hasTracks = session.tracks.length > 0;
  el.emptyState.classList.toggle('visible', !hasTracks);
  el.arrGrid.style.display = hasTracks ? 'flex' : 'none';
  if (!hasTracks) {
    updatePlayhead();
    return;
  }

  const pps = state.zoom;
  const duration = sessionDuration();
  const scrollWidth = el.arrScroll.clientWidth || 320;
  const contentWidth = Math.max(scrollWidth, duration * pps + 240, 480);
  const beatPx = beatDuration() * pps;
  el.arrContent.style.width = `${contentWidth}px`;
  el.lanes.style.setProperty('--beat-width', `${beatPx}px`);

  renderHeads();
  renderRuler(contentWidth, beatPx);
  renderLanes(contentWidth, pps, beatPx);
  renderLoopStrip(contentWidth, pps);
  renderSections(pps);
  updatePlayhead();
  updateClipToolbar();
}

function renderHeads() {
  const session = state.session;
  const parts = [];
  parts.push(`<div class="heads-spacer"><span class="meter-label">4/4</span><span>TRACKS</span><span style="margin-left:auto">${session.tracks.length}</span></div>`);

  session.tracks.forEach((track, index) => {
    const color = model.trackColor(index);
    const frozen = Boolean(track.frozen?.fileId);
    parts.push(`
      <div class="track-head" style="--track-color:${color}">
        <div class="track-head-top">
          <span class="track-index">${String(index + 1).padStart(2, '0')}</span>
          <span class="track-name">${escapeHtml(track.name)}</span>
          <button class="icon-btn" data-act="eq" data-track="${track.id}" title="Equalizer">≡</button>
          <button class="icon-btn ${frozen ? 'off' : ''}" data-act="roll" data-track="${track.id}" title="Piano roll" ${frozen ? 'disabled' : ''}>♫</button>
          <button class="icon-btn ${state.automationTrack === track.id && state.automationParam === 'volume' ? '' : 'off'}" data-act="automation" data-track="${track.id}" title="Volume automation">⋀</button>
          <button class="icon-btn ${state.automationTrack === track.id && state.automationParam === 'pan' ? '' : 'off'}" data-act="automation-pan" data-track="${track.id}" title="Pan automation">⇄</button>
        </div>
        <div class="track-head-row">
          <div style="display:flex;flex-direction:column;gap:4px">
            <button class="mini ${track.muted ? 'on' : ''}" data-act="mute" data-track="${track.id}" title="Mute">M</button>
            <button class="mini ${track.soloed ? 'on' : ''}" data-act="solo" data-track="${track.id}" title="Solo">S</button>
          </div>
          <button class="mini snow ${frozen ? 'frozen' : ''}" data-act="freeze" data-track="${track.id}" title="${frozen ? 'Unfreeze' : 'Freeze to audio'}">❄</button>
          <div class="spacer"></div>
          <input type="range" class="fader" min="0" max="1" step="0.01" value="${track.volume}" data-act="volume" data-track="${track.id}" aria-label="Volume for ${escapeHtml(track.name)}">
          <div class="meter" data-meter="${track.id}"><div class="meter-fill"></div></div>
        </div>
      </div>`);
  });

  el.arrHeads.innerHTML = parts.join('');
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
        <span class="trim trim-left" data-edge="left"></span>
        <span class="trim trim-right" data-edge="right"></span>
      </div>`;
    }).join('');

    const automation = state.automationTrack === track.id ? '<canvas class="automation-canvas"></canvas>' : '';
    const activePoints = state.automationTrack === track.id
      ? activeAutomationPoints(track)
      : [];
    const points = activePoints.length
      ? [...activePoints].sort((a, b) => a.time - b.time).map((point) => (
        `<div class="auto-point ${state.selectedAutomationPoint === point.id ? 'selected' : ''}" data-act="auto-point" data-point="${point.id}" data-track="${track.id}" style="left:${point.time * pps}px;top:${automationY(state.automationParam, point[automationValueKey()])}px"></div>`
      )).join('')
      : '';

    parts.push(`<div class="lane" data-track="${track.id}" style="--beat-width:${beatPx}px">${clipHtml}${automation}${points}</div>`);
  });

  el.lanes.innerHTML = parts.join('');

  el.lanes.querySelectorAll('canvas.clip-wave').forEach((canvas) => {
    drawClipWave(canvas, state.peaks.get(canvas.dataset.file));
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
    updateMeters();
    if (state.countInActive) {
      renderTransport();
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

async function bounceMix() {
  if (state.bouncing) return;
  state.bouncing = true;
  renderTransport();
  toast('Bouncing mix…');
  try {
    const buffer = await engine.renderMix({ masterVolume: state.session.masterVolume });
    download(encodeWav(buffer), `${safeName(state.session.name)}.wav`);
    toast('Bounce complete');
  } catch (error) {
    toast(error.message || 'Bounce failed');
  }
  state.bouncing = false;
  renderTransport();
}

// ---------- Import ----------

async function importFiles(fileList) {
  const files = Array.from(fileList || []).filter((file) => (
    file.type.startsWith('audio') || /\.(wav|mp3|m4a|aif|aiff|caf|ogg)$/i.test(file.name)
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
  state.modal = 'roll';
  state.rollTrackId = trackId;
  state.selectedNote = null;
  renderRollModal();
}

function rollSnap() {
  return beatDuration() / state.rollDivision;
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
      <button class="icon-btn" id="rollDeleteBtn" ${state.selectedNote ? '' : 'disabled'}>🗑</button>
      <button class="modal-close" data-close>Done</button>
    </header>
    <div class="modal-body">
      <div class="roll">
        <div class="roll-toolbar">
          <span class="range-label">Tap the grid to add a note · drag to move · drag its right edge to resize</span>
          <div style="margin-left:auto;display:flex;gap:4px">
            <button class="pill ${state.rollDivision === 1 ? 'on' : ''}" data-roll-div="1">1/4</button>
            <button class="pill ${state.rollDivision === 2 ? 'on' : ''}" data-roll-div="2">1/8</button>
            <button class="pill ${state.rollDivision === 4 ? 'on' : ''}" data-roll-div="4">1/16</button>
          </div>
        </div>
        <div class="roll-grid-wrap">
          <div class="roll-keys">${keys.join('')}</div>
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

  track.notes.forEach((note) => {
    grid.appendChild(buildRollNote(track, note, beatPx));
  });

  document.getElementById('rollPlayBtn').addEventListener('click', () => {
    togglePlay();
    const button = document.getElementById('rollPlayBtn');
    if (button) button.textContent = engine.isPlaying ? '❚❚' : '▶';
  });

  document.getElementById('rollDeleteBtn').addEventListener('click', () => {
    if (!state.selectedNote) return;
    snapshot();
    track.notes = track.notes.filter((note) => note.id !== state.selectedNote);
    state.selectedNote = null;
    persist();
    engine.rebuild();
    renderRollModal();
  });

  document.querySelectorAll('[data-roll-div]').forEach((button) => {
    button.addEventListener('click', () => {
      state.rollDivision = Number(button.dataset.rollDiv);
      renderRollModal();
    });
  });

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
      const note = { id: model.uid(), pitch, start: length, duration: rollSnap() };
      track.notes.push(note);
      track.notes.sort((a, b) => a.start - b.start);
      state.selectedNote = note.id;
      persist();
      engine.rebuild();
      renderRollModal();
      return;
    }

    const note = track.notes.find((item) => item.id === noteEl.dataset.note);
    if (!note) return;
    state.selectedNote = note.id;
    grid.querySelectorAll('.roll-note').forEach((element) => {
      element.classList.toggle('selected', element.dataset.note === note.id);
    });

    const isResize = event.target.classList.contains('resize');
    const startX = event.clientX;
    const startY = event.clientY;
    const origin = { ...note };
    snapshot();

    startDrag((moveEvent) => {
      const dx = moveEvent.clientX - startX;
      const dy = moveEvent.clientY - startY;
      if (isResize) {
        note.duration = Math.max(rollSnap(), origin.duration + dx / (beatPx / beatDuration()));
        note.duration = Math.round(note.duration / rollSnap()) * rollSnap();
      } else {
        const time = origin.start + dx / (beatPx / beatDuration());
        note.start = Math.max(0, Math.round(time / rollSnap()) * rollSnap());
        const pitchDelta = -Math.round(dy / NOTE_HEIGHT);
        note.pitch = model.clamp(origin.pitch + pitchDelta, model.NOTE_LOW, model.NOTE_HIGH);
      }
      positionRollNote(noteEl, note, beatPx);
    }, () => {
      track.notes.sort((a, b) => a.start - b.start);
      persist();
      engine.rebuild();
      renderRollModal();
    });
  });
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
  element.className = `roll-note ${state.selectedNote === note.id ? 'selected' : ''}`;
  element.dataset.note = note.id;
  element.innerHTML = `${model.noteName(note.pitch)}<span class="resize"></span>`;
  positionRollNote(element, note, beatPx);
  return element;
}

function positionRollNote(element, note, beatPx) {
  const pps = beatPx / beatDuration();
  element.style.left = `${Math.max(0, note.start) * pps}px`;
  element.style.top = `${(model.NOTE_HIGH - note.pitch) * NOTE_HEIGHT + 1.5}px`;
  element.style.width = `${Math.max(14, note.duration * pps)}px`;
}

// ---------- Modal shells ----------

function openModal(html, { tall = false } = {}) {
  el.modalRoot.innerHTML = `<div class="modal-backdrop"></div><section class="modal ${tall ? 'tall' : ''}">${html}</section>`;
  el.modalRoot.querySelector('.modal-backdrop').addEventListener('click', closeModal);
  el.modalRoot.querySelectorAll('[data-close]').forEach((button) => {
    button.addEventListener('click', closeModal);
  });
  el.modalRoot.style.pointerEvents = 'auto';
}

function closeModal() {
  state.modal = null;
  el.modalRoot.innerHTML = '';
  el.modalRoot.style.pointerEvents = 'none';
}

// ---------- Mixer ----------

function openMixer() {
  const session = state.session;
  if (!session) return;
  state.modal = 'mixer';

  const strips = session.tracks.map((track, index) => {
    const color = model.trackColor(index);
    return `<div class="strip" style="--track-color:${color}">
      <div class="strip-name">${escapeHtml(track.name.toUpperCase())}</div>
      <input type="range" class="pan-slider" min="-1" max="1" step="0.05" value="${track.pan}" data-mix-pan="${track.id}" style="width:64px" aria-label="Pan for ${escapeHtml(track.name)}">
      <div class="pan-label" data-pan-label="${track.id}">${model.panLabel(track.pan)}</div>
      <div class="fader-block">
        <input type="range" class="fader" min="0" max="1" step="0.01" value="${track.volume}" data-mix-volume="${track.id}" aria-label="Volume for ${escapeHtml(track.name)}">
        <div class="meter" data-mix-meter="${track.id}"><div class="meter-fill"></div></div>
      </div>
      <div class="db" data-db-label="${track.id}">${model.dbLabel(track.volume)}</div>
      <div class="mini-row">
        <button class="mini ${track.muted ? 'on' : ''}" data-mix-mute="${track.id}">M</button>
        <button class="mini ${track.soloed ? 'on' : ''}" data-mix-solo="${track.id}">S</button>
      </div>
    </div>`;
  }).join('');

  openModal(`
    <header class="modal-header">
      <div style="flex:1;min-width:0">
        <h2>Mixer</h2>
        <div class="sub">${escapeHtml(session.name.toUpperCase())} · ${session.tracks.length} ${session.tracks.length === 1 ? 'CHANNEL' : 'CHANNELS'}</div>
      </div>
      <button class="modal-close" data-close>Done</button>
    </header>
    <div class="modal-body">
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
    </div>
    <footer class="modal-footer">
      <button class="tool" id="mixerPlayBtn">${engine.isPlaying ? 'Pause' : 'Play'}</button>
      <button class="tool" id="mixerStopBtn">Stop</button>
      <span class="range-label" style="margin-left:auto" id="mixerTime">${model.formatTime(currentPosition())}</span>
    </footer>`, { tall: true });

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

// ---------- Equalizer + compressor ----------

function openEQ(trackId) {
  const track = trackById(trackId);
  if (!track) return;
  state.modal = 'eq';

  const band = (key, title, gainRange) => `
    <div class="field">
      <div class="label-row"><span>${title} frequency</span><span data-eq-value="${key}-frequency">${Math.round(track.eq[key].frequency)} Hz</span></div>
      <input type="range" min="30" max="16000" step="10" value="${track.eq[key].frequency}" data-eq="${key}-frequency" data-track="${track.id}">
    </div>
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
      </div>
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
        <div class="field">
          <div class="label-row"><span>Decay</span><span data-fx-value="reverbDecay">${fx.reverbDecay.toFixed(1)} s</span></div>
          <input type="range" min="0.2" max="5" step="0.1" value="${fx.reverbDecay}" data-fx="reverbDecay">
        </div>
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
        <div class="field">
          <div class="label-row"><span>Feedback</span><span data-fx-value="delayFeedback">${Math.round(fx.delayFeedback * 100)}%</span></div>
          <input type="range" min="0" max="0.9" step="0.01" value="${fx.delayFeedback}" data-fx="delayFeedback">
        </div>
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

// ---------- Sessions ----------

function openSessions() {
  state.modal = 'sessions';
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
        <button class="icon-btn" data-session-delete="${session.id}" title="Delete">🗑</button>
      </div>
    </div>`;
  }).join('');

  openModal(`
    <header class="modal-header">
      <h2>Sessions</h2>
      <button class="modal-close" data-close>Done</button>
    </header>
    <div class="modal-body"><div class="list">${rows}</div></div>
    <footer class="modal-footer">
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
      copy.tracks = copy.tracks.map((track) => ({
        ...track,
        id: model.uid(),
        clips: track.clips.map((clip) => ({ ...clip, id: model.uid() })),
        notes: track.notes.map((note) => ({ ...note, id: model.uid() }))
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
  el.addTrackBtn.addEventListener('click', () => el.fileInput.click());
  el.emptyImportBtn.addEventListener('click', () => el.fileInput.click());
  el.fileInput.addEventListener('change', () => {
    importFiles(el.fileInput.files);
    el.fileInput.value = '';
  });
  el.blankTrackBtn.addEventListener('click', addBlankTrack);
  el.bounceBtn.addEventListener('click', bounceMix);

  el.undoBtn.addEventListener('click', undo);
  el.redoBtn.addEventListener('click', redo);
  el.mixerBtn.addEventListener('click', openMixer);
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
      case 'automation': toggleAutomation(trackId); break;
      case 'automation-pan': toggleAutomation(trackId, 'pan'); break;
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

// ---------- Boot ----------

function render() {
  renderHeader();
  renderTimeline();
  renderTransport();
}

function boot() {
  const stored = state.store.sessions.find((session) => session.id === state.store.activeId) || state.store.sessions[0];
  state.session = model.normalizeSession(stored);
  const index = state.store.sessions.findIndex((session) => session.id === state.session.id);
  if (index >= 0) state.store.sessions[index] = state.session;
  else state.store.sessions.push(state.session);
  state.store.activeId = state.session.id;
  engine.setSession(state.session);
  ensureClipToolbar();
  state.presets = loadPresets();
  bindEvents();
  render();
  requestAnimationFrame(frame);

  preloadAudio().then(() => {
    engine.rebuild();
    render();
  });
}

boot();
