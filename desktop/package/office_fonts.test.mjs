import assert from "node:assert/strict";
import test from "node:test";
import { OfficeFontFiles, resolveOfficeFontSource } from "./office_fonts.mjs";

test("Office fonts require the published package and all copyright notices", () => {
  const complete = new Set(OfficeFontFiles.map(name => `/registry/${name}`));
  const exists = path => complete.has(path);
  assert.equal(
    resolveOfficeFontSource("/registry", exists),
    "/registry",
  );
  for (const name of OfficeFontFiles.filter(name => name.startsWith("LICENSES/"))) {
    complete.delete(`/registry/${name}`);
    assert.throws(
      () => resolveOfficeFontSource("/registry", exists),
      error => error.message.includes(name),
    );
    complete.add(`/registry/${name}`);
  }
  assert.throws(
    () => resolveOfficeFontSource("/missing", exists),
    /Office viewer fonts are missing from the Mooncakes package/,
  );
});
