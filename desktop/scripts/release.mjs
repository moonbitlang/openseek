// Stamp, upload, and publish Desktop releases.
//
//   node scripts/release.mjs stamp X.Y.Z       stamp the version every packager builds from
//   node scripts/release.mjs upload [vX.Y.Z]   attach the checkout's artifacts to a draft GitHub release
//   node scripts/release.mjs publish [vX.Y.Z]  make the uploaded version live
//   node scripts/release.mjs verify [vX.Y.Z]   check the live release through its public URLs
//   node scripts/release.mjs rollback vX.Y.Z   republish an existing version
//   node scripts/release.mjs status            list API-owned release state
//
// GitHub Releases store the artifacts: the release tagged vX.Y.Z holds one
// asset per file below. Manifests link to openseek-api's own
// `/desktop/releases/<version>/<file>` route, which redirects to the asset, so
// moving storage later is a server configuration change. The API generates and
// atomically replaces latest.json from the filenames and SHA-256 digests it is
// told about, so a release becomes visible once every file is in place, and
// rolling back is publishing an older version again.
//
// upload, publish, and rollback need OPENSEEK_API_ORIGIN,
// OPENSEEK_DEPLOY_TOKEN, GITHUB_REPOSITORY (owner/name), and an authenticated
// gh CLI; upload also needs GITHUB_SHA, the commit a new release tags. verify
// needs only OPENSEEK_API_ORIGIN and the checkout's archives in dist/.

import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { appendFile, readFile, rm, stat, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// Everything one release ships, in upload order. `file` is both the name in
// dist/ and the asset name in the version's GitHub release; `label` names the
// download in the release summary.
const Artifacts = [
  { platform: "macos-arm64", label: "Updater ZIP", file: "SeekMoon.app.zip" },
  { platform: "macos-arm64-dmg", label: "Installer DMG", file: "SeekMoon.dmg" },
  // Also uploaded to the API: `/console/` serves it from the API origin.
  { platform: "browser", label: "Browser bundle", file: "SeekMoon.browser.tar.gz" },
  { platform: "android", label: "Android APK", file: "SeekMoon-android.apk" },
  // Renamed from Proton's `seekmoon-setup.exe` by the release workflow.
  { platform: "windows-x64", label: "Windows installer", file: "SeekMoon-windows-x64-setup.exe" },
];
const Browser = Artifacts.find(artifact => artifact.platform === "browser");

// The Desktop modules released under one version, relative to `desktop/`,
// each with the sibling modules its manifest pins.
const StampedModules = [
  { path: "moon.mod", pins: [] },
  { path: "backend/moon.mod", pins: ["openseek_desktop"] },
  { path: "app/moon.mod", pins: ["openseek_desktop", "openseek_desktop/backend"] },
  { path: "frontend/moon.mod", pins: ["openseek_desktop"] },
];

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

  repository() {
    return this.env("GITHUB_REPOSITORY");
  }

  gh(args) {
    const result = spawnSync("gh", args, { cwd: this.desktop, encoding: "utf8" });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`gh ${args.slice(0, 2).join(" ")} failed: ${result.stderr.trim()}`);
    return result.stdout;
  }

  // The release behind a version tag, draft or public. A draft has no tag
  // until it is published, so the tags endpoint cannot find it; scan the
  // repository's releases instead.
  githubRelease(version) {
    const found = this.gh(["api", "--paginate", `repos/${this.repository()}/releases?per_page=100`,
      "--jq", `.[] | select(.tag_name == ${JSON.stringify(version)})`])
      .split("\n").filter(line => line.trim()).map(line => JSON.parse(line));
    if (found.length > 1) throw new Error(`${found.length} GitHub releases are tagged ${version}`);
    return found[0];
  }

  // The asset GitHub serves for an artifact: present, with the digest GitHub
  // computed on upload, and, when the checkout holds the artifact, the very
  // bytes the checkout holds.
  githubAsset(release, artifact, local) {
    const asset = release.assets.find(asset => asset.name === artifact.file);
    if (!asset) throw new Error(`GitHub release ${release.tag_name} has no ${artifact.file}`);
    const sha256 = asset.digest?.match(/^sha256:([0-9a-f]{64})$/)?.[1];
    if (!sha256) throw new Error(`GitHub reports no SHA-256 digest for ${artifact.file}`);
    if (local && (asset.size !== local.size || sha256 !== local.sha256)) {
      throw new Error(`GitHub asset does not match the built artifact: ${artifact.platform}`);
    }
    return { size: asset.size, sha256 };
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

  async localArtifact(artifact) {
    const path = join(this.dist, artifact.file);
    const size = await stat(path).then(info => info.size, error => {
      if (error.code === "ENOENT") throw new Error(`artifact not found: ${path}`, { cause: error });
      throw error;
    });
    return { path, size, sha256: await this.digest(path) };
  }

  async stamp(version) {
    if (!/^\d+\.\d+\.\d+$/.test(version)) {
      throw new Error(`release version must be three dot-separated numbers: ${version}`);
    }
    // SSH downloads the CLI release, which has its own version in the root manifest.
    const manifest = await readFile(join(this.desktop, "..", "moon.mod"), "utf8");
    const cliVersion = manifest.match(/^version = "([^"]+)"$/m)?.[1];
    if (!cliVersion) throw new Error("could not read CLI version from root moon.mod");
    const path = join(this.desktop, "backend/ssh/version.mbt");
    const source = await readFile(path, "utf8");
    const declaration = /^const CliRelease = "[^"\r\n]*"$/gm;
    if ([...source.matchAll(declaration)].length !== 1) {
      throw new Error("expected one CliRelease constant in backend/ssh/version.mbt");
    }
    await writeFile(path, source.replace(declaration, () => `const CliRelease = ${JSON.stringify(cliVersion)}`));
    // The Desktop modules are released together. Keep their versions and the
    // workspace dependency pins between them on the same value.
    for (const { path, pins } of StampedModules) {
      const modulePath = join(this.desktop, path);
      let module = await readFile(modulePath, "utf8");
      if (!/^version = "[^"]+"$/m.test(module)) throw new Error(`${path} has no version line`);
      module = module.replace(/^version = "[^"]+"$/m, `version = "${version}"`);
      for (const pin of pins) {
        const pinned = new RegExp(`"${pin}@[^"]+"`);
        if (!pinned.test(module)) throw new Error(`${path} has no ${pin} dependency`);
        module = module.replace(pinned, `"${pin}@${version}"`);
      }
      await writeFile(modulePath, module);
    }
    const configPath = join(this.desktop, "proton.project.json");
    const config = JSON.parse(await readFile(configPath, "utf8"));
    config.package.version = version;
    await writeFile(configPath, `${JSON.stringify(config, null, 2)}\n`);
    for (const { path, pins } of StampedModules) {
      const module = await readFile(join(this.desktop, path), "utf8");
      if (!module.includes(`version = "${version}"`)) {
        throw new Error(`${path} did not take the version`);
      }
      for (const pin of pins) {
        if (!module.includes(`"${pin}@${version}"`)) {
          throw new Error(`${path} did not take the ${pin} dependency`);
        }
      }
    }
    if (JSON.parse(await readFile(configPath, "utf8")).package.version !== version) {
      throw new Error("proton.project.json did not take the version");
    }
    console.log(`stamped ${version}`);
  }

  async isPublished(version) {
    const sealed = await this.fetch(`/console/releases/${version}/index.html`);
    await sealed.body?.cancel();
    if (sealed.status === 200) return true;
    if (sealed.status === 404) return false;
    throw new Error(`could not determine whether ${version} is published: HTTP ${sealed.status}`);
  }

  async upload(version) {
    await this.checkoutVersion(version);
    const repository = this.repository();
    const commit = this.env("GITHUB_SHA");
    let release = this.githubRelease(version);
    if (release && !release.draft) {
      // Publish makes the release public just before the API publish, so a
      // public release may never have reached latest.json. The next scheduled
      // run then resolves the same version from a newer commit, and adopting
      // the older assets would ship that commit's version without its changes.
      if (release.target_commitish !== commit) {
        throw new Error(`${version} is public on GitHub from ${release.target_commitish}, not ${commit}; ` +
          `publish it by re-running the run that built it, or release this commit under an unused version`);
      }
      // A public release serves its assets under immutable URLs that CDNs may
      // already cache. A retry after that point adopts those bytes instead of
      // replacing them with a nondeterministic rebuild.
      console.log(`${version} is already public on GitHub; reusing its assets`);
      this.gh(["release", "download", version, "--repo", repository, "--dir", this.dist, "--clobber",
        ...Artifacts.flatMap(artifact => ["--pattern", artifact.file])]);
      for (const artifact of Artifacts) this.githubAsset(release, artifact, await this.localArtifact(artifact));
    } else {
      // Until the release is public, a retry replaces the provisional assets
      // of an earlier attempt, and the tag it will create follows them to
      // this run's commit.
      if (!release) {
        this.gh(["release", "create", version, "--repo", repository, "--draft",
          "--target", commit, "--title", `SeekMoon ${version}`,
          "--notes", `SeekMoon Desktop ${version}.`]);
      } else if (release.target_commitish !== commit) {
        this.gh(["release", "edit", version, "--repo", repository, "--target", commit]);
      }
      for (const artifact of Artifacts) {
        const local = await this.localArtifact(artifact);
        this.gh(["release", "upload", version, local.path, "--repo", repository, "--clobber"]);
      }
      release = this.githubRelease(version);
      for (const artifact of Artifacts) {
        this.githubAsset(release, artifact, await this.localArtifact(artifact));
        console.log(`${artifact.platform} verified on GitHub`);
      }
    }
    await this.unpackBrowser();
    if (await this.isPublished(version)) {
      console.log(`${version} is ready to publish again`);
      return;
    }

    // `/console/` remains on the API origin, so the Browser archive is also
    // uploaded to the API. Desktop packages live only on GitHub.
    const browser = await this.localArtifact(Browser);
    const recorded = await this.fetchJson(`/desktop/releases/${version}/${Browser.file}?platform=browser`, {
      method: "PUT", body: await readFile(browser.path),
    });
    if (recorded.sha256 !== browser.sha256) {
      throw new Error(`DIGEST MISMATCH: API recorded ${recorded.sha256} for Browser`);
    }
    console.log(`${version} is ready to publish`);
  }

  // The publishing runner builds nothing, so the Browser directory that the
  // console verification compares against is unpacked from the archive in
  // dist/: the bytes GitHub holds and the API received.
  async unpackBrowser() {
    await rm(join(this.dist, "browser"), { recursive: true, force: true });
    this.commandRun("tar", ["-xzf", join(this.dist, Browser.file), "-C", this.dist]);
  }

  // Publish and rollback share the same API contract. The runner supplies the
  // filenames and the SHA-256 digests GitHub computed; the API knows only the
  // public release base URL and owns latest.json generation.
  async publish(version, { fromCheckout }) {
    if (fromCheckout) await this.checkoutVersion(version);
    else if (!/^v[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(version)) throw new Error(`invalid rollback version: ${version}`);
    const release = this.githubRelease(version);
    if (!release) throw new Error(`${version} has no GitHub release`);
    const platforms = {};
    for (const artifact of Artifacts) {
      const local = fromCheckout ? await this.localArtifact(artifact) : undefined;
      const served = this.githubAsset(release, artifact, local);
      platforms[artifact.platform] = { file: artifact.file, sha256: served.sha256 };
    }

    // The manifest sends clients to these assets, which anonymous clients can
    // only download once the release is public. Marking it latest keeps the
    // repository's latest release in step with latest.json, rollbacks included.
    this.gh(["release", "edit", version, "--repo", this.repository(), "--draft=false", "--latest"]);
    const response = await this.fetchJson(`/desktop/releases/${version}/publish`, {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ platforms }),
    });
    this.verifyManifest(response.published, version, platforms);
    // Read the canonical file back from the API. This verifies that publish
    // wrote the same manifest it returned.
    const latest = await this.fetchJson("/desktop/releases/latest.json");
    this.verifyManifest(latest, version, platforms);
    console.log(JSON.stringify(latest, null, 2));
  }

  // The API must have published exactly the requested platforms, each at its
  // versioned file with the digest GitHub reported.
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
  // compared with the archives in dist/ (the GitHub bytes once `upload` ran).
  async verify(version) {
    await this.checkoutVersion(version);
    const manifest = await this.fetchJson("/desktop/releases/latest.json", { auth: false });
    const platforms = {};
    for (const artifact of Artifacts) {
      const local = await this.localArtifact(artifact);
      platforms[artifact.platform] = { file: artifact.file, sha256: local.sha256, size: local.size };
    }
    this.verifyManifest(manifest, version, platforms);

    await this.verifyDownloads(manifest);

    // The API serves this version as its one current Browser bundle: the same
    // document at every page route, with its resources under /assets/.
    const bare = version.replace(/^v/, "");
    const current = await this.fetchJson("/browser/releases/current.json", { auth: false });
    if (current?.version !== bare) throw new Error(`browser current.json version ${current?.version} is not ${bare}`);
    for (const [file, path] of [
      ["index.html", "/cloud"],
      ["assets/frontend.js", "/assets/frontend.js"],
    ]) {
      const response = await this.fetch(path, { auth: false });
      if (!response.ok) throw new Error(`GET ${path} failed: HTTP ${response.status}`);
      const served = createHash("sha256").update(Buffer.from(await response.arrayBuffer())).digest("hex");
      if (served !== await this.digest(join(this.dist, "browser", file))) {
        throw new Error(`served ${file} does not match the Browser bundle`);
      }
    }
    const consoleUrl = `${this.apiOrigin()}/cloud`;
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

  async verifyDownloads(manifest) {
    // Follow GitHub's redirect to its asset host and hash the streamed bytes.
    for (const artifact of Artifacts) {
      const { url } = manifest.platforms[artifact.platform];
      const local = await this.localArtifact(artifact);
      const download = await fetch(url, { headers: { "accept-encoding": "identity" } });
      if (!download.ok) throw new Error(`GET ${url} failed: HTTP ${download.status}`);
      const hash = createHash("sha256");
      let size = 0;
      for await (const chunk of download.body) {
        hash.update(chunk);
        size += chunk.length;
      }
      if (size !== local.size || hash.digest("hex") !== local.sha256) {
        throw new Error(`download digest mismatch: ${url}`);
      }
      console.log(`${artifact.platform} ok: ${url}`);
    }
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
