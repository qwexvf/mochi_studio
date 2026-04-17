// mochi_studio/playground.gleam
// Interactive GraphQL playground panel

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import mochi_studio/share
import mochi_studio/storage

pub type Model {
  Model(
    endpoint: String,
    query: String,
    variables: String,
    headers: Dict(String, String),
    response: Option(String),
    loading: Bool,
    error: Option(String),
    active_collection_item: Option(String),
  )
}

pub type Msg {
  QueryChanged(String)
  VariablesChanged(String)
  ExecuteQuery
  GotResponse(Result(String, String))
  CopyShareLink
  LoadFromUrl
}

pub fn init(endpoint: String) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      endpoint: endpoint,
      query: default_query(),
      variables: "{}",
      headers: dict.new(),
      response: None,
      loading: False,
      error: None,
      active_collection_item: None,
    )
  #(model, load_from_url())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    QueryChanged(q) -> #(Model(..model, query: q), effect.none())
    VariablesChanged(v) -> #(Model(..model, variables: v), effect.none())

    ExecuteQuery -> {
      let model = Model(..model, loading: True, error: None, response: None)
      #(model, execute(model))
    }

    GotResponse(Ok(body)) -> #(
      Model(..model, loading: False, response: Some(pretty_print(body))),
      effect.none(),
    )

    GotResponse(Error(err)) -> #(
      Model(..model, loading: False, error: Some(err)),
      effect.none(),
    )

    CopyShareLink -> #(model, share.copy_link(model.query, model.variables))

    LoadFromUrl -> {
      case share.read_url() {
        Some(#(q, v)) -> #(
          Model(..model, query: q, variables: v),
          effect.none(),
        )
        None -> #(model, effect.none())
      }
    }
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("playground")], [
    html.div([attribute.class("playground-editors")], [
      view_query_editor(model),
      view_variables_editor(model),
    ]),
    html.div([attribute.class("playground-response")], [
      view_toolbar(model),
      view_response(model),
    ]),
  ])
}

fn view_query_editor(model: Model) -> Element(Msg) {
  html.div([attribute.class("editor-pane")], [
    html.label([], [html.text("Query")]),
    html.textarea(
      [
        attribute.class("query-editor"),
        attribute.value(model.query),
        event.on_input(QueryChanged),
      ],
      model.query,
    ),
  ])
}

fn view_variables_editor(model: Model) -> Element(Msg) {
  html.div([attribute.class("editor-pane")], [
    html.label([], [html.text("Variables")]),
    html.textarea(
      [
        attribute.class("variables-editor"),
        attribute.value(model.variables),
        event.on_input(VariablesChanged),
      ],
      model.variables,
    ),
  ])
}

fn view_toolbar(model: Model) -> Element(Msg) {
  html.div([attribute.class("toolbar")], [
    html.button(
      [
        attribute.class("run-button"),
        attribute.disabled(model.loading),
        event.on_click(ExecuteQuery),
      ],
      [html.text(case model.loading { True -> "Running…" False -> "Run" })],
    ),
    html.button([event.on_click(CopyShareLink)], [html.text("Share")]),
  ])
}

fn view_response(model: Model) -> Element(Msg) {
  case model.error {
    Some(err) ->
      html.pre([attribute.class("response error")], [html.text(err)])
    None ->
      html.pre([attribute.class("response")], [
        html.text(option.unwrap(model.response, "")),
      ])
  }
}

fn execute(_model: Model) -> Effect(Msg) {
  // TODO: use lustre_http to POST to model.endpoint
  effect.none()
}

fn load_from_url() -> Effect(Msg) {
  effect.from(fn(dispatch) { dispatch(LoadFromUrl) })
}

fn pretty_print(json_str: String) -> String {
  case json.parse(json_str, decode.dynamic) {
    Ok(_) -> json_str
    Error(_) -> json_str
  }
}

fn default_query() -> String {
  "{\n  __typename\n}"
}
