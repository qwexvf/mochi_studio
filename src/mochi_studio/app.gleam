// mochi_studio/app.gleam
// Root Lustre application — Model, Msg, update, view

import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import mochi_studio/collection.{type Collection}
import mochi_studio/panel.{type Panel, Builder, Playground}
import mochi_studio/playground as pg
import mochi_studio/schema_builder as sb

@external(javascript, "./app_ffi.mjs", "get_hash_panel")
fn get_hash_panel() -> String {
  "playground"
}

@external(javascript, "./app_ffi.mjs", "set_hash_panel")
fn set_hash_panel(panel: String) -> Nil {
  let _ = panel
  Nil
}

pub type Model {
  Model(
    endpoint: String,
    active_panel: Panel,
    playground: pg.Model,
    builder: sb.Model,
    collections: List(Collection),
  )
}

pub type Msg {
  SwitchPanel(Panel)
  PlaygroundMsg(pg.Msg)
  BuilderMsg(sb.Msg)
}

pub fn init(endpoint: String) -> fn(Nil) -> #(Model, Effect(Msg)) {
  fn(_) {
    let #(pg_model, pg_effect) = pg.init(endpoint)
    let #(sb_model, sb_effect) = sb.init()
    let initial_panel = case get_hash_panel() {
      "builder" -> Builder
      _ -> Playground
    }
    let model =
      Model(
        endpoint: endpoint,
        active_panel: initial_panel,
        playground: pg_model,
        builder: sb_model,
        collections: [],
      )
    let effect =
      effect.batch([
        effect.map(pg_effect, PlaygroundMsg),
        effect.map(sb_effect, BuilderMsg),
      ])
    #(model, effect)
  }
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SwitchPanel(panel) -> {
      let hash = case panel {
        Playground -> "playground"
        Builder -> "builder"
      }
      #(
        Model(..model, active_panel: panel),
        effect.from(fn(_) { set_hash_panel(hash) }),
      )
    }
    PlaygroundMsg(m) -> {
      let #(pg_model, pg_effect) = pg.update(model.playground, m)
      #(
        Model(..model, playground: pg_model),
        effect.map(pg_effect, PlaygroundMsg),
      )
    }
    BuilderMsg(m) -> {
      let #(sb_model, sb_effect) = sb.update(model.builder, m)
      #(Model(..model, builder: sb_model), effect.map(sb_effect, BuilderMsg))
    }
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div(
    [attribute.class("flex flex-col h-screen bg-gray-950 text-gray-100")],
    [
      view_navbar(model.active_panel),
      html.main([attribute.class("flex-1 overflow-hidden")], [
        case model.active_panel {
          Playground -> pg.view(model.playground) |> element.map(PlaygroundMsg)
          Builder -> sb.view(model.builder) |> element.map(BuilderMsg)
        },
      ]),
    ],
  )
}

fn view_navbar(active: Panel) -> Element(Msg) {
  html.nav(
    [
      attribute.class(
        "flex items-center gap-4 px-4 h-12 bg-gray-900 border-b border-gray-800 shrink-0",
      ),
    ],
    [
      html.span(
        [attribute.class("text-pink-400 font-bold tracking-tight mr-4")],
        [html.text("mochi studio")],
      ),
      panel.tab_button(Playground, active, SwitchPanel),
      panel.tab_button(Builder, active, SwitchPanel),
    ],
  )
}
