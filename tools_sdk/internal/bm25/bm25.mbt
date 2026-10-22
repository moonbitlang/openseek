// Okapi BM25 keyword ranking for small corpora of short English documents,
// such as tool names and descriptions. Documents are ranked once per query, so
// there is no persistent index: term counts are rebuilt per call.

///|
/// Common English words that carry no tool-specific signal.
fn is_stop_word(term : String) -> Bool {
  term
  is ("a"
  | "an"
  | "and"
  | "are"
  | "as"
  | "at"
  | "be"
  | "by"
  | "for"
  | "from"
  | "in"
  | "is"
  | "it"
  | "of"
  | "on"
  | "or"
  | "that"
  | "the"
  | "this"
  | "to"
  | "with")
}

///|
/// Naive singular form, so `issues` matches `issue` and `searches` matches
/// `search`. Terms are lowercase ASCII, so slicing never splits a character.
fn stem(term : String) -> String {
  let length = term.length()
  if length > 4 && term.has_suffix("ies") {
    return "\{term[:length - 3]}y"
  }
  if length > 4 &&
    (
      term.has_suffix("ches") ||
      term.has_suffix("shes") ||
      term.has_suffix("sses") ||
      term.has_suffix("xes") ||
      term.has_suffix("zes")
    ) {
    return term[:length - 2].to_owned()
  }
  if length > 3 && term.has_suffix("s") && !term.has_suffix("ss") {
    return term[:length - 1].to_owned()
  }
  term
}

///|
/// Lowercase ASCII terms of `text`, split at non-alphanumerics and camelCase
/// boundaries, without stop words, stemmed. An uppercase run stays whole until
/// the capital that starts the next word: `HTTPServer` is `http server`.
fn tokenize(text : String) -> Array[String] {
  let terms : Array[String] = []
  let current = StringBuilder()
  fn flush() {
    if current.is_empty() {
      return
    }
    let term = current.to_string()
    current.reset()
    if !is_stop_word(term) {
      terms.push(stem(term))
    }
  }

  let chars : Array[Char] = [..text]
  for i, ch in chars {
    if !(ch.is_ascii_alphabetic() || ch.is_ascii_digit()) {
      flush()
      continue
    }
    if i > 0 && ch.is_ascii_uppercase() {
      let prev = chars[i - 1]
      let starts_word = prev.is_ascii_lowercase() ||
        prev.is_ascii_digit() ||
        (
          prev.is_ascii_uppercase() &&
          chars.get(i + 1) is Some(next) &&
          next.is_ascii_lowercase()
        )
      if starts_word {
        flush()
      }
    }
    current.write_char(ch.to_ascii_lowercase())
  }
  flush()
  terms
}

///|
/// Indices of the `documents` that match `query` best, best first, at most
/// `limit` of them. Okapi BM25 with k1 = 1.2 and b = 0.75; a document sharing
/// no term with the query is not a match, and ties keep document order.
///
/// Both sides are tokenized the same way: lowercase ASCII terms split at
/// non-alphanumerics and camelCase boundaries, without common English stop
/// words, with simple plurals folded (`issues` matches `issue`).
pub fn rank(
  query~ : String,
  documents~ : Array[String],
  limit~ : Int32,
) -> Array[Int32] {
  let query_terms : Array[String] = []
  for term in tokenize(query) {
    if !query_terms.contains(term) {
      query_terms.push(term)
    }
  }
  if query_terms.is_empty() || documents.is_empty() || limit <= 0 {
    return []
  }
  let k1 = 1.2
  let b = 0.75
  let counts : Array[Map[String, Int32]] = []
  let lengths : Array[Double] = []
  // TODO(perf): every call tokenizes and counts every document again. That is
  // cheap next to a model turn at a few hundred tools; build an index once if
  // callers rank thousands of documents or rank on a hot path.
  for document in documents {
    let terms = tokenize(document)
    let count : Map[String, Int32] = Map([])
    for term in terms {
      count[term] = count.get(term).unwrap_or(0) + 1
    }
    counts.push(count)
    lengths.push(terms.length().to_double())
  }
  let total = documents.length().to_double()
  let average = lengths.fold(init=0.0, (sum, length) => sum + length) / total
  let average_length = if average > 0.0 { average } else { 1.0 }
  let idf = query_terms.map(term => {
    let frequency = counts
      .filter(count => count.contains(term))
      .length()
      .to_double()
    @math.ln(1.0 + (total - frequency + 0.5) / (frequency + 0.5))
  })
  let matches : Array[(Int32, Double)] = []
  for index, count in counts {
    let norm = k1 * (1.0 - b + b * lengths[index] / average_length)
    let mut score = 0.0
    for position, term in query_terms {
      guard count.get(term) is Some(occurrences) else { continue }
      let tf = occurrences.to_double()
      score += idf[position] * (tf * (k1 + 1.0)) / (tf + norm)
    }
    if score > 0.0 {
      matches.push((index, score))
    }
  }
  matches.sort_by((left, right) => {
    if left.1 == right.1 {
      left.0.compare(right.0)
    } else {
      right.1.compare(left.1)
    }
  })
  [
    for found in matches[:matches.length().min(limit)] => found.0
  ]
}
