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
