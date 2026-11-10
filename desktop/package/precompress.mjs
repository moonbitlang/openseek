// Writes Brotli and gzip copies beside a browser release's assets, so
// openseek-api can answer Accept-Encoding without compressing on each request.
// frontend.js alone is tens of megabytes; Brotli's best quality takes tens of
// seconds for it, which suits a release build rather than a request.
import { readdir, readFile, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";
import { brotliCompress, constants, gzip } from "node:zlib";

const brotli = promisify(brotliCompress);
const gz = promisify(gzip);

/** Text and uncompressed binary formats; images and woff2 are compressed already. */
const COMPRESSIBLE = /\.(js|mjs|css|json|svg|map|txt|wasm|ttf)$/;

/** Smaller files gain too little to be worth a second request path. */
const MIN_SIZE = 1024;

/** Keep an encoding only when it saves at least a tenth of the file. */
const MAX_RATIO = 0.9;

async function* files(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) yield* files(path);
    else if (entry.isFile()) yield path;
  }
}

/** zlib's asynchronous calls run on libuv's thread pool, four threads by default. */
const CONCURRENCY = 4;

/** Writes the encodings of one file and reports whether any was kept. */
async function compress(path) {
  const { size } = await stat(path);
  if (size < MIN_SIZE) return false;
  const source = await readFile(path);
  const encodings = [
    [".br", await brotli(source, {
      params: {
        [constants.BROTLI_PARAM_QUALITY]: constants.BROTLI_MAX_QUALITY,
        [constants.BROTLI_PARAM_SIZE_HINT]: size,
      },
    })],
    [".gz", await gz(source, { level: constants.Z_BEST_COMPRESSION })],
  ];
  let kept = false;
  for (const [suffix, data] of encodings) {
    if (data.length > size * MAX_RATIO) continue;
    await writeFile(path + suffix, data);
    kept = true;
  }
  return kept;
}

/**
 * Adds `<file>.br` and `<file>.gz` for each compressible file under `dir`,
 * and returns the sorted paths that received at least one encoding.
 */
export async function precompress(dir) {
  const pending = [];
  for await (const path of files(dir)) if (COMPRESSIBLE.test(path)) pending.push(path);
  const compressed = [];
  await Promise.all(Array.from({ length: CONCURRENCY }, async () => {
    for (let path; (path = pending.shift()) !== undefined;) {
      if (await compress(path)) compressed.push(path);
    }
  }));
  return compressed.sort();
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [dir] = process.argv.slice(2);
  if (!dir) throw new Error("usage: node desktop/package/precompress.mjs <browser bundle directory>");
  const compressed = await precompress(dir);
  console.log(`Precompressed ${compressed.length} files under ${dir}`);
}
