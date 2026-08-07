// The upstream xterm and addon-fit distributions are already browser-ready
// UMD files. Development loads them separately and installs only the adapter
// shape the MoonBit frontend consumes; production may still bundle this shape.
globalThis.__openseek_xterm = {
  Terminal: globalThis.Terminal,
  FitAddon: globalThis.FitAddon.FitAddon,
  writeBase64(term, b64, done) {
    const binary = atob(b64);
    const output = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      output[index] = binary.charCodeAt(index);
    }
    term.write(output, () => done(output.length));
  },
};
