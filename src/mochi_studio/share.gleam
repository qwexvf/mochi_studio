// mochi_studio/share.gleam
// URL-based query sharing — encode/decode query+variables into the URL hash

import gleam/option.{type Option, None}
import lustre/effect.{type Effect}

/// Encode query + variables into a base64 URL fragment and copy to clipboard
pub fn copy_link(query: String, variables: String) -> Effect(msg) {
  effect.from(fn(_dispatch) { do_copy_link(query, variables) })
}

/// Read query + variables from the current URL hash
pub fn read_url() -> Option(#(String, String)) {
  do_read_url()
}

@external(javascript, "./share_ffi.mjs", "copyShareLink")
fn do_copy_link(query: String, variables: String) -> Nil {
  let _ = query
  let _ = variables
  Nil
}

@external(javascript, "./share_ffi.mjs", "readUrl")
fn do_read_url() -> Option(#(String, String)) {
  None
}
