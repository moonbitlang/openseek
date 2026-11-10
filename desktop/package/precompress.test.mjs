import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { brotliDecompressSync, gunzipSync } from "node:zlib";
import { precompress } from "./precompress.mjs";

test("encodings decode to the original and skip files that would not shrink", async () => {
  const dir = await mkdtemp(join(tmpdir(), "openseek-precompress-"));
  try {
    await mkdir(join(dir, "assets/fonts"), { recursive: true });
    const script = Buffer.from("console.log('SeekMoon');\n".repeat(400));
    await writeFile(join(dir, "assets/frontend.js"), script);
    await writeFile(join(dir, "assets/fonts/random.ttf"), randomBytes(4096));
    await writeFile(join(dir, "assets/tiny.css"), "a{}");
    await writeFile(join(dir, "assets/icon.png"), script);

    assert.deepEqual(await precompress(dir), [join(dir, "assets/frontend.js")]);
    assert.deepEqual(brotliDecompressSync(await readFile(join(dir, "assets/frontend.js.br"))), script);
    assert.deepEqual(gunzipSync(await readFile(join(dir, "assets/frontend.js.gz"))), script);
    for (const skipped of ["assets/fonts/random.ttf", "assets/tiny.css", "assets/icon.png"]) {
      await assert.rejects(readFile(join(dir, skipped + ".br")), { code: "ENOENT" });
      await assert.rejects(readFile(join(dir, skipped + ".gz")), { code: "ENOENT" });
    }
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
