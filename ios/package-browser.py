"""Package the shared browser release as a WKWebView document and its subresources."""

import mimetypes
import os
from pathlib import Path
import plistlib
import subprocess
import sys
from urllib.parse import quote

root = Path(__file__).resolve().parent.parent
# Xcode gives each target, platform and configuration its own intermediates.
staging = Path(os.environ["TARGET_TEMP_DIR"]) / "seekmoon-browser"
browser = staging / "browser"
with (root / "ios/Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
version = f"{info['CFBundleShortVersionString']} ({info['CFBundleVersion']})"
build_env = os.environ.copy()
build_env.setdefault("SEEKMOON_BROWSER_RELEASE", version)
subprocess.run(
    ["node", "desktop/package/build.mjs", "browser", "--release", "--staging-dir", str(staging)],
    cwd=root, check=True, env=build_env,
)


def resource(path, url):
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    if path.suffix in (".js", ".mjs"):
        mime = "text/javascript"
    data = path.read_bytes()
    if path == browser / "index.html":
        # Let the host restore the account before the frontend reads its store.
        entry = b'<script type="module" src="/assets/frontend.js"></script>'
        if data.count(entry) != 1:
            raise ValueError("Cannot identify the packaged console entry module")
        data = data.replace(entry, b'<link id="seekmoon-entry" rel="modulepreload" href="/assets/frontend.js">')
    return {
        "WebResourceURL": url,
        "WebResourceMIMEType": mime,
        "WebResourceData": data,
    }


# An empty main-resource URL lets WKWebView use the requested /cloud or
# /device/... route as the document URL, including on a cold launch.
origin = "https://seekmoon.moonbitlang.com/"
files = [browser / "sw.js", *sorted((browser / "assets").rglob("*"))]
archive = {
    "WebMainResource": resource(browser / "index.html", ""),
    "WebSubresources": [
        resource(path, origin + quote(path.relative_to(browser).as_posix()))
        for path in files if path.is_file()
    ],
}
output = Path(sys.argv[1])
output.parent.mkdir(parents=True, exist_ok=True)
temporary = output.with_suffix(".tmp")
with temporary.open("wb") as stream:
    plistlib.dump(archive, stream, fmt=plistlib.FMT_BINARY)
os.replace(temporary, output)
