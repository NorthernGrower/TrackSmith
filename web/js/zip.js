const CRC_TABLE = Array.from({ length: 256 }, (_, value) => {
  let crc = value;
  for (let bit = 0; bit < 8; bit += 1) {
    crc = (crc & 1) ? (crc >>> 1) ^ 0xEDB88320 : crc >>> 1;
  }
  return crc >>> 0;
});

function crc32Update(crc, bytes) {
  let value = crc;
  for (const byte of bytes) value = (value >>> 8) ^ CRC_TABLE[(value ^ byte) & 0xFF];
  return value >>> 0;
}

async function blobCRC32(blob) {
  let crc = 0xFFFFFFFF;
  if (typeof blob.stream === 'function') {
    const reader = blob.stream().getReader();
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        crc = crc32Update(crc, value);
      }
    } finally {
      reader.releaseLock();
    }
  } else {
    crc = crc32Update(crc, new Uint8Array(await blob.arrayBuffer()));
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

function dosTimestamp(date) {
  const year = Math.max(1980, Math.min(2107, date.getFullYear()));
  const time = (date.getHours() << 11) | (date.getMinutes() << 5) | Math.floor(date.getSeconds() / 2);
  const day = (year - 1980) << 9 | (date.getMonth() + 1) << 5 | date.getDate();
  return { time, day };
}

function localHeader(nameLength, crc, size, time, day) {
  const bytes = new Uint8Array(30);
  const view = new DataView(bytes.buffer);
  view.setUint32(0, 0x04034B50, true);
  view.setUint16(4, 20, true);
  view.setUint16(6, 0x0800, true);
  view.setUint16(8, 0, true);
  view.setUint16(10, time, true);
  view.setUint16(12, day, true);
  view.setUint32(14, crc, true);
  view.setUint32(18, size, true);
  view.setUint32(22, size, true);
  view.setUint16(26, nameLength, true);
  view.setUint16(28, 0, true);
  return bytes;
}

function centralHeader(nameLength, crc, size, time, day, localOffset) {
  const bytes = new Uint8Array(46);
  const view = new DataView(bytes.buffer);
  view.setUint32(0, 0x02014B50, true);
  view.setUint16(4, 20, true);
  view.setUint16(6, 20, true);
  view.setUint16(8, 0x0800, true);
  view.setUint16(10, 0, true);
  view.setUint16(12, time, true);
  view.setUint16(14, day, true);
  view.setUint32(16, crc, true);
  view.setUint32(20, size, true);
  view.setUint32(24, size, true);
  view.setUint16(28, nameLength, true);
  view.setUint16(30, 0, true);
  view.setUint16(32, 0, true);
  view.setUint16(34, 0, true);
  view.setUint16(36, 0, true);
  view.setUint32(38, 0, true);
  view.setUint32(42, localOffset, true);
  return bytes;
}

function endRecord(entryCount, centralSize, centralOffset) {
  const bytes = new Uint8Array(22);
  const view = new DataView(bytes.buffer);
  view.setUint32(0, 0x06054B50, true);
  view.setUint16(4, 0, true);
  view.setUint16(6, 0, true);
  view.setUint16(8, entryCount, true);
  view.setUint16(10, entryCount, true);
  view.setUint32(12, centralSize, true);
  view.setUint32(16, centralOffset, true);
  view.setUint16(20, 0, true);
  return bytes;
}

/** Creates a standards-compliant, uncompressed ZIP Blob from named Blob entries. */
export async function createZipBlob(entries) {
  if (!Array.isArray(entries) || entries.length === 0 || entries.length > 0xFFFF) {
    throw new Error('The stem archive has an unsupported number of files');
  }

  const encoder = new TextEncoder();
  const date = dosTimestamp(new Date());
  const localParts = [];
  const centralParts = [];
  let localOffset = 0;

  for (const entry of entries) {
    if (!entry?.blob || typeof entry.name !== 'string' || !entry.name) {
      throw new Error('A stem archive file is missing its name or data');
    }
    const nameBytes = encoder.encode(entry.name);
    const size = entry.blob.size;
    if (nameBytes.byteLength > 0xFFFF || size > 0xFFFFFFFF || localOffset > 0xFFFFFFFF) {
      throw new Error('The stems are too large to fit in a standard ZIP archive');
    }
    const crc = await blobCRC32(entry.blob);
    localParts.push(localHeader(nameBytes.byteLength, crc, size, date.time, date.day), nameBytes, entry.blob);
    centralParts.push(centralHeader(nameBytes.byteLength, crc, size, date.time, date.day, localOffset), nameBytes);
    localOffset += 30 + nameBytes.byteLength + size;
  }

  const centralSize = centralParts.reduce((total, part) => total + part.byteLength, 0);
  if (localOffset > 0xFFFFFFFF || centralSize > 0xFFFFFFFF) {
    throw new Error('The stems are too large to fit in a standard ZIP archive');
  }
  return new Blob([...localParts, ...centralParts, endRecord(entries.length, centralSize, localOffset)], {
    type: 'application/zip'
  });
}



/** Reads and validates a UTF-8 manifest.json from an uncompressed stem ZIP. */
export async function readZipManifest(blob) {
  if (!(blob instanceof Blob) || blob.size < 22) {
    throw new Error('Invalid ZIP archive');
  }

  const tailSize = Math.min(blob.size, 65_557);
  const tailStart = blob.size - tailSize;
  const tail = new Uint8Array(await blob.slice(tailStart).arrayBuffer());
  const tailView = new DataView(tail.buffer, tail.byteOffset, tail.byteLength);
  let endOffset = -1;

  for (let offset = tail.byteLength - 22; offset >= 0; offset -= 1) {
    if (tailView.getUint32(offset, true) !== 0x06054B50) continue;
    const commentLength = tailView.getUint16(offset + 20, true);
    if (offset + 22 + commentLength <= tail.byteLength) {
      endOffset = offset;
      break;
    }
  }
  if (endOffset < 0) throw new Error('ZIP end record not found');

  const diskNumber = tailView.getUint16(endOffset + 4, true);
  const directoryDisk = tailView.getUint16(endOffset + 6, true);
  const diskEntryCount = tailView.getUint16(endOffset + 8, true);
  const entryCount = tailView.getUint16(endOffset + 10, true);
  const directorySize = tailView.getUint32(endOffset + 12, true);
  const directoryOffset = tailView.getUint32(endOffset + 16, true);
  const endRecordAbsoluteOffset = tailStart + endOffset;

  if (diskNumber !== 0 || directoryDisk !== 0 || diskEntryCount !== entryCount) {
    throw new Error('Multi-disk ZIP archives are not supported');
  }
  if (directorySize > 16 * 1024 * 1024
      || directoryOffset + directorySize > endRecordAbsoluteOffset) {
    throw new Error('Invalid ZIP directory');
  }

  const directory = new Uint8Array(
    await blob.slice(directoryOffset, directoryOffset + directorySize).arrayBuffer()
  );
  const view = new DataView(directory.buffer, directory.byteOffset, directory.byteLength);
  const decoder = new TextDecoder();
  let cursor = 0;
  let manifestEntry = null;

  for (let index = 0; index < entryCount; index += 1) {
    if (cursor + 46 > directory.byteLength || view.getUint32(cursor, true) !== 0x02014B50) {
      throw new Error('Invalid ZIP directory entry');
    }
    const compression = view.getUint16(cursor + 10, true);
    const checksum = view.getUint32(cursor + 16, true);
    const compressedSize = view.getUint32(cursor + 20, true);
    const uncompressedSize = view.getUint32(cursor + 24, true);
    const nameLength = view.getUint16(cursor + 28, true);
    const extraLength = view.getUint16(cursor + 30, true);
    const commentLength = view.getUint16(cursor + 32, true);
    const localOffset = view.getUint32(cursor + 42, true);
    const recordEnd = cursor + 46 + nameLength + extraLength + commentLength;
    if (recordEnd > directory.byteLength) throw new Error('Invalid ZIP directory entry');

    const name = decoder.decode(directory.subarray(cursor + 46, cursor + 46 + nameLength));
    if (name === 'manifest.json') {
      manifestEntry = { compression, checksum, compressedSize, uncompressedSize, localOffset, name };
      break;
    }
    cursor = recordEnd;
  }

  if (!manifestEntry) throw new Error('Stem manifest not found');
  if (manifestEntry.compression !== 0 || manifestEntry.compressedSize !== manifestEntry.uncompressedSize) {
    throw new Error('Stem manifest uses unsupported compression');
  }
  if (manifestEntry.uncompressedSize > 1024 * 1024) throw new Error('Stem manifest is too large');

  const localHeader = new Uint8Array(
    await blob.slice(manifestEntry.localOffset, manifestEntry.localOffset + 30).arrayBuffer()
  );
  if (localHeader.byteLength !== 30) throw new Error('Invalid stem manifest header');
  const localView = new DataView(localHeader.buffer, localHeader.byteOffset, localHeader.byteLength);
  if (localView.getUint32(0, true) !== 0x04034B50 || localView.getUint16(8, true) !== 0) {
    throw new Error('Invalid stem manifest header');
  }
  const localNameLength = localView.getUint16(26, true);
  const localExtraLength = localView.getUint16(28, true);
  const dataOffset = manifestEntry.localOffset + 30 + localNameLength + localExtraLength;
  const dataEnd = dataOffset + manifestEntry.compressedSize;
  if (dataEnd > directoryOffset || dataEnd > blob.size) throw new Error('Invalid stem manifest data');

  const localName = decoder.decode(
    new Uint8Array(await blob.slice(manifestEntry.localOffset + 30, manifestEntry.localOffset + 30 + localNameLength).arrayBuffer())
  );
  if (localName !== manifestEntry.name) throw new Error('Invalid stem manifest name');
  const bytes = new Uint8Array(await blob.slice(dataOffset, dataEnd).arrayBuffer());
  const checksum = (crc32Update(0xFFFFFFFF, bytes) ^ 0xFFFFFFFF) >>> 0;
  if (checksum !== manifestEntry.checksum) throw new Error('Stem manifest checksum mismatch');

  let manifest;
  try {
    manifest = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  } catch {
    throw new Error('Stem manifest is not valid JSON');
  }
  if (!manifest
      || typeof manifest.sessionName !== 'string'
      || !Number.isFinite(manifest.sessionTempoBPM)
      || !Array.isArray(manifest.stems)
      || manifest.stems.some((stem) => !stem
        || typeof stem.trackName !== 'string'
        || !Number.isFinite(stem.duration)
        || typeof stem.format !== 'string')) {
    throw new Error('Stem manifest is missing required details');
  }

  return manifest;
}
