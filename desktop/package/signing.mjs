import { open, readdir } from "node:fs/promises";
import { join } from "node:path";

function isThinCode(header) {
  if (header.length < 16) return false;
  const magic = header.readUInt32BE(0);
  // MH_EXECUTE, MH_DYLIB, and MH_BUNDLE carry loadable code. MH_OBJECT
  // files are compiler/linker inputs and do not need a code signature.
  if (magic === 0xcffaedfe || magic === 0xcefaedfe) {
    return [2, 6, 8].includes(header.readUInt32LE(12));
  }
  if (magic === 0xfeedfacf || magic === 0xfeedface) {
    return [2, 6, 8].includes(header.readUInt32BE(12));
  }
  return false;
}

async function requiresSigning(file) {
  const handle = await open(file, "r");
  try {
    async function read(position, length) {
      const bytes = Buffer.alloc(length);
      const { bytesRead } = await handle.read(bytes, 0, length, position);
      return bytes.subarray(0, bytesRead);
    }
    const header = await read(0, 16);
    if (header.length < 4) return false;
    const magic = header.readUInt32BE(0);
    if (![0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca].includes(magic)) {
      return isThinCode(header);
    }
    const littleEndian = magic === 0xbebafeca || magic === 0xbfbafeca;
    const fat64 = magic === 0xcafebabf || magic === 0xbfbafeca;
    const read32 = (bytes, offset) => littleEndian
      ? bytes.readUInt32LE(offset) : bytes.readUInt32BE(offset);
    const entrySize = fat64 ? 32 : 20;
    const entries = await read(8, read32(header, 4) * entrySize);
    for (let entry = 0; entry < entries.length; entry += entrySize) {
      const offset = fat64
        ? Number(littleEndian ? entries.readBigUInt64LE(entry + 8) : entries.readBigUInt64BE(entry + 8))
        : read32(entries, entry + 8);
      if (isThinCode(await read(offset, 16))) return true;
    }
    return false;
  } finally {
    await handle.close();
  }
}

export async function assertMacosSigningCoverage(root, binaries) {
  const signed = new Set(binaries);
  const missing = [];
  async function visit(path) {
    for (const entry of await readdir(join(root, path), { withFileTypes: true })) {
      const child = `${path}/${entry.name}`;
      if (entry.isDirectory()) await visit(child);
      else if (entry.isFile() && !signed.has(child) && await requiresSigning(join(root, child))) {
        missing.push(child);
      }
    }
  }
  await visit("seekmoon");
  if (missing.length) {
    throw new Error(`macOS signing list is missing bundled native code:\n${missing.sort().join("\n")}`);
  }
}
