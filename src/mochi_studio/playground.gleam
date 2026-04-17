// mochi_studio/playground.gleam

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import mochi_studio/collection.{type CollectionItem}
import mochi_studio/editor
import mochi_studio/share
import mochi_studio/sidebar

const query_editor_id = "cm-query"

const vars_editor_id = "cm-variables"

pub type Model {
  Model(
    endpoint: String,
    query: String,
    variables: String,
    headers: Dict(String, String),
    response: Option(String),
    loading: Bool,
    error: Option(String),
    schema_json: Option(String),
    sidebar: sidebar.Model,
  )
}

pub type Msg {
  QueryChanged(String)
  VariablesChanged(String)
  ExecuteQuery
  GotResponse(Result(String, String))
  GotIntrospection(Result(String, String))
  CopyShareLink
  LoadFromUrl
  SidebarMsg(sidebar.Msg)
  EditorsMounted
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
      schema_json: None,
      sidebar: sidebar.init(),
    )
  let effects =
    effect.batch([
      load_from_url(),
      mount_editors(model),
      introspect(endpoint),
    ])
  #(model, effects)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    QueryChanged(q) -> #(Model(..model, query: q), effect.none())
    VariablesChanged(v) -> #(Model(..model, variables: v), effect.none())

    ExecuteQuery -> {
      let m = Model(..model, loading: True, error: None, response: None)
      #(m, execute(m))
    }

    GotResponse(Ok(body)) -> #(
      Model(..model, loading: False, response: Some(pretty_print(body))),
      effect.none(),
    )
    GotResponse(Error(err)) -> #(
      Model(..model, loading: False, error: Some(err)),
      effect.none(),
    )

    GotIntrospection(Ok(schema)) -> {
      let m = Model(..model, schema_json: Some(schema))
      #(m, editor.update_schema(query_editor_id, schema))
    }
    GotIntrospection(Error(_)) -> #(model, effect.none())

    CopyShareLink -> #(model, share.copy_link(model.query, model.variables))

    LoadFromUrl -> {
      case share.read_url() {
        Some(#(q, v)) -> {
          let m = Model(..model, query: q, variables: v)
          let fx =
            effect.batch([
              editor.set_value(query_editor_id, q),
              editor.set_value(vars_editor_id, v),
            ])
          #(m, fx)
        }
        None -> #(model, effect.none())
      }
    }

    EditorsMounted -> #(model, effect.none())

    SidebarMsg(sidebar.SelectItem(item)) -> {
      let m = load_item(model, item)
      let fx =
        effect.batch([
          editor.set_value(query_editor_id, item.query),
          editor.set_value(vars_editor_id, item.variables),
        ])
      #(m, fx)
    }

    SidebarMsg(m) -> #(
      Model(..model, sidebar: sidebar.update(model.sidebar, m)),
      effect.none(),
    )
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("flex h-full")], [
    sidebar.view(model.sidebar) |> element.map(SidebarMsg),
    html.div(
      [attribute.class("flex flex-col flex-1 min-w-0 border-r border-gray-800")],
      [
        view_toolbar(model),
        html.div([attribute.class("flex flex-1 overflow-hidden")], [
          view_query_editor(model),
          html.div([attribute.class("w-px bg-gray-800")], []),
          view_variables_editor(model),
        ]),
      ],
    ),
    view_response(model),
  ])
}

fn view_toolbar(model: Model) -> Element(Msg) {
  html.div(
    [attribute.class("flex items-center gap-2 px-3 py-2 bg-gray-900 border-b border-gray-800 shrink-0")],
    [
      html.button(
        [
          attribute.class(
            "px-4 py-1.5 rounded bg-pink-500 hover:bg-pink-400 text-white text-sm font-medium disabled:opacity-50 transition-colors",
          ),
          attribute.disabled(model.loading),
          event.on_click(ExecuteQuery),
        ],
        [html.text(case model.loading { True -> "Running…" False -> "▶  Run" })],
      ),
      html.button(
        [
          attribute.class("px-3 py-1.5 rounded text-sm text-gray-400 hover:text-gray-100 transition-colors"),
          event.on_click(CopyShareLink),
        ],
        [html.text("Share")],
      ),
      html.span([attribute.class("ml-auto text-xs text-gray-600 font-mono")], [
        html.text(model.endpoint),
      ]),
    ],
  )
}

fn view_query_editor(_model: Model) -> Element(Msg) {
  html.div([attribute.class("flex flex-col flex-1 min-w-0")], [
    view_pane_label("Query"),
    editor.view(query_editor_id),
  ])
}

fn view_variables_editor(_model: Model) -> Element(Msg) {
  html.div([attribute.class("flex flex-col w-64 shrink-0")], [
    view_pane_label("Variables"),
    editor.view(vars_editor_id),
  ])
}

fn view_response(model: Model) -> Element(Msg) {
  html.div([attribute.class("flex flex-col w-96 shrink-0")], [
    view_pane_label("Response"),
    case model.error {
      Some(err) ->
        html.pre(
          [attribute.class("flex-1 p-3 font-mono text-sm text-red-400 overflow-auto")],
          [html.text(err)],
        )
      None ->
        html.pre(
          [attribute.class("flex-1 p-3 font-mono text-sm text-gray-300 overflow-auto")],
          [html.text(option.unwrap(model.response, "// Run a query to see results"))],
        )
    },
  ])
}

fn view_pane_label(label: String) -> Element(Msg) {
  html.div(
    [attribute.class("px-3 py-1 text-xs text-gray-500 bg-gray-900 border-b border-gray-800 shrink-0")],
    [html.text(label)],
  )
}

fn load_item(model: Model, item: CollectionItem) -> Model {
  Model(..model, query: item.query, variables: item.variables, response: None, error: None)
}

fn mount_editors(model: Model) -> Effect(Msg) {
  effect.batch([
    editor.mount(query_editor_id, model.query, QueryChanged),
    editor.mount(vars_editor_id, model.variables, VariablesChanged),
  ])
}

fn execute(model: Model) -> Effect(Msg) {
  let vars = case json.parse(model.variables, decode.dynamic) {
    Ok(_) -> model.variables
    Error(_) -> "{}"
  }
  let body =
    "{\"query\":"
    <> json.to_string(json.string(model.query))
    <> ",\"variables\":"
    <> vars
    <> "}"

  effect.from(fn(dispatch) {
    do_execute(model.endpoint, body, fn(ok, value) {
      case ok {
        True -> dispatch(GotResponse(Ok(value)))
        False -> dispatch(GotResponse(Error(value)))
      }
    })
  })
}

fn introspect(endpoint: String) -> Effect(Msg) {
  let body =
    "{\"query\":\"{__schema{queryType{name}types{kind name description fields(includeDeprecated:true){name description args{name description type{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name}}}}}}}}type{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name}}}}}}}isDeprecated deprecationReason}inputFields{name description type{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name}}}}}}}defaultValue}interfaces{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name}}}}}}}enumValues(includeDeprecated:true){name description isDeprecated deprecationReason}possibleTypes{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name}}}}}}}}directives{name description locations args{name description type{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name ofType{kind name}}}}}}}defaultValue}}}}\"}"

  effect.from(fn(dispatch) {
    do_execute(endpoint, body, fn(ok, value) {
      case ok {
        True -> dispatch(GotIntrospection(Ok(value)))
        False -> dispatch(GotIntrospection(Error(value)))
      }
    })
  })
}

@external(javascript, "./playground_ffi.mjs", "executeGraphQL")
fn do_execute(
  endpoint: String,
  body: String,
  callback: fn(Bool, String) -> Nil,
) -> Nil {
  let _ = endpoint
  let _ = body
  let _ = callback
  Nil
}

fn load_from_url() -> Effect(Msg) {
  effect.from(fn(dispatch) { dispatch(LoadFromUrl) })
}

fn pretty_print(json_str: String) -> String {
  do_pretty_print(json_str)
}

@external(javascript, "./playground_ffi.mjs", "prettyPrint")
fn do_pretty_print(json_str: String) -> String {
  json_str
}

fn default_query() -> String {
  "{\n  __typename\n}"
}
