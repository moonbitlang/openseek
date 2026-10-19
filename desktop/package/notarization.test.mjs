import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp, rm, utimes, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { reportNotarizationFailure } from "./notarization.mjs";

const ArtifactSha256 = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824";
const StartedAt = new Date("2026-10-18T08:00:00.000Z");

async function artifactFixture(t, modifiedAt = new Date("2026-10-18T08:01:00.000Z")) {
  const root = await mkdtemp(join(tmpdir(), "openseek-notarization-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const artifact = join(root, "SeekMoon.dmg");
  await writeFile(artifact, "hello");
  await utimes(artifact, modifiedAt, modifiedAt);
  return artifact;
}

test("a successful notarytool exit with Invalid status reports Apple's rejection", async t => {
  const artifact = await artifactFixture(t);
  const log = {
    jobId: "rejected-submission",
    status: "Invalid",
    sha256: ArtifactSha256,
    issues: [{
      severity: "error",
      path: "SeekMoon.dmg/SeekMoon.app/Contents/Resources/seekmoon/toolchains/moonbit/macos-arm64/bin/moonc-prove",
      message: "The binary is not signed with a valid Developer ID certificate.",
    }],
  };
  const run = async (program, args) => {
    assert.equal(program, "/usr/bin/xcrun");
    assert.ok(args.includes("ci notary profile"));
    if (args[1] === "history") return JSON.stringify({ history: [{
      id: log.jobId, name: "SeekMoon.dmg", createdDate: "2026-10-18T08:02:00.000Z", status: "Invalid",
    }] });
    assert.equal(args[1], "log");
    assert.equal(args[2], log.jobId);
    return JSON.stringify(log);
  };
  assert.deepEqual(
    await reportNotarizationFailure({ artifact, profile: "ci notary profile", startedAt: StartedAt, run }),
    { artifact, sha256: ArtifactSha256, submissions: [log] },
  );
});

test("concurrent submissions and older matching archives are not attributed to this package", async t => {
  const artifact = await artifactFixture(t);
  const history = [
    { id: "concurrent", name: "SeekMoon.dmg", createdDate: "2026-10-18T08:04:00.000Z" },
    { id: "another-product", name: "Other.dmg", createdDate: "2026-10-18T08:03:00.000Z" },
    { id: "previous-package", name: "SeekMoon.dmg", createdDate: "2026-10-18T07:59:59.999Z" },
    { id: "this-package", name: "SeekMoon.dmg", createdDate: "2026-10-18T08:02:00.000Z" },
  ];
  const log = { jobId: "this-package", status: "Invalid", sha256: ArtifactSha256, issues: [] };
  const queried = [];
  const run = (program, args) => {
    if (args[1] === "history") return JSON.stringify({ history });
    queried.push(args[2]);
    return JSON.stringify(args[2] === "concurrent"
      ? { jobId: "concurrent", status: "Accepted", sha256: "another-archive-sha256", issues: null }
      : { ...log, jobId: args[2] });
  };
  assert.deepEqual(
    await reportNotarizationFailure({ artifact, profile: "ci", startedAt: StartedAt, run }),
    { artifact, sha256: ArtifactSha256, submissions: [log] },
  );
  assert.deepEqual(queried, ["concurrent", "this-package"]);
});

test("a stale DMG does not query notarization history", async t => {
  const artifact = await artifactFixture(t, new Date("2026-10-18T07:59:59.000Z"));
  const run = () => assert.fail("a previous package must not trigger notarization queries");
  assert.equal(await reportNotarizationFailure({ artifact, profile: "ci", startedAt: StartedAt, run }), null);
});

test("a package that did not produce a DMG does not query notarization history", async t => {
  const artifact = await artifactFixture(t);
  await rm(artifact);
  const run = () => assert.fail("a missing package must not trigger notarization queries");
  assert.equal(await reportNotarizationFailure({ artifact, profile: "ci", startedAt: StartedAt, run }), null);
});

test("a pending concurrent submission does not hide the completed rejection", async t => {
  const artifact = await artifactFixture(t);
  const log = { jobId: "completed", status: "Invalid", sha256: ArtifactSha256, issues: [] };
  const run = async (program, args) => {
    if (args[1] === "history") return JSON.stringify({ history: [
      { id: "pending", name: "SeekMoon.dmg", createdDate: "2026-10-18T08:03:00.000Z", status: "In Progress" },
      { id: "completed", name: "SeekMoon.dmg", createdDate: "2026-10-18T08:02:00.000Z", status: "Invalid" },
    ] });
    assert.equal(args[2], "completed", "unfinished submissions do not have a log");
    return JSON.stringify(log);
  };
  assert.deepEqual(
    await reportNotarizationFailure({ artifact, profile: "ci", startedAt: StartedAt, run }),
    { artifact, sha256: ArtifactSha256, submissions: [log] },
  );
});

test("no current submission with the artifact's SHA-256 returns no report", async t => {
  const artifact = await artifactFixture(t, StartedAt);
  const run = (program, args) => {
    if (args[1] === "history") return JSON.stringify({ history: [
      { id: "other-archive", name: "SeekMoon.dmg", createdDate: "2026-10-18T08:02:00.000Z", status: "Accepted" },
      { id: "unknown-date", name: "SeekMoon.dmg", createdDate: "unknown", status: "Invalid" },
    ] });
    return JSON.stringify({
      jobId: args[2], status: "Accepted", issues: null,
      sha256: args[2] === "unknown-date" ? ArtifactSha256 : "another-archive-sha256",
    });
  };
  assert.equal(await reportNotarizationFailure({ artifact, profile: "ci", startedAt: StartedAt, run }), null);
});

test("repeated submissions of the same bytes retain all matching logs", async t => {
  const artifact = await artifactFixture(t, StartedAt);
  const logs = [
    { jobId: "first", status: "Invalid", sha256: ArtifactSha256, issues: [] },
    { jobId: "second", status: "Accepted", sha256: ArtifactSha256, issues: null },
  ];
  const run = (program, args) => JSON.stringify(args[1] === "history"
    ? { history: logs.map(log => ({
      id: log.jobId, status: log.status, name: "SeekMoon.dmg", createdDate: StartedAt.toISOString(),
    })) }
    : logs.find(log => log.jobId === args[2]));
  assert.deepEqual(
    await reportNotarizationFailure({ artifact, profile: "ci", startedAt: StartedAt, run }),
    { artifact, sha256: ArtifactSha256, submissions: logs },
  );
});

test("notarization lookup failures propagate to the caller", async t => {
  const artifact = await artifactFixture(t);
  for (const stage of ["history", "log"]) {
    const failure = new Error(`${stage} request failed`);
    const run = async (program, args) => {
      if (args[1] === stage) throw failure;
      return JSON.stringify({ history: [{
        id: "failed-lookup", name: "SeekMoon.dmg", createdDate: "2026-10-18T08:02:00.000Z", status: "Invalid",
      }] });
    };
    await assert.rejects(
      reportNotarizationFailure({ artifact, profile: "ci", startedAt: StartedAt, run }),
      error => error === failure,
    );
  }
});
