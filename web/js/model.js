// Shared model + storage helpers for the web studio.

export const NOTE_LOW = 48;
export const NOTE_HIGH = 71;
export const MIN_LOOP = 0.2;
export const TRACK_COLORS = ['#fa9f2d', '#2aa89a', '#5c8fed', '#cc6bc7'];

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

export function createTrack({ name, fileId = null, duration = 0, index = 0 }) {
  const track = {
    id: uid(),
    name: name || `Track ${index + 1}`,
    colorIndex: index,
    volume: 1,
    pan: 0,
    muted: false,
    soloed: false,
    eq: defaultEQ(),
    comp: defaultCompressor(),
    automation: [],
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
  return {
    id: uid(),
    name,
    tempo: 120,
    masterVolume: 1,
    loop: { start: 0, end: 0, enabled: false },
    metronome: { enabled: false, level: 0.7, countIn: false },
    tracks: [],
    editedAt: Date.now()
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

export function sequencedNotes(track) {
  return track.frozen && track.frozen.fileId ? [] : track.notes;
}

export function trackDuration(track) {
  let end = 0;
  for (const clip of playbackClips(track)) {
    const playable = Math.min(clip.duration, Math.max(0, clip.sourceDuration - clip.sourceStart));
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
    end = Math.max(end, trackDuration(track));
  }
  return end;
}

export function hasLoopRange(session) {
  return session.loop.end - session.loop.start > 0.01;
}

export function automationGain(track, time) {
  const points = [...(track.automation || [])].sort((a, b) => a.time - b.time);
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

export function normalizeSession(session) {
  const normal = session || createSession();
  normal.id = normal.id || uid();
  normal.name = normal.name || 'Untitled Session';
  normal.tempo = clamp(Number(normal.tempo) || 120, 60, 200);
  normal.masterVolume = clamp(Number(normal.masterVolume ?? 1), 0, 1);
  normal.loop = normal.loop || { start: 0, end: 0, enabled: false };
  normal.loop.start = Math.max(0, Number(normal.loop.start) || 0);
  normal.loop.end = Math.max(normal.loop.start, Number(normal.loop.end) || 0);
  normal.loop.enabled = Boolean(normal.loop.enabled);
  normal.metronome = normal.metronome || { enabled: false, level: 0.7, countIn: false };
  normal.metronome.level = clamp(Number(normal.metronome.level ?? 0.7), 0, 1);
  normal.metronome.enabled = Boolean(normal.metronome.enabled);
  normal.metronome.countIn = Boolean(normal.metronome.countIn);
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
    track.eq = track.eq || defaultEQ();
    track.eq.bypassed = Boolean(track.eq.bypassed);
    track.eq.low = track.eq.low || { frequency: 120, gain: 0 };
    track.eq.mid = track.eq.mid || { frequency: 1000, gain: 0 };
    track.eq.high = track.eq.high || { frequency: 8000, gain: 0 };
    track.comp = track.comp || defaultCompressor();
    track.comp.bypassed = track.comp.bypassed !== false;
    track.automation = Array.isArray(track.automation) ? track.automation : [];
    track.clips = Array.isArray(track.clips) ? track.clips : [];
    track.notes = Array.isArray(track.notes) ? track.notes : [];
    track.frozen = track.frozen || { fileId: null, duration: 0 };
    track.frozen.fileId = track.frozen.fileId || null;
    track.frozen.duration = Math.max(0, Number(track.frozen.duration) || 0);
  });

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
        return { sessions, activeId };
      }
    }
  } catch (error) {
    console.warn('Could not read saved sessions', error);
  }

  const session = createSession();
  return { sessions: [session], activeId: session.id };
}

export function saveStore(store) {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify({ sessions: store.sessions, activeId: store.activeId }));
  } catch (error) {
    console.warn('Could not save sessions', error);
  }
}

// ---------- Audio file storage (IndexedDB) ----------

const DB_NAME = 'ai-studio.web.audio';
const DB_STORE = 'files';
let dbPromise = null;

function openDb() {
  if (!dbPromise) {
    dbPromise = new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, 1);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains(DB_STORE)) {
          db.createObjectStore(DB_STORE);
        }
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }
  return dbPromise;
}

async function withStore(mode, action) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(DB_STORE, mode);
    const store = transaction.objectStore(DB_STORE);
    const request = action(store);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
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
