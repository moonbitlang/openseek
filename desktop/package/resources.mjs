import { createHash } from "node:crypto";
import { cp, readFile, readdir, stat } from "node:fs/promises";
import { join } from "node:path";

// Validate and copy the installation resource tree. The returned content hash
// identifies the copied snapshot independently of the MoonBit toolchain.
//
// A `_build` directory under the tree is a local build's leftover, not a
// resource: shipping it would both change the hash for no reason and let a
// later step write into the signed bundle, breaking its seal.
export async function stageResources(source, destination) {
  for (const entry of ["doc/moonbit/index.md", "doc/moonbit/language", "doc/moonbit/toolchain", "workflow"]) {
    await stat(join(source, entry));
  }
  const hash = createHash("sha256");
  async function visit(directory, prefix = "") {
    const entries = await readdir(directory, { withFileTypes: true });
    entries.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
    for (const entry of entries) {
      const name = `${prefix}${entry.name}`;
      const path = join(directory, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === "_build") continue;
        await visit(path, `${name}/`);
      } else if (entry.isFile()) {
        hash.update(name).update("\0").update(await readFile(path)).update("\0");
      } else {
        throw new Error(`Bundled resources must be regular files or directories: ${name}`);
      }
    }
  }
  await visit(source);
  await cp(source, destination, {
    recursive: true,
    filter: path => !path.split(/[\\/]/).includes("_build"),
  });
  return hash.digest("hex");
}
