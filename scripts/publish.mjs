import { execFileSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { copyFile, mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { embedInspectAssets } from "./embed_inspect_assets.mjs";

const modules = {
  root: { directory: ".", name: "moonbitlang/openseek" },
  protocol: { directory: "protocol", name: "moonbitlang/openseek_protocol" },
  tools_sdk: { directory: "tools_sdk", name: "moonbitlang/openseek_tools" },
  // The session viewer server. Its package embeds the viewer shell and a
  // fresh release frontend bundle, so `moonx moonbitlang/inspect` needs no
  // files beside the wasm binary (see prepareInspect).
  inspect: { directory: "inspect", name: "moonbitlang/inspect", prepare: prepareInspect },
};

const vizBundle = "_build/js/release/build/moonbitlang/openseek-viz-app/openseek-viz-app.js";

// Build the release frontend in the workspace (cmd/viz_app resolves openseek
// from the checkout, so MOON_WORK stays on), then overwrite the staged
// package's empty generated_assets.mbt with it and web/index.html. Both come
// from the same checkout as the server, so the bundle always matches the API.
async function prepareInspect(repository, staged) {
  execFileSync("moon", ["build", "--target", "js", "--release", "cmd/viz_app"], {
    cwd: repository,
    env: { ...process.env, NO_COLOR: "1" },
    stdio: ["ignore", "inherit", "inherit"],
  });
  const { indexBytes, bundleBytes } = await embedInspectAssets(
    join(repository, "web/index.html"),
    join(repository, vizBundle),
    join(staged, "generated_assets.mbt"),
  );
  console.log(`Embedded web/index.html (${indexBytes} chars) and viz_app.js (${bundleBytes} chars)`);
}

// These exclusions belong to the root module only. A repository-level
// .moonignore would also exclude the members when publishing them separately.
const rootExclusions = [
  "desktop", "editor", "protocol", "tools_sdk", "cmd/viz_app", "inspect",
  "tests", "eval", "docs/plans", ".github", ".agents", ".codex",
  "moon.work", "justfile", "AGENTS.md", "agent-improvement-guide.md",
  "improvement.md", "shrink_package.md", "desktop-dev.html", "web/viz_app.js",
];
const generatedDirectories = new Set([
  "_build", "target", ".mooncakes", "node_modules", ".moonagent", ".repos",
  ".openseek", ".claude", ".proton", ".vscode", ".DS_Store",
]);

// Copy current tracked source, including each member's own ignore configuration.
// Independent directories have no ancestor Git checkout or workspace, so root
// packaging rules and local workspace overrides cannot leak into member releases.
async function stageModule(repository, cwd, module) {
  const deleted = new Set(execFileSync("git", ["ls-files", "--deleted", "-z"], {
    cwd: repository, encoding: "utf8",
  }).split("\0"));
  const files = execFileSync("git", ["ls-files", "-z"], {
    cwd: repository, encoding: "utf8",
  }).split("\0").filter(file => file && !deleted.has(file));
  await mkdir(cwd, { recursive: true });
  for (const file of files) {
    if (file.split("/").some(part => generatedDirectories.has(part))) continue;
    let relative = file;
    if (module.directory === ".") {
      if (rootExclusions.some(path => file === path || file.startsWith(`${path}/`))) continue;
    } else {
      const prefix = `${module.directory}/`;
      if (!file.startsWith(prefix)) continue;
      relative = file.slice(prefix.length);
    }
    const target = join(cwd, relative);
    await mkdir(dirname(target), { recursive: true });
    // Materialize tracked README symlinks so the staged package is standalone.
    await copyFile(join(repository, file), target);
  }
}

function moon(args, cwd) {
  execFileSync("moon", args, {
    cwd,
    env: { ...process.env, NO_COLOR: "1", MOON_WORK: "off" },
    stdio: ["ignore", "inherit", "inherit"],
  });
}

const usage = "Usage: node scripts/publish.mjs <root|protocol|tools_sdk|inspect> [--stage-only <dir>]";

// Stage `target` and publish it. With `stageOnly`, write the staged package to
// that directory and stop, so CI or a person can build and inspect exactly
// what would be published.
async function publish(repository, target, stageOnly) {
  if (!Object.hasOwn(modules, target)) {
    throw new Error(usage);
  }
  const module = modules[target];
  const temporary = stageOnly ?? await mkdtemp(join(tmpdir(), "openseek-publish-"));
  try {
    await stageModule(repository, temporary, module);
    await module.prepare?.(repository, temporary);
    if (stageOnly) {
      console.log(`Staged ${module.name} in ${temporary}`);
      return;
    }
    console.log(`Publishing ${module.name}`);
    moon(["update"], temporary);
    moon(["publish"], temporary);
  } finally {
    if (!stageOnly) await rm(temporary, { recursive: true, force: true });
  }
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const repository = resolve(dirname(fileURLToPath(import.meta.url)), "..");
  const [target, flag, stageDir, ...rest] = process.argv.slice(2);
  const valid = rest.length === 0 && (flag === undefined || (flag === "--stage-only" && stageDir));
  (valid ? publish(repository, target, flag ? resolve(stageDir) : undefined) : Promise.reject(new Error(usage))).catch(error => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
