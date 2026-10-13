import { access, cp, mkdir } from "node:fs/promises";
import { join } from "node:path";

// The npm SHA-512 integrity from Office Viewer's lockfile was verified before
// recording this archive digest. Build.download verifies it on every reuse.
export const OfficePdfArchive = Object.freeze({
  filename: "pdfjs-dist-6.4.299.tgz",
  url: "https://registry.npmjs.org/pdfjs-dist/-/pdfjs-dist-6.4.299.tgz",
  sha: "86269b40170eb41740ea05ad2102d71d33de4f122b34eb2f478be0ea7779c415",
  path: "pdfjs",
});

const PdfDirectories = ["web", "cmaps", "standard_fonts", "wasm", "iccs"];

export async function stageOfficePdfAssets(source, output, runtime) {
  // Validate the complete input before writing a partial distribution. The
  // engine, worker, fonts, CMaps, image codecs, and license ship together.
  for (const name of [
    "build/pdf.mjs", "build/pdf.worker.mjs", "web/pdf_viewer.mjs",
    "web/pdf_viewer.css", ...PdfDirectories, "LICENSE",
  ]) {
    await access(join(source, name));
  }
  await access(runtime);
  const target = join(output, "vendor/pdfjs");
  await mkdir(join(target, "build"), { recursive: true });
  for (const name of ["pdf", "pdf.worker"]) {
    // The shared static server maps .js consistently in both hosts. ESM bytes
    // stay unchanged and the runtime's relative URLs remain self-contained.
    await cp(join(source, `build/${name}.mjs`), join(target, `build/${name}.js`));
  }
  for (const name of [...PdfDirectories, "LICENSE"]) {
    await cp(join(source, name), join(target, name), { recursive: true });
  }
  await cp(join(source, "web/pdf_viewer.mjs"), join(target, "web/pdf_viewer.js"));
  await cp(runtime, join(output, "pdf-runtime.js"));
}
