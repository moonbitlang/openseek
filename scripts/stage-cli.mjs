import { chmod, cp, mkdir, rm } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { stageResources } from "../desktop/package/resources.mjs";

// Stage a relocatable CLI installation, using the same layout as Desktop.
const [artifact, output = ".tmp/openseek"] = process.argv.slice(2);
if (!artifact) throw new Error("usage: node scripts/stage-cli.mjs <executable> [output-directory]");
const root = resolve(output);
const source = resolve(artifact);
const resources = fileURLToPath(new URL("../share/", import.meta.url));
if (resolve(root, "share") === resolve(resources)) throw new Error("output must not replace the checked-in share directory");
const executable = join(root, "bin", process.platform === "win32" ? "openseek.exe" : "openseek");
await mkdir(join(root, "bin"), { recursive: true });
if (source !== executable) await cp(source, executable);
if (process.platform !== "win32") await chmod(executable, 0o755);
// Replacing only this generated resource tree also removes deleted source files.
await rm(join(root, "share"), { recursive: true, force: true });
await stageResources(resources, join(root, "share"));
console.log(executable);
