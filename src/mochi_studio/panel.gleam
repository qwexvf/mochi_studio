// mochi_studio/panel.gleam

import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Panel {
  Playground
  Builder
}

pub fn tab_button(
  panel: Panel,
  active: Panel,
  on_click: fn(Panel) -> msg,
) -> Element(msg) {
  let label = case panel {
    Playground -> "Playground"
    Builder -> "Schema Builder"
  }
  let base = "px-3 py-1 rounded text-sm font-medium transition-colors"
  let classes = case panel == active {
    True -> base <> " bg-pink-500 text-white"
    False -> base <> " text-gray-400 hover:text-gray-100"
  }
  html.button([attribute.class(classes), event.on_click(on_click(panel))], [
    html.text(label),
  ])
}
