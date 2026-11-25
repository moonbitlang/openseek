"""Package the shared browser release as a WKWebView document and its subresources."""

import mimetypes
import os
from pathlib import Path
import plistlib
import subprocess
import sys
from urllib.parse import quote

root = Path(__file__).resolve().parent.parent
browser = root / "desktop/dist/browser"
subprocess.run(
    ["node", "desktop/package/build.mjs", "browser", "--release"], cwd=root, check=True
)


def resource(path, url):
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    if path.suffix in (".js", ".mjs"):
        mime = "text/javascript"
    return {
        "WebResourceURL": url,
        "WebResourceMIMEType": mime,
        "WebResourceData": path.read_bytes(),
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
