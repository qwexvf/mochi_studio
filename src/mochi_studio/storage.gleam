// mochi_studio/storage.gleam
// localStorage persistence for collections and session state

import lustre/effect.{type Effect}
import mochi_studio/collection.{type Collection}

@target(javascript)
pub fn save_collections(collections: List(Collection)) -> Effect(msg) {
  effect.from(fn(_) { do_save(collections) })
}

@target(javascript)
pub fn load_collections() -> List(Collection) {
  do_load()
}

@target(javascript)
@external(javascript, "./storage_ffi.mjs", "saveCollections")
fn do_save(collections: List(Collection)) -> Nil

@target(javascript)
@external(javascript, "./storage_ffi.mjs", "loadCollections")
fn do_load() -> List(Collection)
