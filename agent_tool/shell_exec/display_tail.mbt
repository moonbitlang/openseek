///|
priv struct RewriteStage {
  old : String
  replacement : String
  mut pending : String
}

///|
/// Emit committed matches and retain only a suffix that can still match at
/// the next append. Stages see the previous stage's output in launcher order.
fn RewriteStage::feed(self : RewriteStage, chunk : String) -> String {
  let out = StringBuilder()
  if self.old.is_empty() {
    // replace_all("", r) inserts r before each character and once at EOF.
    // snapshot renders that final insertion without committing it.
    for ch in chunk {
      out.write_string(self.replacement)
      out.write_char(ch)
    }
    return out.to_string()
  }
  let input = self.pending + chunk
  let mut rest = input[:]
  while rest.find(self.old) is Some(i) {
    out.write_view(rest[:i])
    out.write_string(self.replacement)
    rest = rest[i + self.old.length():]
  }
  let mut kept = 0
  for k = (self.old.char_length() - 1).min(rest.char_length()); k > 0; k = k - 1 {
    let units = self.old.offset_of_nth_char(k).unwrap()
    if rest.has_suffix(self.old[:units]) {
      kept = units
      break
    }
  }
  let cut = rest.length() - kept
  self.pending = rest[cut:].to_owned()
  out.write_view(rest[:cut])
  out.to_string()
}

///|
/// Read-only view of a job's retained output after ordered literal rewrites.
struct DisplayTail {
  stages : Array[RewriteStage]
  tail : FixedArray[Char]
  mut next : Int32
  // Saturates at capacity + 1 to distinguish an exact fit from truncation.
  mut count : Int32
}

///|
fn DisplayTail::new(
  rules : Array[(String, String)],
  window : Int32,
) -> DisplayTail {
  {
    stages: rules.map(pair => {
      let (old, replacement) = pair
      { old, replacement, pending: "", }
    }),
    tail: FixedArray::make(window, ' '),
    next: 0,
    count: 0,
  }
}

///|
fn DisplayTail::feed(self : DisplayTail, chunk : String) -> Unit {
  let mut text = chunk
  for stage in self.stages {
    text = stage.feed(text)
  }
  let n = self.tail.length()
  for ch in text {
    self.tail[self.next] = ch
    self.next = (self.next + 1) % n
    self.count = (self.count + 1).min(n + 1)
  }
}

///|
/// Rewritten output visible in the tail and whether any output was omitted.
#derive(Eq, Debug)
pub(all) struct DisplayTailSnapshot {
  text : String
  truncated : Bool
}

///|
/// The display window at this instant. A poll renders unfinished matches
/// without changing subsequent output.
pub fn DisplayTail::snapshot(self : DisplayTail) -> DisplayTailSnapshot {
  let mut pending = ""
  for stage in self.stages {
    pending = (stage.pending + pending).replace_all(
      old=stage.old,
      new=stage.replacement,
    )
  }
  let n = self.tail.length()
  let extra = pending.char_length()
  if extra >= n {
    return {
      text: last_chars(pending, n),
      truncated: extra > n || self.count > 0,
    }
  }
  let keep = self.count.min(n - extra)
  let out = StringBuilder()
  for i in 0..<keep {
    out.write_char(self.tail[(self.next + n - keep + i) % n])
  }
  out.write_string(pending)
  { text: out.to_string(), truncated: self.count > n - extra, }
}
