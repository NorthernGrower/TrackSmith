const API_BASE = 'https://api.audioshake.ai';
const MAX_UPLOAD_BYTES = 5 * 1024 * 1024 * 1024;

export const STEM_TARGETS = [
  { id: 'vocals', name: 'Vocals', hint: 'Lead and backing voices' },
  { id: 'drums', name: 'Drums', hint: 'Percussion and kit' },
  { id: 'bass', name: 'Bass', hint: 'Low-end instruments' },
  { id: 'guitar', name: 'Guitar', hint: 'Electric and acoustic' },
  { id: 'keys', name: 'Keys', hint: 'Keyboard instruments' },
  { id: 'residual', name: 'Residual', hint: 'Remaining sound' },
  { id: 'piano', name: 'Piano', hint: 'Piano parts' },
  { id: 'strings', name: 'Strings', hint: 'String instruments' },
  { id: 'wind', name: 'Wind', hint: 'Wind instruments' },
  { id: 'drum_kit', name: 'Drum Kit', hint: 'Individual kit parts when available' }
];

export const DEFAULT_STEM_TARGETS = ['vocals', 'drums', 'bass', 'guitar', 'keys', 'residual'];

function responseMessage(responseText, fallback) {
  try {
    const body = JSON.parse(responseText);
    const candidate = body.message || body.detail || (typeof body.error === 'string' ? body.error : body.error?.message);
    return typeof candidate === 'string' ? candidate : fallback;
  } catch (error) {
    return responseText || fallback;
  }
}

function xhrRequest(url, {
  method = 'GET',
  apiKey,
  body,
  contentType,
  responseType,
  timeout = 60000,
  signal,
  onUploadProgress
} = {}) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    let settled = false;
    const finish = (callback, value) => {
      if (settled) return;
      settled = true;
      if (signal) signal.removeEventListener('abort', abortRequest);
      callback(value);
    };
    const abortRequest = () => xhr.abort();

    if (signal?.aborted) {
      reject(new DOMException('The operation was aborted.', 'AbortError'));
      return;
    }

    xhr.open(method, url, true);
    xhr.timeout = timeout;
    if (apiKey) xhr.setRequestHeader('x-api-key', apiKey);
    if (contentType) xhr.setRequestHeader('Content-Type', contentType);
    if (responseType) xhr.responseType = responseType;
    if (onUploadProgress && xhr.upload) {
      xhr.upload.addEventListener('progress', (event) => {
        if (event.lengthComputable) onUploadProgress(event.loaded / event.total);
      });
    }
    if (signal) signal.addEventListener('abort', abortRequest, { once: true });

    xhr.onload = () => {
      const text = responseType === 'arraybuffer'
        ? new TextDecoder().decode(xhr.response || new ArrayBuffer(0))
        : xhr.responseText;
      if (xhr.status >= 200 && xhr.status < 300) {
        finish(resolve, responseType === 'arraybuffer' ? xhr.response : text);
      } else {
        finish(reject, new Error(responseMessage(text, `AudioShake request failed (HTTP ${xhr.status}). Check your API key and credits.`)));
      }
    };
    xhr.onerror = () => finish(reject, new Error(
      'The browser could not reach AudioShake. Check your connection and whether AudioShake allows requests from this site (CORS).'
    ));
    xhr.ontimeout = () => finish(reject, new Error('AudioShake request timed out. Please try again.'));
    xhr.onabort = () => finish(reject, new DOMException('The operation was aborted.', 'AbortError'));
    xhr.send(body ?? null);
  });
}

function mimeTypeFor(file) {
  const extension = file.name.split('.').pop()?.toLowerCase();
  const knownType = ({
    wav: 'audio/wav',
    mp3: 'audio/mpeg',
    m4a: 'audio/mp4',
    aac: 'audio/aac',
    aif: 'audio/aiff',
    aiff: 'audio/aiff',
    flac: 'audio/flac'
  })[extension];
  return knownType || (file.type && file.type.startsWith('audio/') ? file.type : '');
}

function delay(milliseconds, signal) {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new DOMException('The operation was aborted.', 'AbortError'));
      return;
    }
    const timer = window.setTimeout(() => {
      if (signal) signal.removeEventListener('abort', abortDelay);
      resolve();
    }, milliseconds);
    const abortDelay = () => {
      window.clearTimeout(timer);
      signal.removeEventListener('abort', abortDelay);
      reject(new DOMException('The operation was aborted.', 'AbortError'));
    };
    if (signal) signal.addEventListener('abort', abortDelay, { once: true });
  });
}

function stemName(model, outputName) {
  const fixedNames = {
    vocals_lead: 'Lead Vocals',
    vocals_backing: 'Backing Vocals',
    guitar_electric: 'Electric Guitar',
    guitar_acoustic: 'Acoustic Guitar',
    drum_kit: 'Drum Kit',
    residual: 'Residual'
  };
  if (model !== 'drum_kit' || !outputName) return fixedNames[model] || model.replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
  const base = outputName.split('/').pop().replace(/\.[^.]+$/, '').toLowerCase();
  const parts = ['kick', 'snare', 'toms', 'hi-hat', 'hihat', 'cymbals', 'percussion'];
  const part = parts.find((name) => base.includes(name));
  return part ? part.replace(/^hihat$/, 'hi-hat').replace(/\b\w/g, (letter) => letter.toUpperCase()) : (base || 'Drum Kit').replace(/\b\w/g, (letter) => letter.toUpperCase());
}

export async function separateWithAudioShake(file, targets, apiKey, { signal, onProgress = () => {} } = {}) {
  if (!file) throw new Error('Choose a song first.');
  if (!apiKey) throw new Error('Enter your AudioShake API key to use AI separation.');
  if (!targets.length) throw new Error('Choose at least one stem to separate.');
  if (file.size > MAX_UPLOAD_BYTES) throw new Error('AudioShake accepts files up to 5 GB.');
  const mimeType = mimeTypeFor(file);
  if (!mimeType) throw new Error('This audio format is not supported. Try WAV, MP3, M4A, AIFF, AAC, or FLAC.');

  onProgress('Uploading song to AudioShake…', 0.02);
  const uploadFile = file.type === mimeType ? file : new File([file], file.name, { type: mimeType });
  const formData = new FormData();
  formData.append('file', uploadFile, file.name);
  const assetText = await xhrRequest(`${API_BASE}/assets`, {
    method: 'POST',
    apiKey,
    body: formData,
    timeout: 60 * 60 * 1000,
    signal,
    onUploadProgress: (fraction) => onProgress('Uploading song to AudioShake…', 0.02 + 0.10 * fraction)
  });
  let asset;
  try {
    asset = JSON.parse(assetText);
  } catch (error) {
    throw new Error('AudioShake returned an unexpected upload response.');
  }
  if (!asset.id) throw new Error('AudioShake did not return an uploaded asset ID.');

  onProgress('Starting AI separation…', 0.13);
  const taskText = await xhrRequest(`${API_BASE}/tasks`, {
    method: 'POST',
    apiKey,
    contentType: 'application/json',
    body: JSON.stringify({
      assetId: asset.id,
      targets: targets.map((model) => ({ model, formats: ['wav'] }))
    }),
    signal
  });
  let task;
  try {
    task = JSON.parse(taskText);
  } catch (error) {
    throw new Error('AudioShake returned an unexpected task response.');
  }
  if (!task.id) throw new Error('AudioShake did not return a task ID.');

  const startedAt = Date.now();
  const timeoutMs = 30 * 60 * 1000;
  while (!Array.isArray(task.targets) || !task.targets.length || !task.targets.every((target) => ['completed', 'error'].includes(String(target.status).toLowerCase()))) {
    if (signal?.aborted) throw new DOMException('The operation was aborted.', 'AbortError');
    if (Date.now() - startedAt >= timeoutMs) throw new Error('AudioShake is taking longer than expected. Reopen separation and try again.');
    const finished = (task.targets || []).filter((target) => ['completed', 'error'].includes(String(target.status).toLowerCase())).length;
    onProgress(`AI separating · ${finished} of ${targets.length} stems…`, 0.15 + 0.62 * finished / targets.length);
    await delay(5000, signal);
    const statusText = await xhrRequest(`${API_BASE}/tasks/${encodeURIComponent(task.id)}`, { apiKey, signal });
    try {
      task = JSON.parse(statusText);
    } catch (error) {
      throw new Error('AudioShake returned an unexpected task status response.');
    }
  }

  const stems = [];
  const failures = [];
  const outputCount = Math.max(1, task.targets.reduce((count, target) => count + (target.output || []).length, 0));
  let downloaded = 0;
  for (const target of task.targets) {
    const baseName = stemName(target.model, null);
    if (String(target.status).toLowerCase() !== 'completed') {
      const detail = typeof target.error === 'string' ? target.error : target.error?.message;
      failures.push(`${baseName}: ${detail || 'Separation failed'}`);
      continue;
    }
    if (!Array.isArray(target.output) || !target.output.length) {
      failures.push(`${baseName}: AudioShake returned no output file`);
      continue;
    }
    for (const output of target.output) {
      try {
        if (!output.link || !output.link.startsWith('https://')) throw new Error('AudioShake returned an invalid download link.');
        const data = await xhrRequest(output.link, { responseType: 'arraybuffer', timeout: 10 * 60 * 1000, signal });
        const name = stemName(target.model, output.name);
        stems.push({ name, fileName: `${name}.wav`, data });
      } catch (error) {
        if (error.name === 'AbortError') throw error;
        const detail = error.message.includes('could not reach AudioShake')
          ? 'The browser could not download this temporary output link (possibly a CORS restriction).'
          : error.message;
        failures.push(`${baseName}: ${detail}`);
      }
      downloaded += 1;
      onProgress(`Downloading stems · ${downloaded} of ${outputCount}…`, 0.78 + 0.20 * downloaded / outputCount);
    }
  }
  if (!stems.length) throw new Error(failures.join('\n') || 'AudioShake did not return any stems.');
  onProgress('Stems ready.', 1);
  return { stems, failures };
}

const OFFLINE_BANDS = [
  { name: 'Vocals', stages: [['highpass', 150, 2], ['lowpass', 2500, 2]] },
  { name: 'Drums', stages: [['highpass', 150, 2], ['highpass', 2500, 2], ['lowpass', 9000, 2]] },
  { name: 'Bass', stages: [['lowpass', 150, 2]] },
  { name: 'Other', stages: [['highpass', 150, 2], ['highpass', 2500, 2], ['highpass', 9000, 2]] }
];

export async function renderOfflineBandSplit(inputBuffer, onProgress = () => {}) {
  const OfflineContext = window.OfflineAudioContext || window.webkitOfflineAudioContext;
  if (!OfflineContext) throw new Error('Offline audio processing is not supported in this browser.');
  const results = [];
  for (let index = 0; index < OFFLINE_BANDS.length; index += 1) {
    const band = OFFLINE_BANDS[index];
    onProgress(`Splitting locally · ${band.name}`, index / OFFLINE_BANDS.length);
    const context = new OfflineContext(inputBuffer.numberOfChannels, inputBuffer.length, inputBuffer.sampleRate);
    const source = context.createBufferSource();
    source.buffer = inputBuffer;
    let previous = source;
    for (const [type, frequency, count] of band.stages) {
      for (let stage = 0; stage < count; stage += 1) {
        const filter = context.createBiquadFilter();
        filter.type = type;
        filter.frequency.value = frequency;
        filter.Q.value = 0.70710678;
        previous.connect(filter);
        previous = filter;
      }
    }
    previous.connect(context.destination);
    source.start(0);
    const buffer = await context.startRendering();
    results.push({ name: band.name, fileName: `${band.name}.wav`, buffer });
  }
  onProgress('Offline band split ready.', 1);
  return results;
}
