#!/usr/bin/env python3
import argparse
import json
import os
import re
import signal
import subprocess
import sys
from datetime import datetime
from pathlib import Path


OUTPUT_FILE = Path("./labels.txt")
DEFAULT_TIMEOUT_SECONDS = 30
DEFAULT_GRACE_PERIOD_SECONDS = int(os.environ.get("GRACE_PERIOD", "5"))


class Colors:
    GREEN = "\033[92m"
    RED = "\033[91m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    RESET = "\033[0m"
    BOLD = "\033[1m"


def supports_color() -> bool:
    if not hasattr(sys.stdout, "isatty"):
        return False
    if not sys.stdout.isatty():
        return False
    return True


USE_COLOR = supports_color()


def colorize(text: str, color: str) -> str:
    if USE_COLOR:
        return f"{color}{text}{Colors.RESET}"
    return text


def status_symbol(status: str) -> str:
    if status == "pass":
        return colorize("PASS", Colors.GREEN)
    if status == "fail":
        return colorize("FAIL", Colors.RED)
    if status == "timeout":
        return colorize("TIMEOUT", Colors.YELLOW)
    if status == "oom":
        return colorize("OOM", Colors.YELLOW)
    return colorize(status.upper(), Colors.YELLOW)


def collect_labels(text: str) -> list[str]:
    labels: list[str] = []
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("//"):
            continue
        match = re.match(r'^\s*test\s+"([^"]+)"', line)
        if match:
            labels.append(match.group(1))
    return labels


def is_oom(returncode: int, stderr: str) -> bool:
    if returncode in (137, -9):
        return True
    if returncode < 0 and -returncode == 9:
        return True
    stderr_lower = stderr.lower()
    return "out of memory" in stderr_lower or "oom" in stderr_lower


def find_test_files(test_file_arg: str | None) -> list[Path]:
    if test_file_arg is not None:
        test_file = Path(test_file_arg)
        if not test_file.exists():
            print(f"missing test file: {test_file}", file=sys.stderr)
            return []
        return [test_file]
    skip_dirs = {".mooncakes", "_build", "target"}
    all_files = Path.cwd().rglob("*_test.mbt")
    filtered = [f for f in all_files if not (skip_dirs & set(f.parts))]
    return sorted(filtered)


def truncate_message(text: str, max_lines: int = 20, max_line_length: int = 200) -> str:
    """Truncate message to first N lines, with per-line length limit."""
    if not text:
        return ""
    lines = text.strip().splitlines()
    truncated_lines = []
    for line in lines[:max_lines]:
        if len(line) > max_line_length:
            line = line[:max_line_length] + "..."
        truncated_lines.append(line)
    result = "\n".join(truncated_lines)
    if len(lines) > max_lines:
        result += f"\n... ({len(lines) - max_lines} more lines)"
    return result


def emit_result(result_dict: dict, json_mode: bool) -> None:
    """Print a test result immediately if in JSON mode."""
    if json_mode:
        print(json.dumps(result_dict), flush=True)


def terminate_process_gracefully(
    proc: subprocess.Popen,
    grace_period: int = DEFAULT_GRACE_PERIOD_SECONDS,
) -> tuple[str, str]:
    if proc.poll() is not None:
        return proc.communicate()

    try:
        proc.terminate()
    except ProcessLookupError:
        return proc.communicate()

    try:
        return proc.communicate(timeout=grace_period)
    except subprocess.TimeoutExpired:
        try:
            pgid = os.getpgid(proc.pid)
            os.killpg(pgid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError, OSError):
            try:
                proc.kill()
            except ProcessLookupError:
                pass

        try:
            return proc.communicate(timeout=1)
        except subprocess.TimeoutExpired:
            try:
                proc.kill()
            except ProcessLookupError:
                pass
            return proc.communicate()


def terminate_process_group(proc: subprocess.Popen) -> None:
    if proc.poll() is not None:
        return

    try:
        pgid = os.getpgid(proc.pid)
    except (ProcessLookupError, OSError):
        pgid = None

    try:
        if pgid is not None:
            os.killpg(pgid, signal.SIGTERM)
        else:
            proc.terminate()
    except (ProcessLookupError, PermissionError, OSError):
        try:
            proc.terminate()
        except ProcessLookupError:
            return

    try:
        proc.wait(timeout=DEFAULT_GRACE_PERIOD_SECONDS)
        return
    except subprocess.TimeoutExpired:
        pass

    try:
        if pgid is not None:
            os.killpg(pgid, signal.SIGKILL)
        else:
            proc.kill()
    except (ProcessLookupError, PermissionError, OSError):
        try:
            proc.kill()
        except ProcessLookupError:
            return

    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        pass


def print_result(
    index: int,
    total: int,
    label: str,
    status: str,
    message: str,
) -> None:
    symbol = status_symbol(status)
    print(f"[{index}/{total}] {symbol}: {label}", flush=True)
    if message and status != "pass":
        for msg_line in message.splitlines():
            print(f"    {msg_line}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--test-file", help="run a specific test file")
    parser.add_argument("--test-name", help="run a specific test by name")
    parser.add_argument(
        "--timeout",
        type=int,
        default=DEFAULT_TIMEOUT_SECONDS,
        help="per-test timeout in seconds",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="output results as JSONL",
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="disable color output",
    )
    args = parser.parse_args()

    global USE_COLOR
    if args.no_color:
        USE_COLOR = False

    test_files = find_test_files(args.test_file)
    if not test_files:
        print("no test files found", file=sys.stderr)
        return 1

    test_labels: list[tuple[Path, str]] = []
    for test_file in test_files:
        labels = collect_labels(test_file.read_text(encoding="utf-8"))
        test_labels.extend((test_file, label) for label in labels)

    if args.test_name:
        matching = [
            (test_file, label)
            for test_file, label in test_labels
            if label == args.test_name
        ]
        if not matching:
            print(f"test_name not found: {args.test_name}", file=sys.stderr)
            return 1
        if len(matching) > 1:
            if args.test_file is None:
                print(
                    "test_name is not unique; specify --test-file",
                    file=sys.stderr,
                )
            else:
                print(
                    "test_name is not unique within the selected file",
                    file=sys.stderr,
                )
            return 1
        test_labels = matching

    timeouts: list[str] = []
    ooms: list[str] = []
    fails: list[str] = []
    all_results: list[dict] = []
    # Emit test count upfront for streaming clients
    if args.json:
        print(json.dumps({"test_count": len(test_labels)}), flush=True)

    current_proc: subprocess.Popen | None = None
    try:
        for index, (test_file, label) in enumerate(test_labels, start=1):
            message = ""
            status = "pass"
            cmd = ["moon", "test", str(test_file), "--filter", label]
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                start_new_session=True,
            )
            current_proc = proc
            try:
                stdout, stderr = proc.communicate(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                stdout, stderr = terminate_process_gracefully(proc)
                status = "timeout"
                message = f"Test timed out after {args.timeout} seconds"
            except KeyboardInterrupt:
                terminate_process_group(proc)
                print("\nInterrupted by user. Terminated running test.", file=sys.stderr)
                return 130
            else:
                if is_oom(proc.returncode, stderr):
                    status = "oom"
                    message = "Out of memory"
                elif proc.returncode != 0:
                    status = "fail"
                    message = truncate_message(stdout + stderr)
            finally:
                current_proc = None

            if status == "timeout":
                timeouts.append(label)
            elif status == "oom":
                ooms.append(label)
            elif status == "fail":
                fails.append(label)

            result_dict = {
                "test_name": label,
                "test_file": str(test_file),
                "status": status,
            }
            if message:
                result_dict["message"] = message
            all_results.append(result_dict)
            emit_result(result_dict, args.json)
            if not args.json:
                print_result(index, len(test_labels), label, status, message)
    except KeyboardInterrupt:
        if current_proc is not None:
            terminate_process_group(current_proc)
        print("\nInterrupted by user. Terminated running test.", file=sys.stderr)
        return 130

    total = len(test_labels)
    bad = timeouts + ooms + fails
    passed = total - len(bad)

    summary_dict = {
        "total": total,
        "passed": passed,
        "timeout": len(timeouts),
        "oom": len(ooms),
        "failed": len(fails),
    }

    output = {
        "results": all_results,
        "summary": summary_dict,
    }
    timestamp = datetime.now().strftime("%Y-%m-%d-%H%M%S")
    results_json_file = Path(f"./results-{timestamp}.json")
    results_json_file.write_text(json.dumps(output, indent=2), encoding="utf-8")

    if args.json:
        summary = {
            "summary": True,
            **summary_dict,
        }
        print(json.dumps(summary), flush=True)
    else:
        OUTPUT_FILE.write_text("\n".join(bad) + ("\n" if bad else ""), encoding="utf-8")
        print(flush=True)
        print(f"{colorize('Summary:', Colors.BOLD)}", flush=True)
        print(f"  Total:   {total}", flush=True)
        print(f"  Passed:  {colorize(str(passed), Colors.GREEN)}", flush=True)
        if len(timeouts) > 0:
            print(f"  Timeout: {colorize(str(len(timeouts)), Colors.YELLOW)}", flush=True)
        else:
            print(f"  Timeout: {len(timeouts)}", flush=True)
        if len(ooms) > 0:
            print(f"  OOM:     {colorize(str(len(ooms)), Colors.YELLOW)}", flush=True)
        else:
            print(f"  OOM:     {len(ooms)}", flush=True)
        if len(fails) > 0:
            print(f"  Failed:  {colorize(str(len(fails)), Colors.RED)}", flush=True)
        else:
            print(f"  Failed:  {len(fails)}", flush=True)
        total_bad = len(bad)
        if total_bad == 0:
            print(f"\n{colorize('All tests passed!', Colors.GREEN)}", flush=True)
        else:
            print(f"\n{colorize('Tests completed with failures.', Colors.RED)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
