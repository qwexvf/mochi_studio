// mochi_studio/panel.gleam
// Top-level panel navigation

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
  html.button(
    [
      attribute.class(case panel == active {
        True -> "tab active"
        False -> "tab"
      }),
      event.on_click(on_click(panel)),
    ],
    [html.text(label)],
  )
}
