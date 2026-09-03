import { createHash } from "node:crypto";
import { createReadStream, existsSync } from "node:fs";
import { chmod, cp, mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { execFileSync, spawnSync } from "node:child_process";

const Hosts = {
  darwin: {
    command: "macos", platform: "macos-arm64", moonbit: "darwin-aarch64",
    ripgrep: "aarch64-apple-darwin",
    sha: "378e973289176ca0c6054054ee7f631a065874a352bf43f0fa60ef079b6ba715",
    esbuild: { package: "darwin-arm64", binary: "bin/esbuild",
      sha: "5d64cc9bc527d598450b5f8d47ff293eb9f3aea38dd9eff67fd55d228c5ccb43" },
  },
  linux: {
    command: "linux", platform: "linux-x64", moonbit: "linux-x86_64",
    ripgrep: "x86_64-unknown-linux-musl",
    sha: "1c9297be4a084eea7ecaedf93eb03d058d6faae29bbc57ecdaf5063921491599",
    esbuild: { package: "linux-x64", binary: "bin/esbuild",
      sha: "9ed00ab5330c94386f3273eda99a1fb0e8f37cfd6cb5270e4ad2fe3527da3546" },
  },
  win32: {
    command: "windows", platform: "windows-x64", moonbit: "windows-x86_64",
    ripgrep: "x86_64-pc-windows-msvc",
    sha: "124510b94b6baa3380d051fdf4650eaa80a302c876d611e9dba0b2e18d87493a",
    esbuild: { package: "win32-x64", binary: "esbuild.exe",
      sha: "5c5d62da7572b57ddc1fa3caedc36c1218b5d8d02ce9c7ee70e3339fce4453c4" },
  },
};

const EsbuildVersion = "0.28.1";

// These archives already contain browser-ready distributions. Fetching the
// exact tarballs avoids installing a package manager or recreating its
// dependency graph during an application build.
const WebArchives = {
  xterm: {
    filename: "xterm-5.5.0.tgz",
    url: "https://registry.npmjs.org/@xterm/xterm/-/xterm-5.5.0.tgz",
    sha: "bd954fa721872170188cc5d7e83e88db3c83c9a18a4e8d24c2783d26491f59d2",
    path: "node_modules/@xterm/xterm",
  },
  fit: {
    filename: "addon-fit-0.10.0.tgz",
    url: "https://registry.npmjs.org/@xterm/addon-fit/-/addon-fit-0.10.0.tgz",
    sha: "917ac44972453d5eed52edc1e50260c76398ce48cf2290c2e60671102bba0b33",
    path: "node_modules/@xterm/addon-fit",
  },
  webLinks: {
    filename: "addon-web-links-0.11.0.tgz",
    url: "https://registry.npmjs.org/@xterm/addon-web-links/-/addon-web-links-0.11.0.tgz",
    sha: "cad54687a1447f87cd8dd9ce454d4d657d18cc7179e9179908f391b4512f74a0",
    path: "node_modules/@xterm/addon-web-links",
  },
  mermaid: {
    filename: "mermaid-11.16.0.tgz",
    url: "https://registry.npmjs.org/mermaid/-/mermaid-11.16.0.tgz",
    sha: "ff48c94a0a0458b377a5187ad01407184d2a182e6476c2015b7068ff58355fae",
    path: "mermaid",
  },
};

// Keep the packaged reference docs tied to the toolchain seed. The host uses
// this exact tree as OPENSEEK_REFERENCES after copying the seed into place.
const MoonbitDocsCommit = "750cc5a41679256441a3efa75487420028cff2e1";
const MoonbitDocsRelDir = join("share", "doc", "moonbit");

class Build {
  constructor(command, argv) {
    this.command = command;
    this.argv = argv;
    this.desktop = fileURLToPath(new URL("../", import.meta.url));
    this.repo = resolve(this.desktop, "..");
    this.host = Hosts[process.platform];
  }

  commandRun(program, args, { cwd = this.desktop, env = {} } = {}) {
    console.log(`$ ${program} ${args.join(" ")}`);
    const result = spawnSync(program, args, {
      cwd, env: { ...process.env, ...env }, stdio: "inherit", shell: false,
    });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`${program} exited with ${result.status ?? result.signal}`);
  }

  commandOutput(program, args) {
    return execFileSync(program, args, { cwd: this.desktop, encoding: "utf8" });
  }

  parse() {
    const options = { help: { type: "boolean", short: "h" } };
    if (this.command !== "dev") options.release = { type: "boolean" };
    if (this.command === "macos" || this.command === "windows") {
      options.target = { type: "string", multiple: true };
    }
    if (this.command === "macos") {
      options["no-open"] = { type: "boolean" };
      options.sign = { type: "string" };
      options.notarize = { type: "string" };
    }
    const { values } = parseArgs({ args: this.argv, options, strict: true });
    if (values.help) {
      const suffix = this.command === "macos"
        ? "[--release] [--target app|dmg|zip] [--sign IDENTITY] [--notarize PROFILE] [--no-open]"
        : this.command === "windows"
          ? "[--release] [--target app|zip|installer]"
          : this.command === "linux" || this.command === "browser" ? "[--release]" : "";
      console.log(`Usage: moon run ./desktop/package/${this.command} -- ${suffix}`.trim());
      return null;
    }
    const targets = values.target ?? (this.command === "macos"
      ? ["app"] : this.command === "windows" ? ["zip", "installer"] : []);
    const allowed = this.command === "macos"
      ? ["app", "dmg", "zip"] : ["app", "zip", "installer"];
    for (const target of targets) {
      if (!allowed.includes(target)) throw new Error(
        `unsupported ${this.command} package target '${target}'; expected ${allowed.join(", ")}`,
      );
    }
    if (values.notarize && !values.sign) throw new Error("--notarize requires --sign");
    if (values.notarize && !targets.includes("dmg")) throw new Error("--notarize requires --target dmg");
    if (values.sign && !targets.some(target => target === "dmg" || target === "zip")) {
      throw new Error("--sign requires a distribution target (--target dmg or --target zip)");
    }
    return { release: values.release ?? false, targets, sign: values.sign,
      notarize: values.notarize, open: !values["no-open"] };
  }

  async proton(args, env = {}) {
    const manifest = await readFile(join(this.desktop, "moon.mod"), "utf8");
    const version = manifest.match(/"moonbit-community\/proton@([^\"]+)"/)?.[1];
    if (!version) throw new Error("desktop/moon.mod does not pin proton");
    await this.commandRun("moonx", [`moonbit-community/proton_cli@${version}`, ...args], { env });
  }

  async digest(path) {
    const hash = createHash("sha256");
    for await (const chunk of createReadStream(path)) hash.update(chunk);
    return hash.digest("hex");
  }

  async download(url, path, expected) {
    if (existsSync(path) && (!expected || await this.digest(path) === expected)) return;
    await rm(path, { force: true });
    await mkdir(dirname(path), { recursive: true });
    const partial = `${path}.part`;
    await rm(partial, { force: true });
    const curl = process.platform === "win32" ? "curl.exe" : "curl";
    await this.commandRun(curl, ["-fL", "--retry", "5", "--retry-all-errors",
      "--retry-delay", "2", "--connect-timeout", "30", url, "-o", partial]);
    await rename(partial, path);
    // Never package bytes that do not match the checked-in upstream digest.
    if (expected && await this.digest(path) !== expected) {
      await rm(path, { force: true });
      throw new Error(`SHA-256 mismatch for ${path}`);
    }
  }

  async webAssets() {
    if (!this.host) throw new Error(`browser assets cannot build on ${process.platform}/${process.arch}`);
    const vendor = join(this.desktop, "target/vendor-web");
    const work = join(vendor, "work");
    const output = join(this.desktop, "target/web");

    // Cache only verified archives. Extraction and generated outputs are
    // recreated so an interrupted build cannot leave a partial asset tree.
    await rm(work, { recursive: true, force: true });
    await rm(output, { recursive: true, force: true });
    await mkdir(work, { recursive: true });
    await mkdir(output, { recursive: true });
    for (const archive of Object.values(WebArchives)) {
      const cached = join(vendor, "cache", archive.filename);
      await this.download(archive.url, cached, archive.sha);
      const extracted = join(work, archive.path);
      await mkdir(extracted, { recursive: true });
      await this.commandRun("tar", ["-xf", cached, "-C", extracted, "--strip-components=1"]);
    }

    const esbuild = this.host.esbuild;
    const esbuildArchive = join(vendor, "cache", `esbuild-${esbuild.package}-${EsbuildVersion}.tgz`);
    await this.download(
      `https://registry.npmjs.org/@esbuild/${esbuild.package}/-/${esbuild.package}-${EsbuildVersion}.tgz`,
      esbuildArchive,
      esbuild.sha,
    );
    const esbuildRoot = join(work, "esbuild");
    await mkdir(esbuildRoot, { recursive: true });
    await this.commandRun("tar", ["-xf", esbuildArchive, "-C", esbuildRoot, "--strip-components=1"]);
    const esbuildBinary = join(esbuildRoot, esbuild.binary);
    if (process.platform !== "win32") await chmod(esbuildBinary, 0o755);

    // esbuild remains the authority for CSS imports, URL handling, and the
    // xterm module graph. It is a verified standalone tool, not an npm install.
    for (const [entry, name] of [
      [join(this.desktop, "app.css"), "app.css"],
      [join(this.desktop, "frontend/build/viewer.css"), "viewer.css"],
    ]) {
      await this.commandRun(esbuildBinary, [entry, "--bundle", "--external:*.ttf",
        "--external:*.woff2", `--outfile=${join(output, name)}`]);
    }
    await cp(join(this.desktop, "frontend/build/xterm-entry.js"), join(work, "xterm-entry.js"));
    await cp(join(this.desktop, "frontend/build/xterm.css"), join(work, "xterm.css"));
    await this.commandRun(esbuildBinary, [join(work, "xterm-entry.js"), "--bundle",
      "--format=iife", "--platform=browser", "--minify",
      `--outfile=${join(output, "xterm.js")}`]);
    await this.commandRun(esbuildBinary, [join(work, "xterm.css"), "--bundle", "--minify",
      `--outfile=${join(output, "xterm.css")}`]);

    const mermaid = join(output, "mermaid");
    await mkdir(join(mermaid, "chunks"), { recursive: true });
    await cp(join(work, "mermaid/dist/mermaid.esm.min.mjs"), join(mermaid, "mermaid.esm.min.mjs"));
    await cp(join(work, "mermaid/dist/chunks/mermaid.esm.min"), join(mermaid, "chunks/mermaid.esm.min"), { recursive: true });
    await cp(join(work, "mermaid/LICENSE"), join(mermaid, "LICENSE"));
  }

  async web(profile, browser = false) {
    await this.webAssets();
    const release = profile === "release" ? ["--release"] : [];
    if (browser) {
      await this.commandRun("moon", ["build", "frontend/browser", "--target", "js", ...release]);
      const output = join(this.desktop, "dist/browser");
      await rm(output, { recursive: true, force: true });
      await mkdir(output, { recursive: true });
      await cp(join(this.desktop, "frontend/browser/index.html"), join(output, "index.html"));
      await cp(join(this.repo, `_build/js/${profile}/build/openseek_desktop/frontend/browser/browser.js`), join(output, "browser.js"));
      await this.sharedWeb(output);
      return;
    }
    await this.commandRun("moon", ["build", "frontend/desktop", "--target", "js", ...release]);
    await this.commandRun("moon", ["build", "cmd/viz_app", "--target", "js", ...release], { cwd: this.repo });
  }

  async sharedWeb(output) {
    const generated = join(this.desktop, "target/web");
    for (const name of ["app.css", "viewer.css", "xterm.js", "xterm.css"]) {
      await cp(join(generated, name), join(output, name));
    }
    await cp(join(this.repo, "editor/viewer/browser/view/codicon/codicon.ttf"), join(output, "codicon.ttf"));
    await cp(join(this.desktop, "fonts"), join(output, "fonts"), { recursive: true });
    await cp(join(generated, "mermaid"), join(output, "mermaid"), { recursive: true });
  }

  async native(profile) {
    const release = profile === "release" ? ["--release"] : [];
    const env = this.command === "macos" ? { MACOSX_DEPLOYMENT_TARGET: "12.0" } : {};
    await this.proton(["cef", "setup"], env);
    if (this.command === "macos") {
      await this.commandRun("moon", ["build", ".", "--target", "native", "--target-dir", "target/moonbuild/macos-12.0", ...release], { env });
      await this.commandRun("moon", ["build", "cmd/openseek", "--target", "native", "--target-dir", "desktop/target/moonbuild/macos-12.0", ...release], { cwd: this.repo, env });
      const host = join(this.desktop, `target/moonbuild/macos-12.0/native/${profile}/build/openseek_desktop/openseek_desktop.exe`);
      const expected = join(this.repo, `_build/native/${profile}/build/openseek_desktop/openseek_desktop.exe`);
      await mkdir(dirname(expected), { recursive: true });
      await cp(host, expected);
      return join(this.desktop, `target/moonbuild/macos-12.0/native/${profile}/build/bobzhang/openseek/cmd/openseek/openseek.exe`);
    }
    const warning = this.command === "windows" ? ["--warn-list", "-20"] : [];
    await this.commandRun("moon", ["build", ".", "--target", "native", ...warning, ...release]);
    await this.commandRun("moon", ["build", "cmd/openseek", "--target", "native", ...release], { cwd: this.repo });
    return join(this.repo, `_build/native/${profile}/build/bobzhang/openseek/cmd/openseek/openseek.exe`);
  }

  async vendors() {
    const rgName = `ripgrep-15.1.0-${this.host.ripgrep}`;
    const extension = this.command === "windows" ? "zip" : "tar.gz";
    const rgArchive = join(this.desktop, `target/vendor-ripgrep/cache/${rgName}.${extension}`);
    await this.download(`https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/${rgName}.${extension}`, rgArchive, this.host.sha);
    const rg = join(this.desktop, `target/vendor-ripgrep/work/${this.host.ripgrep}`);
    await rm(rg, { recursive: true, force: true });
    await mkdir(rg, { recursive: true });
    await this.commandRun("tar", ["-xf", rgArchive, "-C", rg, "--strip-components=1"]);

    const version = (await readFile(join(this.desktop, ".moonbit-version"), "utf8")).trim();
    const archiveExt = this.command === "windows" ? "zip" : "tar.gz";
    const cache = join(this.desktop, "target/moonbit/cache");
    const binary = join(cache, `moonbit-${this.host.moonbit}-${version}.${archiveExt}`);
    const core = join(cache, `core-${version}.${archiveExt}`);
    const encoded = encodeURIComponent(version);
    await this.download(`https://cli.moonbitlang.com/binaries/${encoded}/moonbit-${this.host.moonbit}.${archiveExt}`, binary);
    await this.download(`https://cli.moonbitlang.com/cores/core-${encoded}.${archiveExt}`, core);
    const seed = join(this.desktop, `target/moonbit/${this.host.platform}/seed`);
    await rm(seed, { recursive: true, force: true });
    await mkdir(join(seed, "lib"), { recursive: true });
    await this.commandRun("tar", ["-xf", binary, "-C", seed]);
    await this.commandRun("tar", ["-xf", core, "-C", join(seed, "lib")]);
    await rm(join(seed, "lib/core/_build"), { recursive: true, force: true });

    const docsArchive = join(cache, `moonbit-docs-${MoonbitDocsCommit}.tar.gz`);
    await this.download(
      `https://codeload.github.com/moonbitlang/moonbit-docs/tar.gz/${MoonbitDocsCommit}`,
      docsArchive,
    );
    const docs = join(seed, MoonbitDocsRelDir);
    await mkdir(docs, { recursive: true });
    await this.commandRun("tar", ["-xzf", docsArchive, "-C", docs, "--strip-components=1"]);
    await rm(join(docs, "_sphinx_design_static"), { recursive: true, force: true });
    for (const entry of ["index.md", "language", "toolchain"]) {
      if (!existsSync(join(docs, entry))) throw new Error(`moonbit-docs archive is missing ${entry}`);
    }

    if (this.command !== "windows") await this.commandRun("chmod", ["-R", "+x", join(seed, "bin")]);
    const compiler = join(seed, `bin/moonc${this.command === "windows" ? ".exe" : ""}`);
    const actual = (await this.commandOutput(compiler, ["-v"])).trim().split(/\s+/)[0].replace(/^v/, "");
    if (actual !== version) {
      await rm(binary, { force: true });
      await rm(core, { force: true });
      throw new Error(`downloaded MoonBit ${actual}, expected ${version}`);
    }
    await writeFile(
      join(seed, ".openseek-moonbit-seed-version"),
      `${version} docs=${MoonbitDocsCommit} docsdir=share/doc/moonbit\n`,
    );
    return { rg, seed };
  }

  async stage(profile, engine, vendors) {
    const root = join(this.desktop, "seekmoon");
    await rm(root, { recursive: true, force: true });
    await mkdir(join(root, "web/viz"), { recursive: true });
    await mkdir(join(root, "bin"), { recursive: true });
    await mkdir(join(root, "licenses/ripgrep"), { recursive: true });
    await cp(join(this.desktop, "index.html"), join(root, "web/index.html"));
    await cp(join(this.repo, `_build/js/${profile}/build/openseek_desktop/frontend/desktop/desktop.js`), join(root, "web/frontend.js"));
    await cp(join(this.repo, "web/index.html"), join(root, "web/viz/index.html"));
    await cp(join(this.repo, `_build/js/${profile}/build/bobzhang/openseek-viz-app/openseek-viz-app.js`), join(root, "web/viz/viz_app.js"));
    await this.sharedWeb(join(root, "web"));
    const suffix = this.command === "windows" ? ".exe" : "";
    await cp(engine, join(root, `bin/openseek${suffix}`));
    await cp(join(vendors.rg, `rg${suffix}`), join(root, `bin/rg${suffix}`));
    await cp(join(vendors.rg, "LICENSE-MIT"), join(root, "licenses/ripgrep/LICENSE-MIT"));
    await cp(join(vendors.rg, "UNLICENSE"), join(root, "licenses/ripgrep/UNLICENSE"));
    await cp(vendors.seed, join(root, `toolchains/moonbit/${this.host.platform}`), { recursive: true, dereference: true });
    if (this.command !== "windows") {
      await chmod(join(root, "bin/openseek"), 0o755);
      await chmod(join(root, "bin/rg"), 0o755);
    } else {
      const path = join(root, "bin/openseek.exe");
      const bytes = Buffer.from(await readFile(path));
      if (bytes[0] !== 0x4d || bytes[1] !== 0x5a) throw new Error(`${engine} is not a PE executable`);
      const pe = bytes.readUInt32LE(0x3c);
      if (bytes.toString("ascii", pe, pe + 4) !== "PE\0\0" || bytes.readUInt16LE(pe + 20) < 70) throw new Error(`${engine} has an invalid PE header`);
      bytes.writeUInt16LE(2, pe + 24 + 68);
      await writeFile(path, bytes);
    }
  }

  async package(options) {
    if (!this.host || this.host.command !== this.command) throw new Error(`${this.command} packaging cannot run on ${process.platform}/${process.arch}`);
    if ((this.command === "macos" && process.arch !== "arm64") || (this.command !== "macos" && process.arch !== "x64")) {
      throw new Error(`${this.command} packaging does not support ${process.arch}`);
    }
    const profile = options.release ? "release" : "debug";
    await this.web(profile);
    const engine = await this.native(profile);
    const vendors = await this.vendors();
    await this.stage(profile, engine, vendors);
    const formats = this.command === "macos"
      ? ["app", ...options.targets.filter(target => target !== "app")]
      : this.command === "windows"
        ? options.targets.map(target => target === "installer" ? "nsis" : target)
        : ["appimage"];
    const args = ["-C", ".", "package", "--config", "proton.project.json"];
    for (const format of [...new Set(formats)]) args.push("--format", format);
    if (options.release) args.push("--release");
    if (options.sign) args.push("--sign");
    if (options.notarize) args.push("--notarize");
    const env = {};
    if (this.command === "macos") env.PROTON_MACOS_ENTITLEMENTS = join(this.desktop, "package/macos/SeekMoon.entitlements");
    if (options.sign) env.PROTON_MACOS_SIGNING_IDENTITY = options.sign;
    if (options.notarize) env.PROTON_NOTARY_PROFILE = options.notarize;
    if (this.command === "macos") env.MACOSX_DEPLOYMENT_TARGET = "12.0";
    if (this.command === "linux") {
      const tool = join(this.desktop, "target/tools/appimagetool");
      await this.download("https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage", tool);
      await chmod(tool, 0o755);
      env.PATH = `${dirname(tool)}:${process.env.PATH}`;
      env.APPIMAGE_EXTRACT_AND_RUN = "1";
    }
    await this.proton(args, env);
    if (this.command === "macos" && options.open) await this.commandRun("open", [join(this.desktop, "dist/SeekMoon.app")]);
  }

  async run() {
    if (!["macos", "windows", "linux", "browser", "dev"].includes(this.command)) {
      throw new Error("expected build command: macos, windows, linux, browser, or dev");
    }
    const options = this.parse();
    if (!options) return;
    if (this.command === "browser") return await this.web(options.release ? "release" : "debug", true);
    if (this.command === "dev") {
      await this.web("debug");
      await this.commandRun("moon", ["build", "cmd/openseek", "--target", "native"], { cwd: this.repo });
      return await this.proton(["-C", ".", "dev", "--config", "proton.project.json", "--no-frontend", "--setup"]);
    }
    await this.package(options);
  }
}

try {
  await new Build(process.argv[2], process.argv.slice(3)).run();
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
}
