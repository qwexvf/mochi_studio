// mochi_studio/app.gleam
// Root Lustre application — Model, Msg, update, view

import gleam/option.{type Option, None, Some}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import mochi_studio/collection.{type Collection}
import mochi_studio/panel.{type Panel, Builder, Playground}
import mochi_studio/playground as pg
import mochi_studio/schema_builder as sb

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
    let model =
      Model(
        endpoint: endpoint,
        active_panel: Playground,
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
    SwitchPanel(panel) -> #(Model(..model, active_panel: panel), effect.none())
    PlaygroundMsg(m) -> {
      let #(pg_model, pg_effect) = pg.update(model.playground, m)
      #(Model(..model, playground: pg_model), effect.map(pg_effect, PlaygroundMsg))
    }
    BuilderMsg(m) -> {
      let #(sb_model, sb_effect) = sb.update(model.builder, m)
      #(Model(..model, builder: sb_model), effect.map(sb_effect, BuilderMsg))
    }
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([], [
    view_navbar(model.active_panel),
    case model.active_panel {
      Playground -> pg.view(model.playground) |> element.map(PlaygroundMsg)
      Builder -> sb.view(model.builder) |> element.map(BuilderMsg)
    },
  ])
}

fn view_navbar(active: Panel) -> Element(Msg) {
  html.nav([], [
    html.span([], [html.text("mochi studio")]),
    panel.tab_button(Playground, active, SwitchPanel),
    panel.tab_button(Builder, active, SwitchPanel),
  ])
}
