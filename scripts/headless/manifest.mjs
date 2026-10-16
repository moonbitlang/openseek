import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { lstat, readdir } from "node:fs/promises";
import { join } from "node:path";

export const platforms = new Map([["linux-x64", 62], ["linux-arm64", 183]]);
export const validBuild = value => typeof value === "string" && /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,199}$/.test(value);
export const validPath = value => typeof value === "string" && value.length <= 1024 &&
  !value.includes("\\") && !/[\x00-\x1f\x7f]/.test(value) &&
  value.split("/").every(part => part !== "" && part !== "." && part !== "..");

export async function sha256(path) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest("hex");
}

export function checkElf(bytes, platform, label) {
  if (bytes.length < 64 || !bytes.subarray(0, 4).equals(Buffer.from([127, 69, 76, 70])) ||
      bytes[4] !== 2 || bytes[5] !== 1 || ![2, 3].includes(bytes.readUInt16LE(16)) ||
      bytes.readUInt16LE(18) !== platforms.get(platform)) {
    throw new Error(`${label}: expected a 64-bit ${platform} ELF executable`);
  }
}

export async function inventory(root, prefix = "") {
  const result = [];
  for (const name of (await readdir(join(root, prefix))).sort()) {
    const path = prefix + name;
    if (!validPath(path)) throw new Error(`Invalid package path: ${path}`);
    const info = await lstat(join(root, path));
    if (info.isDirectory()) result.push(...await inventory(root, path + "/"));
    else if (info.isFile()) {
      if (path === "manifest.json") continue;
      if ((info.mode & 0o7777) !== 0o644 && (info.mode & 0o7777) !== 0o755) {
        throw new Error(`Unexpected package permissions: ${path}`);
      }
      result.push({ path, size: info.size, mode: info.mode & 0o777, sha256: await sha256(join(root, path)) });
    } else throw new Error(`Package entries must be regular files or directories: ${path}`);
  }
  return result;
}

export function validateManifest(value) {
  if (!value || value.schema_version !== 1 || !validBuild(value.build_id) ||
      !platforms.has(value.platform) || value.protocol_version !== 1 || value.data_schema_version !== 1 ||
      typeof value.moonbit_version !== "string" || !value.moonbit_version ||
      typeof value.resource_sha256 !== "string" || !/^[a-f0-9]{64}$/.test(value.resource_sha256) ||
      value.runtime_requirements?.os !== "Linux" || value.runtime_requirements?.libc !== "glibc" || value.runtime_requirements?.minimum_glibc !== "2.35" ||
      !Array.isArray(value.files) || value.files.length < 1 || value.files.length > 100000) {
    throw new Error("Invalid headless build manifest");
  }
  const paths = new Set();
  let total = 0;
  for (const file of value.files) {
    if (!file || !validPath(file.path) || file.path === "manifest.json" || paths.has(file.path) ||
        !Number.isSafeInteger(file.size) || file.size < 0 || ![0o644, 0o755].includes(file.mode) ||
        typeof file.sha256 !== "string" || !/^[a-f0-9]{64}$/.test(file.sha256)) {
      throw new Error("Invalid or duplicate manifest file entry");
    }
    total += file.size;
    if (total > 4 * 1024 ** 3) throw new Error("Headless package size limit exceeded");
    paths.add(file.path);
  }
  const seed = `toolchains/moonbit/${value.platform}`;
  for (const path of ["bin/openseek", "bin/moonrun", "bin/rg", "lib/openseek.wasm",
    "share/doc/moonbit/index.md", "web/viz/index.html", "web/viz/viz_app.js",
    `${seed}/bin/moon`, `${seed}/bin/moonc`, `${seed}/bin/moonx`, `${seed}/bin/moonrun`,
    `${seed}/.openseek-moonbit-seed-version`]) {
    if (!paths.has(path)) throw new Error(`Headless package is missing ${path}`);
  }
  const entries = new Map(value.files.map(file => [file.path, file]));
  for (const path of ["bin/openseek", "bin/moonrun", "bin/rg",
    `${seed}/bin/moon`, `${seed}/bin/moonc`, `${seed}/bin/moonx`, `${seed}/bin/moonrun`]) {
    if (entries.get(path).mode !== 0o755) throw new Error(`Required executable is not executable: ${path}`);
  }
  if (!paths.has(`${seed}/lib/core/moon.mod`) && !paths.has(`${seed}/lib/core/moon.mod.json`)) throw new Error("MoonBit core module is missing");
  for (const path of paths) {
    if (path === "web/frontend.js" || /(^|\/)(CEF|Chromium Embedded Framework|libcef\.so|proton)(\/|$)/i.test(path)) {
      throw new Error(`GUI runtime is not a headless resource: ${path}`);
    }
  }
  return value;
}

export async function verifyTree(root, manifest) {
  validateManifest(manifest);
  const actual = await inventory(root);
  const expected = new Map(manifest.files.map(file => [file.path, file]));
  if (actual.length !== expected.size) throw new Error("Package file set differs from manifest");
  for (const file of actual) {
    const entry = expected.get(file.path);
    if (!entry || file.size !== entry.size || file.mode !== entry.mode || file.sha256 !== entry.sha256) {
      throw new Error(`Package checksum or permissions differ: ${file.path}`);
    }
  }
}
