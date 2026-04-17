// mochi_studio/schema_builder.gleam

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import mochi_studio/schema_node.{type SchemaNode, FieldDef, SchemaNode}

const diagram_id = "sb-diagram"
const container_id = "sb-container"

// ── FFI ───────────────────────────────────────────────────────────────────────

@external(javascript, "./diagram_ffi.mjs", "init_diagram")
fn do_init(container_id: String, on_generate: fn(String) -> Nil) -> Nil {
  let _ = container_id
  let _ = on_generate
  Nil
}

@external(javascript, "./diagram_ffi.mjs", "generate")
fn do_generate(callback: fn(String) -> Nil) -> Nil {
  let _ = callback
  Nil
}

@external(javascript, "./panel_resize_ffi.mjs", "init_resize")
fn do_init_resize(container_id: String) -> Nil {
  let _ = container_id
  Nil
}

@external(javascript, "./schema_builder_ffi.mjs", "copyToClipboard")
fn do_copy(text: String) -> Nil {
  let _ = text
  Nil
}

// ── Types ─────────────────────────────────────────────────────────────────────

pub type OutputTab {
  GleamTab
  SdlTab
  SqlTab
  MochiTab
}

pub type GeneratedOutput {
  GeneratedOutput(
    gleam_types: String,
    sdl: String,
    sql: String,
    mochi_schema: String,
  )
}

pub type Model {
  Model(
    output: Option(GeneratedOutput),
    output_tab: OutputTab,
  )
}

pub type Msg {
  GenerateAll
  GotGenerated(String)
  SwitchOutputTab(OutputTab)
  CopyToClipboard(String)
}

// ── Init ──────────────────────────────────────────────────────────────────────

pub fn init() -> #(Model, Effect(Msg)) {
  let model = Model(output: None, output_tab: GleamTab)
  let eff = effect.from(fn(dispatch) {
    do_init(diagram_id, fn(json) { dispatch(GotGenerated(json)) })
    do_init_resize(container_id)
  })
  #(model, eff)
}

// ── Update ────────────────────────────────────────────────────────────────────

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GenerateAll ->
      #(model, effect.from(fn(dispatch) {
        do_generate(fn(json) { dispatch(GotGenerated(json)) })
      }))

    GotGenerated(json_str) -> {
      let output = case decode_nodes(json_str) {
        Ok(nodes) ->
          Some(GeneratedOutput(
            gleam_types: schema_node.nodes_to_gleam(nodes),
            sdl: schema_node.nodes_to_sdl(nodes),
            sql: schema_node.nodes_to_sql(nodes),
            mochi_schema: schema_node.nodes_to_mochi_schema(nodes),
          ))
        Error(_) -> None
      }
      #(Model(..model, output: output), effect.none())
    }

    SwitchOutputTab(tab) -> #(Model(..model, output_tab: tab), effect.none())

    CopyToClipboard(text) ->
      #(model, effect.from(fn(_) { do_copy(text) }))
  }
}

// ── JSON decode ───────────────────────────────────────────────────────────────

fn decode_nodes(json_str: String) -> Result(List(SchemaNode), json.DecodeError) {
  let field_decoder = {
    use name       <- decode.field("name", decode.string)
    use field_type <- decode.field("field_type", decode.string)
    use non_null   <- decode.field("non_null", decode.bool)
    decode.success(FieldDef(name: name, field_type: field_type, non_null: non_null))
  }

  let node_decoder = {
    use id     <- decode.field("id", decode.string)
    use name   <- decode.field("name", decode.string)
    use kind   <- decode.field("kind", decode.string)
    use fields <- decode.field("fields", decode.list(field_decoder))
    use x      <- decode.field("x", decode.int)
    use y      <- decode.field("y", decode.int)
    decode.success(SchemaNode(
      id: id,
      name: name,
      kind: decode_kind(kind),
      fields: fields,
      x: x,
      y: y,
    ))
  }

  json.parse(json_str, decode.list(node_decoder))
}

fn decode_kind(s: String) -> schema_node.NodeKind {
  case s {
    "InputObject" -> schema_node.InputObject
    "Enum"        -> schema_node.Enum
    "Union"       -> schema_node.Union
    _             -> schema_node.Object
  }
}

// ── View ──────────────────────────────────────────────────────────────────────

pub fn view(model: Model) -> Element(Msg) {
  html.div(
    [attribute.id(container_id), attribute.class("flex h-full overflow-hidden")],
    [
      view_diagram(),
      view_resize_handle("right"),
      view_right_panel(model),
    ],
  )
}

fn view_resize_handle(side: String) -> Element(Msg) {
  html.div(
    [
      attribute.class("w-1 shrink-0 cursor-col-resize bg-gray-800 hover:bg-indigo-500 transition-colors"),
      attribute.attribute("data-resize-handle", side),
    ],
    [],
  )
}

fn view_diagram() -> Element(Msg) {
  html.div(
    [
      attribute.id(diagram_id),
      attribute.class("flex-1 h-full relative overflow-hidden"),
      attribute.style("background", "#0f172a"),
    ],
    [],
  )
}

fn view_right_panel(model: Model) -> Element(Msg) {
  let tabs = [
    #(GleamTab, "Gleam"),
    #(SdlTab, "SDL"),
    #(SqlTab, "SQL"),
    #(MochiTab, "Mochi"),
  ]
  let content = case model.output {
    None -> "// Click Generate"
    Some(out) ->
      case model.output_tab {
        GleamTab -> out.gleam_types
        SdlTab   -> out.sdl
        SqlTab   -> out.sql
        MochiTab -> out.mochi_schema
      }
  }
  html.div(
    [
      attribute.class("flex flex-col bg-gray-900 border-l border-gray-800 shrink-0 overflow-hidden"),
      attribute.style("width", "280px"),
      attribute.attribute("data-panel", "right"),
    ],
    [
      // Tab bar + Generate button
      html.div(
        [attribute.class("flex items-center gap-1 px-2 py-1.5 border-b border-gray-800 flex-wrap")],
        [
          html.button(
            [
              attribute.class("px-2 py-1 rounded bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-medium transition-colors mr-1"),
              event.on_click(GenerateAll),
            ],
            [html.text("Generate")],
          ),
          ..list.map(tabs, fn(pair) {
            let #(tab, label) = pair
            html.button(
              [
                attribute.class(case model.output_tab == tab {
                  True  -> "px-2 py-1 rounded text-xs text-indigo-300 bg-indigo-500/20 border border-indigo-500/30"
                  False -> "px-2 py-1 rounded text-xs text-gray-500 hover:text-gray-300 transition-colors"
                }),
                event.on_click(SwitchOutputTab(tab)),
              ],
              [html.text(label)],
            )
          })
        ],
      ),
      // Copy button
      html.div(
        [attribute.class("flex justify-end px-2 py-1 border-b border-gray-800")],
        [
          html.button(
            [
              attribute.class("px-2 py-0.5 text-xs text-gray-400 hover:text-white hover:bg-gray-800 rounded transition-colors"),
              event.on_click(CopyToClipboard(content)),
            ],
            [html.text("Copy")],
          ),
        ],
      ),
      html.pre(
        [attribute.class("flex-1 p-3 font-mono text-xs text-gray-300 overflow-auto leading-relaxed")],
        [html.text(content)],
      ),
    ],
  )
}
