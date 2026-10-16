import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
if (process.platform === "win32") {
  console.log("headless installer filesystem tests require Unix; skipped on Windows");
} else {
  const result = spawnSync("python3", ["-B", fileURLToPath(new URL("./install_test.py", import.meta.url)), "-v"], { stdio: "inherit" });
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
}
