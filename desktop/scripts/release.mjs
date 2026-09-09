// Stamp, upload, and publish Desktop releases.
//
//   node scripts/release.mjs stamp X.Y.Z       stamp the version every packager builds from
//   node scripts/release.mjs upload [vX.Y.Z]   upload the checkout's artifacts to OSS
//   node scripts/release.mjs publish [vX.Y.Z]  make the uploaded version live
//   node scripts/release.mjs verify [vX.Y.Z]   check the live release through its public URLs
//   node scripts/release.mjs rollback vX.Y.Z   republish an existing version
//   node scripts/release.mjs status            list API-owned release state
//
// OSS stores the artifacts only. openseek-api generates and atomically
// replaces latest.json from the filenames and SHA-256 digests it is told
// about, so a release becomes visible once every file is in place, and
// rolling back is publishing an older version again.
//
// upload, publish, and rollback need OPENSEEK_OSS_BUCKET, OPENSEEK_OSS_REGION,
// OPENSEEK_API_ORIGIN, and OPENSEEK_DEPLOY_TOKEN, plus ossutil 2.x with its
// OSS_ACCESS_KEY_ID and OSS_ACCESS_KEY_SECRET. The standard API origins select
// their OSS prefixes; other deployments set OPENSEEK_OSS_PREFIX. verify needs
// only OPENSEEK_API_ORIGIN and the checkout's archives in dist/.

import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { appendFile, readFile, rm, stat, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// Everything one release ships, in upload order. `file` is both the name in
// dist/ and the immutable download name under the version directory; `label`
// names the download in the release summary.
const Artifacts = [
  { platform: "macos-arm64", label: "Updater ZIP", file: "SeekMoon.app.zip", contentType: "application/zip" },
  { platform: "macos-arm64-dmg", label: "Installer DMG", file: "SeekMoon.dmg", contentType: "application/x-apple-diskimage" },
  // Also uploaded to the API: `/console/` serves it from the API origin.
  { platform: "browser", label: "Browser bundle", file: "SeekMoon.browser.tar.gz", contentType: "application/gzip" },
  // Renamed from Proton's `seekmoon-setup.exe` by the release workflow.
  // Rollbacks preserve older ZIP downloads or releases without Windows.
  { platform: "windows-x64", label: "Windows installer", file: "SeekMoon-windows-x64-setup.exe", contentType: "application/octet-stream",
    optionalOnRollback: true, rollbackFiles: ["SeekMoon-windows-x64.zip"] },
];
const Browser = Artifacts.find(artifact => artifact.platform === "browser");

const OssPrefixes = {
  "https://openseek-api.moonbitlang.cn": "openseek/desktop/releases",
  "https://openseek-api-staging.moonbitlang.cn": "openseek/staging/desktop/releases",
};

const Usage = `usage:
  node scripts/release.mjs stamp X.Y.Z
  node scripts/release.mjs upload [vX.Y.Z]
  node scripts/release.mjs publish [vX.Y.Z]
  node scripts/release.mjs verify [vX.Y.Z]
  node scripts/release.mjs rollback vX.Y.Z
  node scripts/release.mjs status`;

export class Release {
  constructor() {
    this.desktop = fileURLToPath(new URL("../", import.meta.url));
    this.dist = join(this.desktop, "dist");
  }

  env(name) {
    const value = process.env[name];
    if (!value) throw new Error(`set ${name}`);
    return value;
  }

  apiOrigin() {
    return this.env("OPENSEEK_API_ORIGIN").replace(/\/$/, "");
  }

  oss() {
    const origin = this.apiOrigin();
    const prefix = process.env.OPENSEEK_OSS_PREFIX?.replace(/^\/+|\/+$/g, "") || OssPrefixes[origin];
    if (!prefix) throw new Error(`no OSS prefix mapped for ${origin}; set OPENSEEK_OSS_PREFIX`);
    return { bucket: this.env("OPENSEEK_OSS_BUCKET"), region: this.env("OPENSEEK_OSS_REGION"), prefix };
  }

  async moduleVersion() {
    const module = await readFile(join(this.desktop, "moon.mod"), "utf8");
    const match = module.match(/^version = "([^"]+)"$/m);
    if (!match) throw new Error("could not read version from moon.mod");
    return match[1];
  }

  async checkoutVersion(version) {
    const checkout = `v${await this.moduleVersion()}`;
    if (version !== checkout) {
      throw new Error(`${version} does not match checkout version ${checkout}; use rollback for an already-published version`);
    }
    return version;
  }

  commandRun(program, args, env = {}) {
    console.log(`$ ${program} ${args.join(" ")}`);
    const result = spawnSync(program, args, {
      cwd: this.desktop, env: { ...process.env, ...env }, stdio: "inherit", shell: false,
    });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`${program} exited with ${result.status ?? result.signal}`);
  }

  async digest(path) {
    const hash = createHash("sha256");
    for await (const chunk of createReadStream(path)) hash.update(chunk);
    return hash.digest("hex");
  }

  // An API route, with the deploy token unless the route is public.
  // Fail on the first request error; operators can rerun the release job.
  async fetch(path, { auth = true, headers = {}, ...options } = {}) {
    const authorization = auth ? { authorization: `Bearer ${this.env("OPENSEEK_DEPLOY_TOKEN")}` } : {};
    return fetch(`${this.apiOrigin()}${path}`, { ...options, headers: { ...headers, ...authorization } });
  }

  async fetchJson(path, options) {
    const response = await this.fetch(path, options);
    const text = await response.text();
    if (!response.ok) throw new Error(`${options?.method ?? "GET"} ${path} failed: HTTP ${response.status}\n${text}`);
    return JSON.parse(text);
  }

  // ossutil appends an elapsed-time line to structured output unless quiet
  // mode is on; the HeadObject JSON must stay parseable. Only OSS's own
  // NoSuchKey answer reads as `missing`: credentials, network, or a wrong
  // bucket are failures, so a rollback cannot mistake an outage for a
  // release that predates a platform.
  headObject(version, artifact) {
    const oss = this.oss();
    const result = spawnSync("ossutil", ["api", "head-object", "--region", oss.region, "--bucket", oss.bucket,
      "--key", `${oss.prefix}/${version}/${artifact.file}`, "--output-format", "json", "--quiet"],
    { cwd: this.desktop, encoding: "utf8" });
    if (result.error) throw result.error;
    if (result.status !== 0) {
      const detail = `${result.stdout}${result.stderr}`.trim();
      if (/^Error Code: NoSuchKey\.?\s*$/m.test(detail)) return { missing: true };
      throw new Error(`ossutil head-object failed for ${artifact.platform} ${version}: ${detail}`);
    }
    const header = JSON.parse(result.stdout).Header;
    return {
      size: header["Content-Length"]?.[0],
      sha256: header["X-Oss-Meta-Sha256"]?.[0],
      crc64: header["X-Oss-Hash-Crc64ecma"]?.[0],
    };
  }

  ossUrl(version, artifact) {
    const oss = this.oss();
    return `oss://${oss.bucket}/${oss.prefix}/${version}/${artifact.file}`;
  }

  async localArtifact(artifact) {
    const path = join(this.dist, artifact.file);
    const size = await stat(path).then(info => info.size, error => {
      if (error.code === "ENOENT") throw new Error(`artifact not found: ${path}`, { cause: error });
      throw error;
    });
    return { path, size, sha256: await this.digest(path) };
  }

  // What OSS serves must be a complete object whose metadata describes it,
  // and, when the checkout built it, the very bytes the checkout holds.
  async verifyServed(version, artifact, local) {
    const served = this.headObject(version, artifact);
    if (served.missing) throw new Error(`OSS object is missing for ${artifact.platform} ${version}`);
    if (!served.crc64 || !/^[0-9a-f]{64}$/.test(served.sha256 ?? "")) {
      throw new Error(`OSS metadata is incomplete for ${artifact.platform}`);
    }
    if (local && (served.size !== String(local.size) || served.sha256 !== local.sha256)) {
      throw new Error(`OSS object does not match the built artifact: ${artifact.platform}`);
    }
    return served;
  }

  async stamp(version) {
    if (!/^\d+\.\d+\.\d+$/.test(version)) {
      throw new Error(`release version must be three dot-separated numbers: ${version}`);
    }
    // OpenSeek's shared build program reads moon.mod, while Proton 0.2 reads
    // package.version from the project config; both must agree before packaging.
    const modulePath = join(this.desktop, "moon.mod");
    const module = await readFile(modulePath, "utf8");
    if (!/^version = "[^"]+"$/m.test(module)) throw new Error("moon.mod has no version line");
    await writeFile(modulePath, module.replace(/^version = "[^"]+"$/m, `version = "${version}"`));
    const configPath = join(this.desktop, "proton.project.json");
    const config = JSON.parse(await readFile(configPath, "utf8"));
    config.package.version = version;
    await writeFile(configPath, `${JSON.stringify(config, null, 2)}\n`);
    if (await this.moduleVersion() !== version) throw new Error("moon.mod did not take the version");
    if (JSON.parse(await readFile(configPath, "utf8")).package.version !== version) {
      throw new Error("proton.project.json did not take the version");
    }
    console.log(`stamped ${version}`);
  }

  async upload(version) {
    await this.checkoutVersion(version);
    const oss = this.oss();
    // A published Browser directory is the API-owned per-version seal. If a
    // previous attempt reached API publish but the job failed afterwards, its
    // OSS bytes must be reused instead of overwritten by a fresh rebuild.
    const sealed = await this.fetch(`/console/releases/${version}/index.html`);
    await sealed.body?.cancel();
    if (sealed.status === 200) {
      console.log(`${version} is already published by the API; reusing its OSS artifacts`);
      for (const artifact of Artifacts) {
        this.commandRun("ossutil", ["cp", "--force", "--region", oss.region,
          this.ossUrl(version, artifact), join(this.dist, artifact.file)]);
        await this.verifyServed(version, artifact, await this.localArtifact(artifact));
        console.log(`${artifact.platform} restored: ${this.ossUrl(version, artifact)}`);
      }
      await this.unpackBrowser();
      console.log(`${version} is ready to publish again`);
      return;
    }
    if (sealed.status !== 404) {
      throw new Error(`could not determine whether ${version} is published: HTTP ${sealed.status}`);
    }

    console.log(`${version} is unpublished; uploading replaceable OSS artifacts`);
    const digests = {};
    for (const artifact of Artifacts) {
      const local = await this.localArtifact(artifact);
      // Rebuilds are not byte-identical. Until the API publishes this version,
      // a retry must replace provisional bytes instead of keeping an older run.
      this.commandRun("ossutil", ["cp", "--force", "--region", oss.region,
        "--content-type", artifact.contentType,
        "--cache-control", "public, max-age=31536000, immutable",
        "--metadata", `sha256=${local.sha256}`,
        local.path, this.ossUrl(version, artifact)]);
      // Verify against OSS directly. Accessing the CDN before publication can
      // cache provisional bytes under the immutable version URL.
      await this.verifyServed(version, artifact, local);
      digests[artifact.platform] = local.sha256;
      console.log(`${artifact.platform} verified in OSS`);
    }

    // `/console/` remains on the API origin, so only the much smaller Browser
    // archive is uploaded twice. Desktop packages exist only in OSS.
    const recorded = await this.fetchJson(`/desktop/releases/${version}/${Browser.file}?platform=browser`, {
      method: "PUT", body: await readFile(join(this.dist, Browser.file)),
    });
    if (recorded.sha256 !== digests.browser) {
      throw new Error(`DIGEST MISMATCH: API recorded ${recorded.sha256} for Browser`);
    }
    await this.unpackBrowser();
    console.log(`${version} is ready to publish`);
  }

  // The publishing runner builds nothing, so the Browser directory that the
  // console verification compares against is unpacked from the archive in
  // dist/: the bytes OSS holds and the API received.
  async unpackBrowser() {
    await rm(join(this.dist, "browser"), { recursive: true, force: true });
    this.commandRun("tar", ["-xzf", join(this.dist, Browser.file), "-C", this.dist]);
  }

  // Publish and rollback share the same API contract. The runner knows OSS and
  // supplies trusted filenames and SHA-256 values; the API knows only the
  // public release base URL and owns latest.json generation.
  async publish(version, { fromCheckout }) {
    if (fromCheckout) await this.checkoutVersion(version);
    else if (!/^v[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(version)) throw new Error(`invalid rollback version: ${version}`);
    const platforms = {};
    for (let artifact of Artifacts) {
      if (!fromCheckout && artifact.optionalOnRollback) {
        const file = [artifact.file, ...(artifact.rollbackFiles ?? [])].find(file =>
          !this.headObject(version, { ...artifact, file }).missing);
        if (file === undefined) {
          console.log(`${artifact.platform} was never uploaded for ${version}; republishing without it`);
          continue;
        }
        artifact = { ...artifact, file };
      }
      const local = fromCheckout ? await this.localArtifact(artifact) : undefined;
      const served = await this.verifyServed(version, artifact, local);
      platforms[artifact.platform] = { file: artifact.file, sha256: served.sha256 };
    }

    const response = await this.fetchJson(`/desktop/releases/${version}/publish`, {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ platforms }),
    });
    this.verifyManifest(response.published, version, platforms);
    // Read the canonical file back from the API. This verifies that publish
    // wrote the same manifest it returned; no manifest is copied to OSS.
    const latest = await this.fetchJson("/desktop/releases/latest.json");
    this.verifyManifest(latest, version, platforms);
    console.log(JSON.stringify(latest, null, 2));
  }

  // The API must have published exactly the requested platforms, each at its
  // versioned file with the digest OSS reported.
  verifyManifest(manifest, version, platforms) {
    if (manifest?.version !== version.replace(/^v/, "")) {
      throw new Error(`manifest version ${manifest?.version} is not ${version}`);
    }
    const published = Object.keys(manifest.platforms ?? {}).sort().join(" ");
    const requested = Object.keys(platforms).sort().join(" ");
    if (published !== requested) throw new Error(`manifest platforms "${published}" are not "${requested}"`);
    for (const [platform, { file, sha256 }] of Object.entries(platforms)) {
      const entry = manifest.platforms[platform];
      if (entry.sha256 !== sha256) throw new Error(`manifest digest for ${platform} is not ${sha256}`);
      if (!entry.url.endsWith(`/${version}/${file}`)) throw new Error(`manifest URL for ${platform} is not ${file}: ${entry.url}`);
    }
  }

  // The release as a user meets it, needing no credentials: the manifest the
  // API serves, the download URLs it names, and the console it selects, each
  // compared with the archives in dist/ (the OSS bytes once `upload` ran).
  async verify(version) {
    await this.checkoutVersion(version);
    const manifest = await this.fetchJson("/desktop/releases/latest.json", { auth: false });
    const platforms = {};
    for (const artifact of Artifacts) {
      const local = await this.localArtifact(artifact);
      platforms[artifact.platform] = { file: artifact.file, sha256: local.sha256, size: local.size };
    }
    this.verifyManifest(manifest, version, platforms);

    // HEAD through the public URL, so whatever fronts OSS is checked too. The
    // size must be the object's own, not that of a transfer encoding.
    for (const artifact of Artifacts) {
      const { url } = manifest.platforms[artifact.platform];
      const local = platforms[artifact.platform];
      const response = await fetch(url, { method: "HEAD", headers: { "accept-encoding": "identity" } });
      if (!response.ok) throw new Error(`HEAD ${url} failed: HTTP ${response.status}`);
      const served = {
        size: response.headers.get("content-length"),
        sha256: response.headers.get("x-oss-meta-sha256"),
        crc64: response.headers.get("x-oss-hash-crc64ecma"),
      };
      if (served.size !== String(local.size) || served.sha256 !== local.sha256 || !served.crc64) {
        throw new Error(`${url} does not serve the released ${artifact.platform} archive`);
      }
      console.log(`${artifact.platform} ok: ${url}`);
    }

    // The API must have selected this version's Browser bundle for `/console/`
    // and serve the files that the archive in dist/ contains.
    const bare = version.replace(/^v/, "");
    const current = await this.fetchJson("/browser/releases/current.json", { auth: false });
    if (current?.version !== bare) throw new Error(`browser current.json version ${current?.version} is not ${bare}`);
    const consolePath = `/console/releases/${version}/index.html`;
    const redirect = await this.fetch("/console/", { auth: false, redirect: "manual" });
    await redirect.body?.cancel();
    if (redirect.status < 300 || redirect.status >= 400) {
      throw new Error(`/console/ did not redirect: HTTP ${redirect.status}`);
    }
    const location = redirect.headers.get("location");
    if (location === null) throw new Error(`/console/ redirect is missing Location: HTTP ${redirect.status}`);
    if (new URL(location, this.apiOrigin()).pathname !== consolePath) {
      throw new Error(`/console/ did not select ${consolePath}: HTTP ${redirect.status} ${location}`);
    }
    for (const file of ["index.html", "browser.js"]) {
      const response = await this.fetch(`/console/releases/${version}/${file}`, { auth: false });
      if (!response.ok) throw new Error(`GET /console/releases/${version}/${file} failed: HTTP ${response.status}`);
      const served = createHash("sha256").update(Buffer.from(await response.arrayBuffer())).digest("hex");
      if (served !== await this.digest(join(this.dist, "browser", file))) {
        throw new Error(`served ${file} does not match the Browser bundle`);
      }
    }
    const consoleUrl = `${this.apiOrigin()}/console/releases/${version}/`;
    console.log(`browser console ok: ${consoleUrl}`);

    const summary = [
      `## Desktop release ${version}`,
      "",
      `- API: ${this.apiOrigin()}`,
      ...Artifacts.flatMap(artifact => [
        `- ${artifact.label}: ${manifest.platforms[artifact.platform].url}`,
        `- ${artifact.label} SHA-256: \`${platforms[artifact.platform].sha256}\``,
      ]),
      `- Browser console: ${consoleUrl}`,
      "",
    ].join("\n");
    console.log(summary);
    if (process.env.GITHUB_STEP_SUMMARY) await appendFile(process.env.GITHUB_STEP_SUMMARY, summary);
  }

  async status() {
    const response = await this.fetch("/desktop/releases");
    const text = await response.text();
    if (!response.ok) throw new Error(`GET /desktop/releases failed: HTTP ${response.status}\n${text}`);
    console.log(text);
  }

  async run(command, argument) {
    const version = async () => argument ?? `v${await this.moduleVersion()}`;
    switch (command) {
      case "stamp": return await this.stamp(argument ?? "");
      case "upload": return await this.upload(await version());
      case "publish": return await this.publish(await version(), { fromCheckout: true });
      case "verify": return await this.verify(await version());
      case "rollback": return await this.publish(argument ?? "", { fromCheckout: false });
      case "status": return await this.status();
      default: {
        console.error(Usage);
        process.exitCode = 64;
      }
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await new Release().run(process.argv[2], process.argv[3]);
  } catch (error) {
    console.error(`error: ${error.message}`);
    process.exitCode = 1;
  }
}
