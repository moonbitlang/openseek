import { chmod, cp, lstat, mkdir, mkdtemp, readFile, readdir, rename, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { execFileSync } from "node:child_process";
import { stageResources } from "../../desktop/package/resources.mjs";
import { checkElf, inventory, sha256, validBuild, validateManifest, verifyTree } from "./manifest.mjs";

const repo = fileURLToPath(new URL("../../", import.meta.url));
const lock = JSON.parse(await readFile(new URL("./vendors.json", import.meta.url), "utf8"));

function run(command, args) {
  return execFileSync(command, args, { cwd: repo, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 16 * 1024 ** 2 });
}

export function launcher(buildId, platform) {
  if (!validBuild(buildId) || !Object.hasOwn(lock.platforms, platform)) throw new Error("Invalid launcher identity");
  return `#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
export PATH="$root/bin:\${PATH:-/usr/bin:/bin}"
export OPENSEEK_HOST_ENGINE="$root/bin/openseek"
export OPENSEEK_HOST_BUILD_ID='${buildId}'
export OPENSEEK_HOST_VIZ_DIR="$root/web/viz"
export OPENSEEK_HOST_MOONBIT_PLATFORM='${platform}'
export OPENSEEK_HOST_MOONBIT_SEED_DIR="$root/toolchains/moonbit/${platform}"
exec "$root/bin/moonrun" "$root/lib/openseek.wasm" -- "$@"
`;
}

async function normalize(path, executable = false) {
  const info = await lstat(path);
  if (info.isDirectory()) {
    await chmod(path, 0o755);
    for (const name of await readdir(path)) await normalize(join(path, name), executable);
  } else if (info.isFile()) await chmod(path, executable || (info.mode & 0o111) ? 0o755 : 0o644);
  else throw new Error(`Unsupported resource: ${path}`);
}

async function normalizedCopy(source, destination) {
  await cp(source, destination, { recursive: true, dereference: true });
  await normalize(destination);
}

async function checkedArchive(vendor, directory) {
  const path = join(directory, vendor.file);
  if (await sha256(path) !== vendor.sha256) throw new Error(`Vendor checksum mismatch: ${vendor.file}`);
  return path;
}

export async function packageHeadless({ platform, buildId, vendorDir, output, wasm, viz }) {
  const desktopVersion = (await readFile(join(repo, "desktop/.moonbit-version"), "utf8")).trim();
  if (lock.moonbit_version !== desktopVersion) {
    throw new Error(`Headless SDK ${lock.moonbit_version} differs from desktop ${desktopVersion}; update vendors.json before packaging`);
  }
  if (process.platform === "win32") throw new Error("Build Linux packages on Linux or macOS to preserve POSIX permissions");
  const target = Object.hasOwn(lock.platforms, platform) ? lock.platforms[platform] : undefined;
  if (!target || !validBuild(buildId)) throw new Error("Specify a supported platform and build ID");
  output = resolve(output);
  try { await lstat(output); throw new Error(`Output already exists: ${output}`); }
  catch (error) { if (error.code !== "ENOENT") throw error; }
  const wasmHeader = (await readFile(wasm)).subarray(0, 8);
  if (!wasmHeader.equals(Buffer.from([0, 97, 115, 109, 1, 0, 0, 0]))) throw new Error("Expected a compiled Wasm module");
  const sdkArchive = await checkedArchive(target.sdk, vendorDir);
  const coreArchive = await checkedArchive(lock.core, vendorDir);
  const rgArchive = await checkedArchive(target.ripgrep, vendorDir);
  await mkdir(dirname(output), { recursive: true });
  const temporary = await mkdtemp(join(dirname(output), ".headless-"));
  const root = join(temporary, "package");
  try {
    const sdk = join(temporary, "sdk");
    const rg = join(temporary, "rg");
    await mkdir(join(sdk, "lib"), { recursive: true });
    await mkdir(rg);
    // Only pinned upstream archives reach extraction; the shipped tree below
    // contains no links and is independently inventoried after normalization.
    run("tar", ["-xf", sdkArchive, "-C", sdk]);
    run("tar", ["-xf", coreArchive, "-C", join(sdk, "lib")]);
    run("tar", ["-xf", rgArchive, "-C", rg]);
    await rm(join(sdk, "lib/core/_build"), { recursive: true, force: true });
    await normalize(join(sdk, "bin"), true);
    // The SDK installer normally creates moonx -> moon. Ship a regular copy
    // so argv[0] still selects moonx while the manifest contains no links.
    await cp(join(sdk, "bin/moon"), join(sdk, "bin/moonx"));
    for (const name of ["moon", "moonc", "moonx", "moonrun"]) checkElf(await readFile(join(sdk, "bin", name)), platform, name);
    const rgRoot = join(rg, target.ripgrep.directory);
    checkElf(await readFile(join(rgRoot, "rg")), platform, "ripgrep");
    for (const dir of ["bin", "lib", "web/viz", "licenses/ripgrep", "licenses/openseek"]) {
      await mkdir(join(root, dir), { recursive: true });
    }
    const seed = join(root, `toolchains/moonbit/${platform}`);
    await normalizedCopy(sdk, seed);
    await writeFile(join(seed, ".openseek-moonbit-seed-version"), lock.moonbit_version + "\n", { mode: 0o644 });
    await normalizedCopy(join(sdk, "bin/moonrun"), join(root, "bin/moonrun"));
    await normalizedCopy(join(rgRoot, "rg"), join(root, "bin/rg"));
    await normalizedCopy(wasm, join(root, "lib/openseek.wasm"));
    await chmod(join(root, "lib/openseek.wasm"), 0o644);
    await normalizedCopy(join(repo, "web/index.html"), join(root, "web/viz/index.html"));
    await normalizedCopy(viz, join(root, "web/viz/viz_app.js"));
    for (const name of ["LICENSE-MIT", "UNLICENSE"]) await normalizedCopy(join(rgRoot, name), join(root, "licenses/ripgrep", name));
    await normalizedCopy(join(repo, "LICENSE"), join(root, "licenses/openseek/LICENSE"));
    const resourceHash = await stageResources(join(repo, "share"), join(root, "share"));
    // Normalize shared files too: checkout modes must not accidentally make a
    // data file privileged or make the manifest vary with the build umask.
    await normalize(join(root, "share"));
    await writeFile(join(root, "bin/openseek"), launcher(buildId, platform), { mode: 0o755 });
    await normalize(root);
    const manifest = validateManifest({
      schema_version: 1, build_id: buildId, platform, protocol_version: 1, data_schema_version: 1,
      moonbit_version: lock.moonbit_version, resource_sha256: resourceHash,
      runtime_requirements: { os: "Linux", libc: "glibc", minimum_glibc: "2.35" },
      files: await inventory(root),
    });
    await writeFile(join(root, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n", { mode: 0o644 });
    await chmod(join(root, "manifest.json"), 0o644);
    await verifyTree(root, manifest);
    await rename(root, output);
    return manifest;
  } finally { await rm(temporary, { recursive: true, force: true }); }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { values } = parseArgs({ options: Object.fromEntries(["platform", "build-id", "vendor-dir", "output", "wasm", "viz"].map(name => [name, { type: "string" }])) });
  for (const name of ["platform", "build-id", "vendor-dir", "output"]) if (!values[name]) throw new Error(`Missing --${name}`);
  const manifest = await packageHeadless({
    platform: values.platform, buildId: values["build-id"],
    vendorDir: resolve(values["vendor-dir"]), output: values.output,
    wasm: resolve(values.wasm ?? join(repo, "_build/wasm/debug/build/moonbitlang/openseek/openseek.wasm")),
    viz: resolve(values.viz ?? join(repo, "_build/js/debug/build/moonbitlang/openseek-viz-app/openseek-viz-app.js")),
  });
  console.log(JSON.stringify({ build_id: manifest.build_id, platform: manifest.platform, files: manifest.files.length, output: resolve(values.output), manifest_sha256: await sha256(join(resolve(values.output), "manifest.json")) }));
}
