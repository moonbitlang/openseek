import { execFileSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { copyFile, mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const modules = {
  root: { directory: ".", name: "moonbitlang/openseek" },
  protocol: { directory: "protocol", name: "moonbitlang/openseek_protocol" },
  tools_sdk: { directory: "tools_sdk", name: "moonbitlang/openseek_tools" },
};

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

async function publish(repository, target) {
  if (!Object.hasOwn(modules, target)) {
    throw new Error("Usage: node scripts/publish.mjs <root|protocol|tools_sdk>");
  }
  const module = modules[target];
  const temporary = await mkdtemp(join(tmpdir(), "openseek-publish-"));
  try {
    await stageModule(repository, temporary, module);
    console.log(`Publishing ${module.name}`);
    moon(["update"], temporary);
    moon(["publish"], temporary);
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const repository = resolve(dirname(fileURLToPath(import.meta.url)), "..");
  publish(repository, process.argv.length === 3 ? process.argv[2] : undefined).catch(error => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
