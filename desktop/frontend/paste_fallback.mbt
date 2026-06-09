///|
fn install_clipboard_paste_bridge() -> @cmd.Cmd {
  @cmd.custom_cmd(_ => js_install_clipboard_paste_bridge())
}

///|
extern "js" fn js_install_clipboard_paste_bridge() =
  #| () => {
  #|   if (globalThis.__openseekDesktopClipboardPasteBridgeInstalled) return;
  #|   globalThis.__openseekDesktopClipboardPasteBridgeInstalled = true;
  #|   const editableInputTypes = new Set([
  #|     "email", "number", "password", "search", "tel", "text", "url",
  #|   ]);
  #|   const editableTarget = (target) => {
  #|     if (target instanceof HTMLTextAreaElement) return true;
  #|     if (!(target instanceof HTMLInputElement)) return false;
  #|     return editableInputTypes.has(String(target.type || "text").toLowerCase());
  #|   };
  #|   const clipboardApi = () => {
  #|     const root = globalThis.__MoonBit__;
  #|     const clipboard = root && root.clipboard;
  #|     return clipboard && typeof clipboard.readText === "function" ? clipboard : null;
  #|   };
  #|   const readClipboardText = async () => {
  #|     const clipboard = clipboardApi();
  #|     if (!clipboard) throw new Error("clipboard bridge unavailable");
  #|     const reply = await clipboard.readText({});
  #|     return String((reply && reply.text) || "");
  #|   };
  #|   const inputEvent = (text) => {
  #|     if (typeof InputEvent === "function") {
  #|       return new InputEvent("input", {
  #|         bubbles: true,
  #|         cancelable: true,
  #|         inputType: "insertFromPaste",
  #|         data: text,
  #|       });
  #|     }
  #|     return new Event("input", { bubbles: true, cancelable: true });
  #|   };
  #|   const insertText = (target, text) => {
  #|     const value = String(target.value || "");
  #|     const start = typeof target.selectionStart === "number" ? target.selectionStart : value.length;
  #|     const end = typeof target.selectionEnd === "number" ? target.selectionEnd : start;
  #|     if (typeof target.setRangeText === "function") {
  #|       target.setRangeText(text, start, end, "end");
  #|     } else {
  #|       target.value = value.slice(0, start) + text + value.slice(end);
  #|     }
  #|     target.dispatchEvent(inputEvent(text));
  #|   };
  #|   document.addEventListener("keydown", async (event) => {
  #|     const key = String(event.key || "").toLowerCase();
  #|     if (key !== "v" || event.altKey || !(event.metaKey || event.ctrlKey)) return;
  #|     const target = event.target;
  #|     if (!editableTarget(target) || target.readOnly || target.disabled) return;
  #|     if (!clipboardApi()) return;
  #|     event.preventDefault();
  #|     try {
  #|       const text = await readClipboardText();
  #|       if (text) insertText(target, text);
  #|     } catch (error) {
  #|       console.warn("OpenSeek clipboard paste fallback failed", error);
  #|     }
  #|   }, true);
  #| }
