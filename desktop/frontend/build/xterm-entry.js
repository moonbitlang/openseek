// build.mjs stages the pinned packages and invokes a verified standalone
// esbuild binary to expose one shape shared by Desktop and Browser.
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebLinksAddon } from "@xterm/addon-web-links";

const writeBase64 = (term, b64, done) => {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  term.write(out, () => done(out.length));
};

globalThis.__openseek_xterm = {
  Terminal,
  FitAddon,
  WebLinksAddon,
  writeBase64,
};
