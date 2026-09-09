import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { stageResources } from "./resources.mjs";

test("package checked-in docs and workflows; edits change the payload stamp", async () => {
  const temp = await mkdtemp(join(tmpdir(), "openseek-resources-"));
  try {
    const source = fileURLToPath(new URL("../../share/", import.meta.url));
    const staged = join(temp, "share");
    const hash = await stageResources(source, staged);
    for (const path of ["doc/moonbit/index.md", "doc/moonbit.commit", "workflow/check.mbtx", "workflow/check-json.mbtx"]) {
      assert.deepEqual(await readFile(join(staged, path)), await readFile(join(source, path)));
    }
    assert.equal(hash, await stageResources(staged, join(temp, "copy")));
    await writeFile(join(staged, "doc/moonbit/index.md"), "updated docs");
    const docsHash = await stageResources(staged, join(temp, "updated-docs"));
    assert.notEqual(docsHash, hash);
    await writeFile(join(staged, "workflow/check.mbtx"), "updated workflow");
    assert.notEqual(await stageResources(staged, join(temp, "updated-workflow")), docsHash);
    await rm(join(staged, "doc/moonbit/index.md"));
    await assert.rejects(stageResources(staged, join(temp, "incomplete")), { code: "ENOENT" });
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});
