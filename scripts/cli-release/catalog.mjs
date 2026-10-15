import { readFile, stat, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { checkElf, lock, sha256, validateRelease } from "./prepare.mjs";

export async function catalog(directory, id) {
  const platforms = {};
  const checksums = [];
  for (const platform of ["linux-x64", "linux-arm64"]) {
    const runtime = JSON.parse(await readFile(join(directory, `runtime-${platform}.json`), "utf8"));
    const baseUrl = `https://github.com/moonbitlang/openseek/releases/download/${id}`;
    validateRelease(id, platform, baseUrl);
    const runtimeFile = `openseek-runtime-${platform}.tar.gz`;
    if (runtime.id !== id || runtime.platform !== platform || runtime.moonbit_version !== lock.moonbit_version || runtime.url !== `${baseUrl}/${runtimeFile}` ||
        await sha256(join(directory, runtimeFile)) !== runtime.sha256) throw new Error(`Mismatched runtime: ${platform}`);
    const executable = `openseek-${platform}`;
    const path = join(directory, executable);
    checkElf(await readFile(path), platform);
    const digest = await sha256(path);
    platforms[platform] = { url: `${baseUrl}/${executable}`, sha256: digest, size: (await stat(path)).size, runtime };
    checksums.push(`${digest}  ${executable}`, `${runtime.sha256}  ${runtimeFile}`);
  }
  const result = { schema_version: 1, id, platforms };
  await writeFile(join(directory, "cli-release.json"), JSON.stringify(result, null, 2) + "\n");
  await writeFile(join(directory, "SHA256SUMS"), checksums.join("\n") + "\n");
  return result;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [directory, id] = process.argv.slice(2);
  if (!directory || !id) throw new Error("Usage: node scripts/cli-release/catalog.mjs DIRECTORY CLI-TAG");
  await catalog(resolve(directory), id);
}
