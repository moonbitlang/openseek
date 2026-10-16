import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../", import.meta.url));
if (process.platform === "win32") {
  console.log("loopback TCP integration tests require Unix; skipped on Windows");
  process.exit(0);
}
for (const [command, args] of [
  ["moon", ["build", ".", "--target", "native"]],
  ["moon", ["build", ".", "--target", "wasm"]],
  ["python3", ["-B", "tests/host_server/test_foreground.py", "-v"]],
  ["python3", ["-B", "tests/host_server/test_daemon.py", "-v"]],
  ["python3", ["-B", "tests/host_server/test_client.py", "-v"]],
]) {
  const result = spawnSync(command, args, { cwd: root, stdio: "inherit" });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
