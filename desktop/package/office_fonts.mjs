import { existsSync } from "node:fs";
import { join } from "node:path";

export const OfficeFontFiles = [
  "Carlito-Regular.ttf",
  "Carlito-Bold.ttf",
  "Carlito-Italic.ttf",
  "Carlito-BoldItalic.ttf",
  "LiberationSans-Regular.ttf",
  "LiberationSans-Bold.ttf",
  "LiberationSans-Italic.ttf",
  "LiberationSans-BoldItalic.ttf",
  "LiberationSerif-Regular.ttf",
  "LiberationSerif-Bold.ttf",
  "LiberationSerif-Italic.ttf",
  "LiberationSerif-BoldItalic.ttf",
  "LiberationMono-Regular.ttf",
  "LiberationMono-Bold.ttf",
  "LiberationMono-Italic.ttf",
  "LiberationMono-BoldItalic.ttf",
  "NotoSansSC-Regular.ttf",
  "LICENSES/Carlito-OFL.txt",
  "LICENSES/Liberation-LICENSE.txt",
  "LICENSES/NotoSansSC-OFL.txt",
  "LICENSES/MODIFICATIONS.md",
];

export function resolveOfficeFontSource(source, exists = existsSync) {
  const missing = OfficeFontFiles.filter(name => !exists(join(source, name)));
  if (missing.length) {
    throw new Error(
      "Office viewer fonts are missing from the Mooncakes package: " +
      missing.join(", "),
    );
  }
  return source;
}
