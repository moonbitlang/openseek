// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
/// XML Parser Specification
/// Inspired by quick-xml (https://github.com/tafia/quick-xml)
///
/// This module provides a streaming XML parser using a pull-parser model.
/// Users read events one at a time, similar to StAX in Java.
///

// ============================================================================
// Reader API (Pull Parser)
// ============================================================================

///|
/// A streaming XML reader
declare pub type Reader

///|
/// Create a new reader from a string
declare pub fn Reader::from_string(input : String) -> Reader

///|
/// Create a new reader from a file path
declare pub fn Reader::from_file(path : String) -> Reader raise @fs.IOError

///|
/// Read the next XML event
declare pub fn Reader::read_event(self : Reader) -> Event raise XmlError

///|
/// Check if the reader has reached the end
declare pub fn Reader::is_eof(self : Reader) -> Bool

///|
/// Get current line number (1-indexed)
declare pub fn Reader::line(self : Reader) -> Int

///|
/// Get current column number (1-indexed)
declare pub fn Reader::column(self : Reader) -> Int

///|
/// Read all events until EOF (inclusive) as an Array.
/// Includes the final Eof event in the result.
/// Raises XmlError if parsing fails.
declare pub fn Reader::read_events_until_eof(
  self : Reader,
) -> Array[Event] raise XmlError

// ============================================================================
// Writer API
// ============================================================================

///|
/// An XML writer for generating XML output
declare pub type Writer

///|
/// Create a new writer
declare pub fn Writer::new() -> Writer

///|
/// Write an XML event
declare pub fn Writer::write_event(self : Writer, event : Event) -> Unit

///|
/// Write a start element
declare pub fn Writer::start_element(
  self : Writer,
  name : String,
  attributes : Array[(String, String)],
) -> Unit

///|
/// Write an end element
declare pub fn Writer::end_element(self : Writer, name : String) -> Unit

///|
/// Write a self-closing element
declare pub fn Writer::empty_element(
  self : Writer,
  name : String,
  attributes : Array[(String, String)],
) -> Unit

///|
/// Write text content (escaped)
declare pub fn Writer::text(self : Writer, content : String) -> Unit

///|
/// Write CDATA section
declare pub fn Writer::cdata(self : Writer, content : String) -> Unit

///|
/// Write a comment
declare pub fn Writer::comment(self : Writer, content : String) -> Unit

///|
/// Get the generated XML string
declare pub fn Writer::to_string(self : Writer) -> String

// ============================================================================
// Convenience Functions
// ============================================================================

///|
/// Escape special XML characters in text
declare pub fn escape(text : String) -> String

///|
/// Unescape XML entities (&lt; &gt; &amp; &quot; &apos;)
declare pub fn unescape(text : String) -> String raise XmlError

///|
declare pub fn to_libxml_format(events : Array[Event]) -> String

///|
declare pub type Event

///|
declare pub fn Event::to_string(self : Event) -> String

///|
pub(all) suberror XmlError {
  UnexpectedEof
  InvalidSyntax(String)
  UnmatchedTag(expected~ : String, found~ : String)
  InvalidAttribute(String)
  InvalidEntity(String)
} derive(Debug, Eq)
