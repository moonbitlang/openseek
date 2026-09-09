import { createHash } from "node:crypto";
import { cp, readFile, readdir, stat } from "node:fs/promises";
import { join } from "node:path";

// Hash names and bytes in stable order, so any checked-in resource change
// refreshes the prepared payload even when the compiler version is unchanged.
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
        await visit(path, `${name}/`);
      } else if (entry.isFile()) {
        hash.update(name).update("\0").update(await readFile(path)).update("\0");
      } else {
        throw new Error(`Bundled resources must be regular files or directories: ${name}`);
      }
    }
  }
  await visit(source);
  await cp(source, destination, { recursive: true });
  return hash.digest("hex");
}
