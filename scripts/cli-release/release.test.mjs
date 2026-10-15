import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { catalog } from "./catalog.mjs";
import { checkElf, lock, sha256, validateRelease } from "./prepare.mjs";

function elf(machine) {
  const bytes = Buffer.alloc(64);
  bytes.set([0x7f, 69, 76, 70, 2, 1]);
  bytes.writeUInt16LE(2, 16);
  bytes.writeUInt16LE(machine, 18);
  return bytes;
}

test("release catalog requires matching complete assets for both architectures", async t => {
  const directory = await mkdtemp(join(tmpdir(), "openseek-catalog-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const id = "cli-v1.2.3";
  for (const [platform, machine] of [["linux-x64", 62], ["linux-arm64", 183]]) {
    const archive = `openseek-runtime-${platform}.tar.gz`;
    await writeFile(join(directory, archive), `runtime for ${platform}`);
    await writeFile(join(directory, `openseek-${platform}`), elf(machine));
    await writeFile(join(directory, `runtime-${platform}.json`), JSON.stringify({ id, platform, moonbit_version: lock.moonbit_version,
      url: `https://github.com/moonbitlang/openseek/releases/download/${id}/${archive}`, sha256: await sha256(join(directory, archive)) }));
  }
  const result = await catalog(directory, id);
  assert.deepEqual(Object.keys(result.platforms), ["linux-x64", "linux-arm64"]);
  assert.equal(result.platforms["linux-x64"].sha256, await sha256(join(directory, "openseek-linux-x64")));
  assert.equal((await readFile(join(directory, "SHA256SUMS"), "utf8")).trim().split("\n").length, 4);
  await writeFile(join(directory, "openseek-runtime-linux-arm64.tar.gz"), "truncated upload");
  await assert.rejects(catalog(directory, id), /Mismatched runtime/);
  await rm(join(directory, "openseek-linux-x64"));
  await assert.rejects(catalog(directory, id), /ENOENT/);
});

test("release preparation rejects wrong-architecture executables and ambiguous identities", () => {
  checkElf(elf(62), "linux-x64");
  checkElf(elf(183), "linux-arm64");
  assert.throws(() => checkElf(elf(62), "linux-arm64"), /ELF/);
  assert.throws(() => checkElf(Buffer.from("#!/bin/sh"), "linux-x64"), /ELF/);
  validateRelease("cli-v1.2.3", "linux-x64", "https://example.com/releases/cli-v1.2.3");
  for (const id of ["latest", "../cli-v1.2.3", "cli-v1.2.3/file"]) assert.throws(() => validateRelease(id, "linux-x64", "https://example.com"));
  for (const url of ["http://example.com", "https://user:password@example.com", "https://example.com/?latest=1"]) {
    assert.throws(() => validateRelease("cli-v1.2.3", "linux-x64", url));
  }
});
