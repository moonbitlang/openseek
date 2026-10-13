///| Faithful port of vscode's `model/utils.ts` helpers (pinned `vscode/`
/// checked-in submodule). Currently only `computeIndentLevel`; the rest
/// of `utils.ts` is ported on demand.

///|
/// Whitespace-run width of `line` (tabs expanded to `tab_size`), or `-1` if the
/// line consists only of whitespace. Mirrors `model/utils.ts`
/// `computeIndentLevel`.
pub fn compute_indent_level(line : String, tab_size : Int32) -> Int32 {
  let len = line.length()
  for i = 0, indent = 0; i < len; {
    let ch_code = line[i].to_int()
    if ch_code == 32 {
      continue i + 1, indent + 1
    } else if ch_code == 9 {
      continue i + 1, indent - indent % tab_size + tab_size
    } else {
      break indent
    }
  } nobreak {
    -1
  } // line only consists of whitespace
}
