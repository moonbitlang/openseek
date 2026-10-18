import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { basename } from "node:path";

function runNotarytool(program, args) {
  return execFileSync(program, args, {
    encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], shell: false, timeout: 30_000,
  });
}

// Proton can report a stapling failure after notarytool exits successfully with
// Invalid status. Match Apple's log to the retained, unstapled DMG's bytes.
export async function reportNotarizationFailure({ artifact, profile, startedAt, run = runNotarytool }) {
  const info = await stat(artifact).catch(error => {
    if (error.code === "ENOENT") return null;
    throw error;
  });
  if (!info) return null;
  if (info.mtimeMs < startedAt.getTime()) return null;
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(artifact)) hash.update(chunk);
  const sha256 = hash.digest("hex");
  const history = JSON.parse(await run("/usr/bin/xcrun", [
    "notarytool", "history", "--keychain-profile", profile, "--output-format", "json",
  ]));
  const candidates = history.history.filter(submission =>
    submission.name === basename(artifact) &&
    Date.parse(submission.createdDate) >= startedAt.getTime() &&
    submission.status !== "In Progress",
  );
  const submissions = [];
  for (const submission of candidates) {
    const log = JSON.parse(await run("/usr/bin/xcrun", [
      "notarytool", "log", submission.id, "--keychain-profile", profile,
    ]));
    if (log.sha256 === sha256) submissions.push(log);
  }
  return submissions.length ? { artifact, sha256, submissions } : null;
}
