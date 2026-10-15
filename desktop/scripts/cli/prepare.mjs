import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { chmod, copyFile, cp, lstat, mkdir, mkdtemp, readFile, readdir, rename, rm, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

export const repository = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
export const lock = JSON.parse(await readFile(new URL("./vendors.json", import.meta.url), "utf8"));

export async function sha256(path) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest("hex");
}

function run(program, args) {
  execFileSync(program, args, { cwd: repository, stdio: "inherit", env: { ...process.env, COPYFILE_DISABLE: "1" } });
}

async function download(vendor, destination) {
  run("curl", ["--fail", "--location", "--silent", "--show-error", "--proto", "=https", "--proto-redir", "=https",
    "--connect-timeout", "15", "--max-time", "600", "--retry", "2", "--output", destination, vendor.url]);
  if (await sha256(destination) !== vendor.sha256) throw new Error("Downloaded rg checksum mismatch");
}

async function normalize(path) {
  const info = await lstat(path);
  if (info.isDirectory()) {
    await chmod(path, 0o755);
    for (const name of await readdir(path)) await normalize(join(path, name));
  } else if (info.isFile()) {
    await chmod(path, info.mode & 0o111 ? 0o755 : 0o644);
  } else throw new Error(`Release bundle contains a non-regular file: ${path}`);
}

export async function prepare({ platform, output }) {
  if (!Object.hasOwn(lock.platforms, platform)) throw new Error(`Unsupported platform: ${platform}`);
  output = resolve(output);
  await mkdir(output, { recursive: true });
  const asset = `openseek-deps-${platform}.tar.gz`;
  const suffix = platform === "windows-x64" ? ".exe" : "";
  const destination = join(output, asset);
  const target = lock.platforms[platform];
  const tar = process.platform === "win32" ? join(process.env.SystemRoot, "System32/tar.exe") : "tar";
  const temporary = await mkdtemp(join(output, ".prepare-"));
  try {
    const rg = join(temporary, "ripgrep.archive");
    await download(target.rg, rg);
    const root = join(temporary, "bundle");
    await mkdir(join(root, "bin"), { recursive: true });
    await mkdir(join(temporary, "rg"));
    run(tar, ["-xf", rg, "-C", join(temporary, "rg"), "--strip-components=1"]);
    await copyFile(join(temporary, `rg/rg${suffix}`), join(root, `bin/rg${suffix}`));
    await chmod(join(root, `bin/rg${suffix}`), 0o755);
    const cli = join(output, `openseek-${platform}${suffix}`);
    await cp(join(repository, "share"), join(root, "share"), {
      recursive: true, filter: path => !["_build", ".mooncakes"].includes(basename(path)),
    });
    await mkdir(join(root, "licenses/ripgrep"), { recursive: true });
    for (const name of ["LICENSE-MIT", "UNLICENSE"]) await copyFile(join(temporary, "rg", name), join(root, "licenses/ripgrep", name));
    await copyFile(join(repository, "LICENSE"), join(root, "licenses/OpenSeek-LICENSE"));
    await normalize(root);
    const archive = join(temporary, asset);
    run(tar, ["-czf", archive, "-C", root, "."]);
    await rename(archive, destination);
    await writeFile(join(output, `SHA256SUMS-${platform}`),
      `${await sha256(cli)}  openseek-${platform}${suffix}\n${await sha256(destination)}  ${asset}\n`);
  } finally { await rm(temporary, { recursive: true, force: true }); }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { values } = parseArgs({ options: { platform: { type: "string" }, output: { type: "string" } } });
  for (const name of ["platform", "output"]) if (!values[name]) throw new Error(`Missing --${name}`);
  await prepare(values);
}
