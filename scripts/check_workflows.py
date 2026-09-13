"""Type-check every bundled workflow without executing its main function."""

from pathlib import Path
import subprocess


def main():
    root = Path(__file__).resolve().parents[1]
    scripts = sorted((root / "share" / "workflow").glob("*.mbtx"))
    if not scripts:
        raise SystemExit("No bundled workflow scripts found")
    for script in scripts:
        relative = script.relative_to(root)
        print(f"Checking {relative}", flush=True)
        result = subprocess.run(
            ["moon", "check", "--target", "wasm", "--deny-warn", str(relative)],
            cwd=root,
        )
        if result.returncode:
            raise SystemExit(result.returncode)
    print(f"Checked {len(scripts)} bundled workflows", flush=True)


if __name__ == "__main__":
    main()
