import { createWriteStream } from "node:fs";
import { mkdir, mkdtemp, readFile, rename, rm } from "node:fs/promises";
import { join, resolve } from "node:path";
import { Readable, Transform } from "node:stream";
import { pipeline } from "node:stream/promises";
import { parseArgs } from "node:util";
import { sha256 } from "./manifest.mjs";

const lock = JSON.parse(await readFile(new URL("./vendors.json", import.meta.url), "utf8"));
const { values } = parseArgs({ options: { platform: { type: "string" }, output: { type: "string" } } });
if (!Object.hasOwn(lock.platforms, values.platform) || !values.output) throw new Error("Specify --platform linux-x64|linux-arm64 and --output vendor-cache");
const output = resolve(values.output);
await mkdir(output, { recursive: true });
const target = lock.platforms[values.platform];
for (const vendor of [target.sdk, lock.core, target.ripgrep]) {
  const destination = join(output, vendor.file);
  try {
    if (await sha256(destination) !== vendor.sha256) throw new Error(`Cached vendor checksum mismatch: ${destination}`);
    console.log(`Reused ${vendor.file}`);
    continue;
  } catch (error) { if (error.code !== "ENOENT") throw error; }
  const temporary = await mkdtemp(join(output, ".download-"));
  try {
    const response = await fetch(vendor.url, { signal: AbortSignal.timeout(180000) });
    if (!response.ok || !response.body) throw new Error(`Vendor download returned HTTP ${response.status}`);
    let bytes = 0;
    const limit = new Transform({ transform(chunk, _encoding, done) {
      bytes += chunk.length;
      done(bytes > 512 * 1024 ** 2 ? new Error("Vendor download size limit exceeded") : null, chunk);
    } });
    const path = join(temporary, "archive");
    await pipeline(Readable.fromWeb(response.body), limit, createWriteStream(path, { flags: "wx", mode: 0o644 }));
    if (await sha256(path) !== vendor.sha256) throw new Error(`Downloaded vendor checksum mismatch: ${vendor.file}`);
    await rename(path, destination);
    console.log(`Verified ${vendor.file}`);
  } finally { await rm(temporary, { recursive: true, force: true }); }
}
