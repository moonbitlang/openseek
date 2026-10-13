import assert from "node:assert/strict";
import test from "node:test";
import { access, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { stageOfficePdfAssets } from "./office_pdf.mjs";

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "openseek-pdf-assets-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const source = join(root, "source");
  for (const name of ["build", "web", "cmaps", "standard_fonts", "wasm", "iccs"]) {
    await mkdir(join(source, name), { recursive: true });
  }
  for (const name of [
    "build/pdf.mjs", "build/pdf.worker.mjs", "web/pdf_viewer.mjs", "web/pdf_viewer.css",
    "cmaps/sample.bcmap", "standard_fonts/sample.pfb", "wasm/openjpeg.wasm",
    "iccs/sample.icc", "LICENSE",
  ]) await writeFile(join(source, name), name);
  const runtime = join(root, "pdf-runtime.js");
  await writeFile(runtime, 'import "./vendor/pdfjs/build/pdf.js";');
  return { source, runtime, output: join(root, "output") };
}

test("PDF browser assets stage a self-contained engine, worker, fonts, codecs, and runtime", async t => {
  const { source, runtime, output } = await fixture(t);
  await stageOfficePdfAssets(source, output, runtime);
  for (const [name, original] of [
    ["build/pdf.js", "build/pdf.mjs"],
    ["build/pdf.worker.js", "build/pdf.worker.mjs"],
    ["web/pdf_viewer.js", "web/pdf_viewer.mjs"],
    ["web/pdf_viewer.css", "web/pdf_viewer.css"],
    ["cmaps/sample.bcmap", "cmaps/sample.bcmap"],
    ["standard_fonts/sample.pfb", "standard_fonts/sample.pfb"],
    ["wasm/openjpeg.wasm", "wasm/openjpeg.wasm"],
    ["iccs/sample.icc", "iccs/sample.icc"],
    ["LICENSE", "LICENSE"],
  ]) assert.equal(await readFile(join(output, "vendor/pdfjs", name), "utf8"), original);
  assert.equal(await readFile(join(output, "pdf-runtime.js"), "utf8"), await readFile(runtime, "utf8"));
});

test("a missing PDF worker fails before creating a partial distribution", async t => {
  const { source, runtime, output } = await fixture(t);
  await rm(join(source, "build/pdf.worker.mjs"));
  await assert.rejects(stageOfficePdfAssets(source, output, runtime), /pdf.worker.mjs/);
  await assert.rejects(access(output), { code: "ENOENT" });
});
