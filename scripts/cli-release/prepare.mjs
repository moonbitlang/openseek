import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { chmod, copyFile, lstat, mkdir, mkdtemp, readFile, readdir, rename, rm, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { stageResources } from "../../desktop/package/resources.mjs";

export const repository = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
export const lock = JSON.parse(await readFile(new URL("./vendors.json", import.meta.url), "utf8"));

export async function sha256(path) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest("hex");
}

export function validateRelease(id, platform, baseUrl) {
  if (!/^cli-v\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$/.test(id)) throw new Error("Expected cli-vMAJOR.MINOR.PATCH[-suffix]");
  if (!Object.hasOwn(lock.platforms, platform)) throw new Error("Expected linux-x64 or linux-arm64");
  const url = new URL(baseUrl);
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash) throw new Error("Release base URL must be HTTPS without credentials, query or fragment");
}

export function checkElf(bytes, platform) {
  if (bytes.length < 64 || bytes.subarray(0, 4).toString("hex") !== "7f454c46" ||
      bytes[4] !== 2 || bytes[5] !== 1 || ![2, 3].includes(bytes.readUInt16LE(16)) ||
      bytes.readUInt16LE(18) !== lock.platforms[platform].machine) {
    throw new Error(`Expected a native 64-bit ${platform} ELF executable`);
  }
}

function run(program, args) {
  execFileSync(program, args, { cwd: repository, stdio: "inherit", env: { ...process.env, COPYFILE_DISABLE: "1" } });
}

async function download(vendor, cache) {
  const destination = join(cache, vendor.file);
  try {
    if (await sha256(destination) !== vendor.sha256) throw new Error(`Cached dependency checksum mismatch: ${vendor.file}`);
    return destination;
  } catch (error) { if (error.code !== "ENOENT") throw error; }
  const temporary = await mkdtemp(join(cache, ".download-"));
  try {
    const path = join(temporary, "archive");
    run("curl", ["--fail", "--location", "--silent", "--show-error", "--proto", "=https", "--proto-redir", "=https",
      "--connect-timeout", "15", "--max-time", "600", "--retry", "2", "--output", path, vendor.url]);
    if (await sha256(path) !== vendor.sha256) throw new Error(`Downloaded dependency checksum mismatch: ${vendor.file}`);
    await rename(path, destination);
    return destination;
  } finally { await rm(temporary, { recursive: true, force: true }); }
}

async function normalize(path, executable = false) {
  const info = await lstat(path);
  if (info.isDirectory()) {
    await chmod(path, 0o755);
    for (const name of await readdir(path)) await normalize(join(path, name), executable);
  } else if (info.isFile()) {
    await chmod(path, executable || (info.mode & 0o111) ? 0o755 : 0o644);
  } else throw new Error(`Release runtime contains a non-regular file: ${path}`);
}

export async function prepare({ id, platform, baseUrl, output, cache }) {
  validateRelease(id, platform, baseUrl);
  const version = (await readFile(join(repository, "desktop/.moonbit-version"), "utf8")).trim();
  if (version !== lock.moonbit_version) throw new Error("Update CLI vendors.json when desktop/.moonbit-version changes");
  output = resolve(output); cache = resolve(cache);
  await mkdir(output, { recursive: true });
  await mkdir(cache, { recursive: true });
  const asset = `openseek-runtime-${platform}.tar.gz`;
  const destination = join(output, asset);
  try { await lstat(destination); throw new Error(`Refusing to replace ${destination}`); }
  catch (error) { if (error.code !== "ENOENT") throw error; }
  const target = lock.platforms[platform];
  const rg = await download(target.rg, cache);
  const temporary = await mkdtemp(join(output, ".prepare-"));
  try {
    const root = join(temporary, "runtime");
    await mkdir(join(root, "bin"), { recursive: true });
    await mkdir(join(temporary, "rg"));
    run("tar", ["-xf", rg, "-C", join(temporary, "rg"), "--strip-components=1"]);
    checkElf(await readFile(join(temporary, "rg/rg")), platform);
    await copyFile(join(temporary, "rg/rg"), join(root, "bin/rg"));
    await chmod(join(root, "bin/rg"), 0o755);
    await stageResources(join(repository, "share"), join(root, "share"));
    await writeFile(join(root, "runtime.json"), JSON.stringify({ id, platform, moonbit_version: version }) + "\n");
    await mkdir(join(root, "licenses/ripgrep"), { recursive: true });
    for (const name of ["LICENSE-MIT", "UNLICENSE"]) await copyFile(join(temporary, "rg", name), join(root, "licenses/ripgrep", name));
    await copyFile(join(repository, "LICENSE"), join(root, "licenses/OpenSeek-LICENSE"));
    await normalize(root);
    const archive = join(temporary, asset);
    run("tar", ["-czf", archive, "-C", root, "."]);
    const manifest = { id, platform, url: `${baseUrl.replace(/\/$/, "")}/${asset}`, sha256: await sha256(archive), moonbit_version: version };
    await rename(archive, destination);
    await writeFile(join(output, `runtime-${platform}.json`), JSON.stringify(manifest, null, 2) + "\n");
    // Each binary knows the exact runtime bytes it accepts. No runtime lookup
    // of latest, and no second mutable manifest between download and execution.
    await writeFile(join(repository, "installation/release.mbt"),
      `///|\n// Generated for ${id} / ${platform}; do not commit release-build output.\nfn release_manifest() -> String? {\n  Some(${JSON.stringify(JSON.stringify(manifest))})\n}\n`);
    return manifest;
  } finally { await rm(temporary, { recursive: true, force: true }); }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { values } = parseArgs({ options: Object.fromEntries(["id", "platform", "base-url", "output", "cache"].map(name => [name, { type: "string" }])) });
  for (const name of ["id", "platform", "output", "cache"]) if (!values[name]) throw new Error(`Missing --${name}`);
  console.log(JSON.stringify(await prepare({ id: values.id, platform: values.platform, output: values.output, cache: values.cache,
    baseUrl: values["base-url"] ?? `https://github.com/moonbitlang/openseek/releases/download/${values.id}` })));
}
