///|
/// Mint a lowercase RFC 9562 UUID version 4 in Desktop's browser process.
/// The packaged WebView contract includes Web Crypto, which also lets
/// synchronous UI callbacks keep their existing non-optional return types.
pub extern "js" fn mint() -> String =
  #| () => {
  #|   const crypto = globalThis.crypto;
  #|   if (!crypto || typeof crypto.randomUUID !== "function") {
  #|     throw new Error("Web Crypto randomUUID is unavailable");
  #|   }
  #|   return crypto.randomUUID();
  #| }
