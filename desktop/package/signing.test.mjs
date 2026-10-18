import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { assertMacosSigningCoverage } from "./signing.mjs";

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "openseek-signing-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, "seekmoon"));
  return root;
}

async function resource(root, path, bytes) {
  const file = join(root, path);
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, bytes, { mode: 0o644 });
}

function fat(slices, { bits, littleEndian }) {
  const entrySize = bits === 64 ? 32 : 20;
  const header = Buffer.alloc(8 + slices.length * entrySize);
  header.writeUInt32BE(bits === 64
    ? (littleEndian ? 0xbfbafeca : 0xcafebabf)
    : (littleEndian ? 0xbebafeca : 0xcafebabe));
  const write32 = (value, offset) => littleEndian
    ? header.writeUInt32LE(value, offset) : header.writeUInt32BE(value, offset);
  const write64 = (value, offset) => littleEndian
    ? header.writeBigUInt64LE(BigInt(value), offset) : header.writeBigUInt64BE(BigInt(value), offset);
  write32(slices.length, 4);
  let position = header.length;
  slices.forEach((slice, index) => {
    const entry = 8 + index * entrySize;
    write32(0x0100000c, entry);
    if (bits === 64) {
      write64(position, entry + 8);
      write64(slice.length, entry + 16);
    } else {
      write32(position, entry + 8);
      write32(slice.length, entry + 12);
    }
    position += slice.length;
  });
  return Buffer.concat([header, ...slices]);
}

test("a newly bundled native command must be listed before macOS signing", async t => {
  const root = await fixture(t);
  const command = "seekmoon/toolchains/moonbit/macos-arm64/bin/new-command";
  await resource(root, command, Buffer.from(
    "cffaedfe0c000001000000000200000000000000000000000000000000000000",
    "hex",
  ));
  await assert.rejects(assertMacosSigningCoverage(root, []), error => {
    assert.ok(error.message.includes(command), error.message);
    return true;
  });
  await assertMacosSigningCoverage(root, [command]);
});

test("signing coverage reports every executable, library, and bundle while ignoring documents and objects", async t => {
  const root = await fixture(t);
  const files = {
    "seekmoon/bin/big-endian-32": "feedface0000000c0000000000000002000000000000000000000000",
    "seekmoon/lib/big-endian-64.dylib": "feedfacf0100000c000000000000000600000000000000000000000000000000",
    "seekmoon/lib/little-endian-32.bundle": "cefaedfe0c0000000000000008000000000000000000000000000000",
    "seekmoon/lib/little-endian-64.dylib": "cffaedfe0c000001000000000600000000000000000000000000000000000000",
  };
  for (const [path, bytes] of Object.entries(files)) await resource(root, path, Buffer.from(bytes, "hex"));
  await resource(root, "seekmoon/doc/readme.md", "Bundled documentation");
  await resource(root, "seekmoon/lib/runtime.o", Buffer.from(
    "cffaedfe0c000001000000000100000000000000000000000000000000000000", "hex",
  ));
  await assert.rejects(assertMacosSigningCoverage(root, []), error => {
    assert.deepEqual(error.message.split("\n").slice(1), Object.keys(files));
    return true;
  });
  await assertMacosSigningCoverage(root, Object.keys(files));
});

for (const bits of [32, 64]) {
  for (const littleEndian of [false, true]) {
    test(`${bits}-bit ${littleEndian ? "little" : "big"}-endian universal code checks every slice`, async t => {
      const root = await fixture(t);
      const object = Buffer.from(
        "cffaedfe0c000001000000000100000000000000000000000000000000000000", "hex",
      );
      const library = Buffer.from(
        "feedfacf0100000c000000000000000600000000000000000000000000000000", "hex",
      );
      const path = "seekmoon/lib/universal-plugin.cmxs";
      await resource(root, path, fat([object, library], { bits, littleEndian }));
      await resource(root, "seekmoon/lib/universal-runtime.o", fat([object, object], { bits, littleEndian }));
      await assert.rejects(assertMacosSigningCoverage(root, []), error => {
        assert.deepEqual(error.message.split("\n").slice(1), [path]);
        return true;
      });
      await assertMacosSigningCoverage(root, [path]);
    });
  }
}
