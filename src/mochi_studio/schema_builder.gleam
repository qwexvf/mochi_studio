// mochi_studio/schema_builder.gleam

import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg
import lustre/event
import mochi_studio/schema_node.{type SchemaNode}

const canvas_id = "schema-canvas"

const zoom_min = 0.25

const zoom_max = 2.0

const zoom_step = 0.1

const snap_grid = 20

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
    nodes: List(SchemaNode),
    selected: Option(String),
    generated_code: Option(String),
    canvas_offset_x: Float,
    canvas_offset_y: Float,
    zoom: Float,
    snap_to_grid: Bool,
    output: Option(GeneratedOutput),
    output_tab: OutputTab,
    write_status: WriteStatus,
  )
}

pub type WriteStatus {
  Idle
  Writing
  WriteOk(List(String))
  WriteError(String)
}

pub type Msg {
  AddType(kind: schema_node.NodeKind)
  SelectNode(id: String)
  DeselectNode
  UpdateNode(schema_node.SchemaNode)
  RemoveNode(id: String)
  AddField(node_id: String)
  GenerateCode
  GotCode(String)
  GenerateAll
  SwitchOutputTab(OutputTab)
  CopyToClipboard(String)
  WriteToProject
  GotWriteResult(Result(List(String), String))
  NodeDragStarted(id: String, mouse_x: Int, mouse_y: Int)
  NodeDragging(id: String, dx: Int, dy: Int)
  NodeDragEnded(id: String)
  PanStart(x: Int, y: Int)
  Panning(dx: Int, dy: Int)
  PanEnd
  ZoomChanged(delta_y: Float, mouse_x: Float, mouse_y: Float)
  ZoomIn
  ZoomOut
  ResetView
  FitToScreen
  ToggleSnap
  DeleteSelected
}

pub fn init() -> #(Model, Effect(Msg)) {
  let model =
    Model(
      nodes: [],
      selected: None,
      generated_code: None,
      canvas_offset_x: 0.0,
      canvas_offset_y: 0.0,
      zoom: 1.0,
      snap_to_grid: True,
      output: None,
      output_tab: GleamTab,
      write_status: Idle,
    )
  let eff =
    effect.batch([
      listen_wheel_effect(),
      listen_keyboard_effect(),
    ])
  #(model, eff)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    AddType(kind) -> {
      let node = schema_node.new(kind)
      #(Model(..model, nodes: [node, ..model.nodes]), effect.none())
    }
    SelectNode(id) -> #(Model(..model, selected: Some(id)), effect.none())
    DeselectNode -> #(Model(..model, selected: None), effect.none())
    UpdateNode(updated) -> {
      let nodes =
        list.map(model.nodes, fn(n) {
          case n.id == updated.id {
            True -> updated
            False -> n
          }
        })
      #(Model(..model, nodes: nodes), effect.none())
    }
    RemoveNode(id) -> {
      let nodes = list.filter(model.nodes, fn(n) { n.id != id })
      #(Model(..model, nodes: nodes, selected: None), effect.none())
    }
    AddField(node_id) -> {
      let nodes =
        list.map(model.nodes, fn(n) {
          case n.id == node_id {
            True -> schema_node.add_field(n)
            False -> n
          }
        })
      #(Model(..model, nodes: nodes), effect.none())
    }
    GenerateCode -> #(model, generate_code(model.nodes))
    GotCode(code) -> #(
      Model(..model, generated_code: Some(code)),
      effect.none(),
    )
    NodeDragStarted(id, mouse_x, mouse_y) -> {
      let eff =
        schema_node.start_node_drag(
          id,
          mouse_x,
          mouse_y,
          model.zoom,
          fn(nid, dx, dy) { NodeDragging(id: nid, dx: dx, dy: dy) },
          fn(nid) { NodeDragEnded(id: nid) },
        )
      #(Model(..model, selected: Some(id)), eff)
    }
    NodeDragging(id, dx, dy) -> {
      let nodes =
        list.map(model.nodes, fn(n) {
          case n.id == id {
            True -> {
              let new_x = n.x + dx
              let new_y = n.y + dy
              let snapped_x = case model.snap_to_grid {
                True -> snap(new_x, snap_grid)
                False -> new_x
              }
              let snapped_y = case model.snap_to_grid {
                True -> snap(new_y, snap_grid)
                False -> new_y
              }
              schema_node.SchemaNode(..n, x: snapped_x, y: snapped_y)
            }
            False -> n
          }
        })
      #(Model(..model, nodes: nodes), effect.none())
    }
    NodeDragEnded(_id) -> #(model, effect.none())
    PanStart(x, y) -> {
      let eff = start_canvas_pan(x, y)
      #(model, eff)
    }
    Panning(dx, dy) -> {
      #(
        Model(
          ..model,
          canvas_offset_x: model.canvas_offset_x +. int.to_float(dx),
          canvas_offset_y: model.canvas_offset_y +. int.to_float(dy),
        ),
        effect.none(),
      )
    }
    PanEnd -> #(model, effect.none())
    ZoomChanged(delta_y, mouse_x, mouse_y) -> {
      let direction = case delta_y >. 0.0 {
        True -> -1.0
        False -> 1.0
      }
      let old_z = model.zoom
      let new_z = clamp(old_z +. direction *. zoom_step, zoom_min, zoom_max)
      // Zoom toward mouse cursor: keep world point under cursor fixed
      let world_x = { mouse_x -. model.canvas_offset_x } /. old_z
      let world_y = { mouse_y -. model.canvas_offset_y } /. old_z
      let new_offset_x = mouse_x -. world_x *. new_z
      let new_offset_y = mouse_y -. world_y *. new_z
      #(
        Model(
          ..model,
          zoom: new_z,
          canvas_offset_x: new_offset_x,
          canvas_offset_y: new_offset_y,
        ),
        effect.none(),
      )
    }
    ZoomIn -> {
      let new_z = clamp(model.zoom +. zoom_step, zoom_min, zoom_max)
      #(Model(..model, zoom: new_z), effect.none())
    }
    ZoomOut -> {
      let new_z = clamp(model.zoom -. zoom_step, zoom_min, zoom_max)
      #(Model(..model, zoom: new_z), effect.none())
    }
    ResetView -> {
      #(
        Model(..model, zoom: 1.0, canvas_offset_x: 0.0, canvas_offset_y: 0.0),
        effect.none(),
      )
    }
    FitToScreen -> {
      let result = fit_to_screen(model)
      #(result, effect.none())
    }
    ToggleSnap -> {
      #(Model(..model, snap_to_grid: !model.snap_to_grid), effect.none())
    }
    DeleteSelected -> {
      case model.selected {
        None -> #(model, effect.none())
        Some(id) -> {
          let nodes = list.filter(model.nodes, fn(n) { n.id != id })
          #(Model(..model, nodes: nodes, selected: None), effect.none())
        }
      }
    }
    GenerateAll -> {
      let out =
        GeneratedOutput(
          gleam_types: schema_node.nodes_to_gleam(model.nodes),
          sdl: schema_node.nodes_to_sdl(model.nodes),
          sql: schema_node.nodes_to_sql(model.nodes),
          mochi_schema: schema_node.nodes_to_mochi_schema(model.nodes),
        )
      #(Model(..model, output: Some(out)), effect.none())
    }
    SwitchOutputTab(tab) -> #(Model(..model, output_tab: tab), effect.none())
    CopyToClipboard(text) -> #(model, do_copy_effect(text))
    WriteToProject -> {
      case model.output {
        None -> #(model, effect.none())
        Some(out) ->
          #(
            Model(..model, write_status: Writing),
            write_to_project_effect(out),
          )
      }
    }
    GotWriteResult(Ok(files)) -> #(
      Model(..model, write_status: WriteOk(files)),
      effect.none(),
    )
    GotWriteResult(Error(err)) -> #(
      Model(..model, write_status: WriteError(err)),
      effect.none(),
    )
  }
}

fn snap(value: Int, grid: Int) -> Int {
  let remainder = value % grid
  case remainder >= grid / 2 {
    True -> value + { grid - remainder }
    False -> value - remainder
  }
}

fn clamp(value: Float, lo: Float, hi: Float) -> Float {
  case value <. lo {
    True -> lo
    False ->
      case value >. hi {
        True -> hi
        False -> value
      }
  }
}

fn fit_to_screen(model: Model) -> Model {
  case model.nodes {
    [] -> model
    nodes -> {
      // estimate canvas size (fallback 800x600)
      let canvas_w = 800.0
      let canvas_h = 600.0
      let padding = 40.0

      // bounding box of all nodes
      let min_x =
        list.fold(nodes, 999_999, fn(acc, n) {
          case n.x < acc {
            True -> n.x
            False -> acc
          }
        })
      let min_y =
        list.fold(nodes, 999_999, fn(acc, n) {
          case n.y < acc {
            True -> n.y
            False -> acc
          }
        })
      let max_x =
        list.fold(nodes, -999_999, fn(acc, n) {
          let right = n.x + schema_node.node_card_width()
          case right > acc {
            True -> right
            False -> acc
          }
        })
      let max_y =
        list.fold(nodes, -999_999, fn(acc, n) {
          let bottom =
            n.y
            + schema_node.node_header_height()
            + list.length(n.fields)
            * schema_node.node_field_height()
            + 36
          case bottom > acc {
            True -> bottom
            False -> acc
          }
        })

      let content_w = int.to_float(max_x - min_x)
      let content_h = int.to_float(max_y - min_y)
      let scale_x = { canvas_w -. padding *. 2.0 } /. content_w
      let scale_y = { canvas_h -. padding *. 2.0 } /. content_h
      let new_zoom = clamp(float.min(scale_x, scale_y), zoom_min, zoom_max)
      let offset_x = padding -. int.to_float(min_x) *. new_zoom
      let offset_y = padding -. int.to_float(min_y) *. new_zoom

      Model(
        ..model,
        zoom: new_zoom,
        canvas_offset_x: offset_x,
        canvas_offset_y: offset_y,
      )
    }
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("flex flex-col h-full")], [
    view_toolbar(model),
    html.div([attribute.class("flex flex-1 overflow-hidden")], [
      view_sidebar(model),
      view_canvas(model),
      view_output_panel(model),
    ]),
    view_status_bar(model),
  ])
}

fn view_toolbar(model: Model) -> Element(Msg) {
  let zoom_pct = int.to_string(float.round(model.zoom *. 100.0)) <> "%"
  let snap_class = case model.snap_to_grid {
    True -> "bg-pink-500/20 text-pink-300 border-pink-500/40"
    False -> "text-gray-400 border-gray-700 hover:text-gray-200"
  }
  html.div(
    [
      attribute.class(
        "flex items-center gap-1 px-3 py-1.5 bg-gray-900 border-b border-gray-800 shrink-0",
      ),
    ],
    [
      html.div([attribute.class("flex items-center gap-1 ml-auto")], [
        toolbar_btn("−", ZoomOut),
        html.button(
          [
            attribute.class(
              "px-2 py-1 text-xs text-gray-300 hover:text-white transition-colors tabular-nums w-12 text-center",
            ),
            event.on_click(ResetView),
          ],
          [html.text(zoom_pct)],
        ),
        toolbar_btn("+", ZoomIn),
        html.div([attribute.class("w-px h-4 bg-gray-700 mx-1")], []),
        toolbar_btn("⊞ Fit", FitToScreen),
        toolbar_btn("⟳ Reset", ResetView),
        html.div([attribute.class("w-px h-4 bg-gray-700 mx-1")], []),
        html.button(
          [
            attribute.class(
              "px-2 py-1 rounded text-xs border transition-colors "
              <> snap_class,
            ),
            event.on_click(ToggleSnap),
          ],
          [html.text("⊹ Snap")],
        ),
      ]),
    ],
  )
}

fn toolbar_btn(label: String, msg: Msg) -> Element(Msg) {
  html.button(
    [
      attribute.class(
        "px-2 py-1 rounded text-xs text-gray-400 hover:text-white hover:bg-gray-800 transition-colors",
      ),
      event.on_click(msg),
    ],
    [html.text(label)],
  )
}

fn view_sidebar(_model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "flex flex-col gap-2 w-48 p-3 bg-gray-900 border-r border-gray-800 shrink-0",
      ),
    ],
    [
      html.p(
        [
          attribute.class("text-xs text-gray-500 uppercase tracking-wider mb-1"),
        ],
        [html.text("Add Type")],
      ),
      type_button("Object", AddType(schema_node.Object)),
      type_button("Input", AddType(schema_node.InputObject)),
      type_button("Enum", AddType(schema_node.Enum)),
      type_button("Union", AddType(schema_node.Union)),
      html.div([attribute.class("mt-auto")], [
        html.button(
          [
            attribute.class(
              "w-full px-3 py-2 rounded bg-pink-500 hover:bg-pink-400 text-white text-sm font-medium transition-colors",
            ),
            event.on_click(GenerateCode),
          ],
          [html.text("Generate Code")],
        ),
      ]),
    ],
  )
}

fn type_button(label: String, msg: Msg) -> Element(Msg) {
  html.button(
    [
      attribute.class(
        "px-3 py-1.5 rounded text-sm text-left text-gray-300 hover:bg-gray-800 hover:text-white transition-colors",
      ),
      event.on_click(msg),
    ],
    [html.text(label)],
  )
}

fn view_canvas(model: Model) -> Element(Msg) {
  let ox = float.to_string(model.canvas_offset_x)
  let oy = float.to_string(model.canvas_offset_y)
  let z = float.to_string(model.zoom)
  let transform = "translate(" <> ox <> "px, " <> oy <> "px) scale(" <> z <> ")"

  html.div(
    [
      attribute.id(canvas_id),
      attribute.class(
        "relative flex-1 overflow-hidden bg-gray-950 cursor-grab active:cursor-grabbing",
      ),
      event.on("mousedown", {
        use mouse_x <- decode.field("clientX", decode.int)
        use mouse_y <- decode.field("clientY", decode.int)
        decode.success(PanStart(x: mouse_x, y: mouse_y))
      }),
    ],
    [
      view_canvas_grid(),
      html.div(
        [
          attribute.class("absolute inset-0"),
          attribute.style("transform", transform),
          attribute.style("transform-origin", "0 0"),
        ],
        case model.nodes {
          [] -> [
            html.div(
              [
                attribute.class(
                  "absolute inset-0 flex items-center justify-center text-gray-700 text-sm pointer-events-none",
                ),
              ],
              [html.text("Add a type from the sidebar to get started")],
            ),
          ]
          nodes -> {
            let connection_svg = view_connections(nodes)
            let node_cards =
              list.map(nodes, fn(node) {
                schema_node.view(node, model.selected)
                |> element.map(fn(msg) {
                  case msg {
                    schema_node.Selected(id) -> SelectNode(id)
                    schema_node.Updated(n) -> UpdateNode(n)
                    schema_node.Removed(id) -> RemoveNode(id)
                    schema_node.FieldAdded(id) -> AddField(id)
                    schema_node.DragStarted(id, sx, sy) ->
                      NodeDragStarted(id: id, mouse_x: sx, mouse_y: sy)
                  }
                })
              })
            [connection_svg, ..node_cards]
          }
        },
      ),
      view_minimap(model),
    ],
  )
}

fn view_canvas_grid() -> Element(Msg) {
  html.div(
    [
      attribute.class("absolute inset-0 pointer-events-none"),
      attribute.style(
        "background-image",
        "radial-gradient(circle, #374151 1px, transparent 1px)",
      ),
      attribute.style("background-size", "24px 24px"),
      attribute.style("opacity", "0.4"),
    ],
    [],
  )
}

fn view_connections(nodes: List(SchemaNode)) -> Element(Msg) {
  let node_names = list.map(nodes, fn(n) { n.name })
  let paths =
    list.flat_map(nodes, fn(src) {
      list.index_map(src.fields, fn(field, field_idx) {
        case list.contains(node_names, field.field_type) {
          False -> Error(Nil)
          True ->
            case list.find(nodes, fn(n) { n.name == field.field_type }) {
              Error(_) -> Error(Nil)
              Ok(target) -> {
                let card_w = schema_node.node_card_width()
                let header_h = schema_node.node_header_height()
                let field_h = schema_node.node_field_height()
                let sx = src.x + card_w
                let sy = src.y + header_h + field_idx * field_h + field_h / 2
                let tx = target.x
                let ty = target.y + header_h / 2
                let cp1x = sx + 80
                let cp1y = sy
                let cp2x = tx - 80
                let cp2y = ty
                let d =
                  "M "
                  <> int.to_string(sx)
                  <> " "
                  <> int.to_string(sy)
                  <> " C "
                  <> int.to_string(cp1x)
                  <> " "
                  <> int.to_string(cp1y)
                  <> " "
                  <> int.to_string(cp2x)
                  <> " "
                  <> int.to_string(cp2y)
                  <> " "
                  <> int.to_string(tx)
                  <> " "
                  <> int.to_string(ty)
                Ok(d)
              }
            }
        }
      })
    })
    |> list.filter_map(fn(x) { x })

  svg.svg(
    [
      attribute.class("absolute inset-0 pointer-events-none overflow-visible"),
      attribute.style("width", "100%"),
      attribute.style("height", "100%"),
    ],
    [
      svg.defs([], [
        svg.marker(
          [
            attribute.id("arrowhead"),
            attribute.attribute("markerWidth", "8"),
            attribute.attribute("markerHeight", "6"),
            attribute.attribute("refX", "8"),
            attribute.attribute("refY", "3"),
            attribute.attribute("orient", "auto"),
          ],
          [
            svg.polygon([
              attribute.attribute("points", "0 0, 8 3, 0 6"),
              attribute.attribute("fill", "#6b7280"),
            ]),
          ],
        ),
      ]),
      svg.g(
        [],
        list.map(paths, fn(d) {
          svg.path([
            attribute.attribute("d", d),
            attribute.attribute("stroke", "#6b7280"),
            attribute.attribute("stroke-width", "1.5"),
            attribute.attribute("fill", "none"),
            attribute.attribute("stroke-dasharray", "4 2"),
            attribute.attribute("marker-end", "url(#arrowhead)"),
            attribute.attribute("opacity", "0.7"),
          ])
        }),
      ),
    ],
  )
}

// Minimap: 80x60 px panel in bottom-right of canvas
fn view_minimap(model: Model) -> Element(Msg) {
  let minimap_w = 80
  let minimap_h = 60
  // Logical canvas space shown in minimap (fixed world window)
  let world_w = 2000.0
  let world_h = 1500.0
  let scale_x = int.to_float(minimap_w) /. world_w
  let scale_y = int.to_float(minimap_h) /. world_h

  // Current viewport in world coords
  let vp_x = { 0.0 -. model.canvas_offset_x } /. model.zoom
  let vp_y = { 0.0 -. model.canvas_offset_y } /. model.zoom
  // Approximate viewport size (use 800x600 as canvas size estimate)
  let vp_w = 800.0 /. model.zoom
  let vp_h = 600.0 /. model.zoom

  let vp_rx = float.round(vp_x *. scale_x)
  let vp_ry = float.round(vp_y *. scale_y)
  let vp_rw = float.round(vp_w *. scale_x)
  let vp_rh = float.round(vp_h *. scale_y)

  let node_rects =
    list.map(model.nodes, fn(n) {
      let rx = float.round(int.to_float(n.x) *. scale_x)
      let ry = float.round(int.to_float(n.y) *. scale_y)
      let rw =
        float.round(int.to_float(schema_node.node_card_width()) *. scale_x)
      let rh =
        float.round(
          int.to_float(
            schema_node.node_header_height()
            + list.length(n.fields)
            * schema_node.node_field_height()
            + 8,
          )
          *. scale_y,
        )
      let color = case n.kind {
        schema_node.Object -> "#ec4899"
        schema_node.InputObject -> "#3b82f6"
        schema_node.Enum -> "#22c55e"
        schema_node.Union -> "#a855f7"
      }
      svg.rect([
        attribute.attribute("x", int.to_string(rx)),
        attribute.attribute("y", int.to_string(ry)),
        attribute.attribute("width", int.to_string(int.max(rw, 1))),
        attribute.attribute("height", int.to_string(int.max(rh, 1))),
        attribute.attribute("fill", color),
        attribute.attribute("opacity", "0.7"),
        attribute.attribute("rx", "1"),
      ])
    })

  let viewport_rect =
    svg.rect([
      attribute.attribute("x", int.to_string(vp_rx)),
      attribute.attribute("y", int.to_string(vp_ry)),
      attribute.attribute("width", int.to_string(int.max(vp_rw, 4))),
      attribute.attribute("height", int.to_string(int.max(vp_rh, 4))),
      attribute.attribute("fill", "none"),
      attribute.attribute("stroke", "#9ca3af"),
      attribute.attribute("stroke-width", "1"),
    ])

  html.div(
    [
      attribute.class(
        "absolute bottom-3 right-3 rounded border border-gray-700 bg-gray-900/80 overflow-hidden pointer-events-auto",
      ),
      attribute.style("width", int.to_string(minimap_w) <> "px"),
      attribute.style("height", int.to_string(minimap_h) <> "px"),
      event.on("click", {
        use mouse_x <- decode.field("offsetX", decode.float)
        use mouse_y <- decode.field("offsetY", decode.float)
        // Convert minimap click to world coords, then set offset
        let world_click_x = mouse_x /. scale_x
        let world_click_y = mouse_y /. scale_y
        let new_ox = { 0.0 -. { world_click_x -. 400.0 } } *. model.zoom
        let new_oy = { 0.0 -. { world_click_y -. 300.0 } } *. model.zoom
        decode.success(Panning(
          dx: float.round(new_ox -. model.canvas_offset_x),
          dy: float.round(new_oy -. model.canvas_offset_y),
        ))
      }),
    ],
    [
      svg.svg(
        [
          attribute.attribute("width", int.to_string(minimap_w)),
          attribute.attribute("height", int.to_string(minimap_h)),
        ],
        list.append(node_rects, [viewport_rect]),
      ),
    ],
  )
}

fn view_status_bar(model: Model) -> Element(Msg) {
  let n_types = list.length(model.nodes)
  let n_fields =
    list.fold(model.nodes, 0, fn(acc, n) { acc + list.length(n.fields) })
  let zoom_pct = int.to_string(float.round(model.zoom *. 100.0))
  let snap_label = case model.snap_to_grid {
    True -> " · snap on"
    False -> ""
  }
  html.div(
    [
      attribute.class(
        "flex items-center gap-4 px-4 py-1 bg-gray-900 border-t border-gray-800 text-xs text-gray-500 shrink-0",
      ),
    ],
    [
      html.span([], [
        html.text(
          int.to_string(n_types)
          <> " types · "
          <> int.to_string(n_fields)
          <> " fields · zoom "
          <> zoom_pct
          <> "%"
          <> snap_label,
        ),
      ]),
    ],
  )
}

fn view_output_panel(model: Model) -> Element(Msg) {
  let tabs = [
    #(GleamTab, "Gleam Types"),
    #(SdlTab, "SDL"),
    #(SqlTab, "SQL Migration"),
    #(MochiTab, "Mochi Schema"),
  ]
  let content = case model.output {
    None -> "// Click Generate All to see output"
    Some(out) ->
      case model.output_tab {
        GleamTab -> out.gleam_types
        SdlTab -> out.sdl
        SqlTab -> out.sql
        MochiTab -> out.mochi_schema
      }
  }
  html.div(
    [
      attribute.class(
        "flex flex-col bg-gray-900 border-l border-gray-800 shrink-0",
      ),
      attribute.style("width", "320px"),
    ],
    [
      html.div(
        [
          attribute.class(
            "flex items-center gap-1 px-2 py-1.5 border-b border-gray-800 overflow-x-auto",
          ),
        ],
        list.map(tabs, fn(tab_pair) {
          let #(tab, label) = tab_pair
          let is_active = model.output_tab == tab
          let cls = case is_active {
            True ->
              "px-2 py-1 rounded text-xs text-pink-300 bg-pink-500/20 border border-pink-500/40 whitespace-nowrap"
            False ->
              "px-2 py-1 rounded text-xs text-gray-400 hover:text-gray-200 hover:bg-gray-800 whitespace-nowrap transition-colors"
          }
          html.button(
            [attribute.class(cls), event.on_click(SwitchOutputTab(tab))],
            [html.text(label)],
          )
        }),
      ),
      html.div(
        [
          attribute.class(
            "flex items-center justify-between px-3 py-1.5 border-b border-gray-800",
          ),
        ],
        [
          html.button(
            [
              attribute.class(
                "px-3 py-1 rounded text-xs bg-pink-500 hover:bg-pink-400 text-white font-medium transition-colors",
              ),
              event.on_click(GenerateAll),
            ],
            [html.text("Generate All")],
          ),
          html.button(
            [
              attribute.class(
                "px-2 py-1 rounded text-xs text-gray-400 hover:text-white hover:bg-gray-800 transition-colors",
              ),
              event.on_click(CopyToClipboard(content)),
            ],
            [html.text("Copy")],
          ),
          html.button(
            [
              attribute.class(
                "px-2 py-1 rounded text-xs bg-blue-600 hover:bg-blue-500 text-white transition-colors",
              ),
              attribute.disabled(model.write_status == Writing),
              event.on_click(WriteToProject),
            ],
            [
              html.text(case model.write_status {
                Writing -> "Writing…"
                _ -> "Write"
              }),
            ],
          ),
        ],
      ),
      case model.write_status {
        Idle -> html.div([], [])
        Writing ->
          html.div(
            [attribute.class("px-3 py-1 text-xs text-blue-400 border-b border-gray-800")],
            [html.text("Writing files…")],
          )
        WriteOk(files) ->
          html.div(
            [attribute.class("px-3 py-1 text-xs text-green-400 border-b border-gray-800")],
            [html.text("✓ Wrote " <> int.to_string(list.length(files)) <> " file(s)")],
          )
        WriteError(err) ->
          html.div(
            [attribute.class("px-3 py-1 text-xs text-red-400 border-b border-gray-800")],
            [html.text("✗ " <> err)],
          )
      },
      html.pre(
        [
          attribute.class(
            "flex-1 p-3 font-mono text-xs text-gray-300 overflow-auto leading-relaxed",
          ),
        ],
        [html.text(content)],
      ),
    ],
  )
}

fn generate_code(nodes: List(SchemaNode)) -> Effect(Msg) {
  let code = schema_node.nodes_to_gleam(nodes)
  effect.from(fn(dispatch) { dispatch(GotCode(code)) })
}

fn do_copy_effect(text: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) { do_copy_to_clipboard(text) })
}

@external(javascript, "./schema_builder_ffi.mjs", "copyToClipboard")
fn do_copy_to_clipboard(text: String) -> Nil {
  let _ = text
  Nil
}

fn start_canvas_pan(start_x: Int, start_y: Int) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    do_start_canvas_pan(
      start_x,
      start_y,
      fn(dx, dy) { dispatch(Panning(dx: dx, dy: dy)) },
      fn() { dispatch(PanEnd) },
    )
  })
}

fn listen_wheel_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    do_listen_wheel(
      canvas_id,
      fn(delta_y, client_x, client_y, rect_x, rect_y, _rw, _rh) {
        let mx = client_x -. rect_x
        let my = client_y -. rect_y
        dispatch(ZoomChanged(delta_y: delta_y, mouse_x: mx, mouse_y: my))
      },
    )
  })
}

fn listen_keyboard_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    do_listen_keyboard(fn() { dispatch(DeleteSelected) }, fn() {
      dispatch(DeselectNode)
    })
  })
}

@external(javascript, "./schema_builder_ffi.mjs", "startCanvasPan")
fn do_start_canvas_pan(
  start_x: Int,
  start_y: Int,
  on_move: fn(Int, Int) -> Nil,
  on_end: fn() -> Nil,
) -> Nil {
  let _ = start_x
  let _ = start_y
  let _ = on_move
  let _ = on_end
  Nil
}

@external(javascript, "./schema_builder_ffi.mjs", "listenWheel")
fn do_listen_wheel(
  canvas_id: String,
  callback: fn(Float, Float, Float, Float, Float, Float, Float) -> Nil,
) -> Nil {
  let _ = canvas_id
  let _ = callback
  Nil
}

@external(javascript, "./schema_builder_ffi.mjs", "listenKeyboard")
fn do_listen_keyboard(on_delete: fn() -> Nil, on_escape: fn() -> Nil) -> Nil {
  let _ = on_delete
  let _ = on_escape
  Nil
}

fn write_to_project_effect(out: GeneratedOutput) -> Effect(Msg) {
  let files = [
    #("src/schema_types.gleam", out.gleam_types),
    #("schema.graphql", out.sdl),
    #("src/mochi_schema.gleam", out.mochi_schema),
  ]
  effect.from(fn(dispatch) {
    do_write_to_project(
      ".",
      files,
      fn(ok, value) {
        case ok {
          True -> dispatch(GotWriteResult(Ok([value])))
          False -> dispatch(GotWriteResult(Error(value)))
        }
      },
    )
  })
}

@external(javascript, "./schema_builder_ffi.mjs", "writeToProject")
fn do_write_to_project(
  project_path: String,
  files: List(#(String, String)),
  callback: fn(Bool, String) -> Nil,
) -> Nil {
  let _ = project_path
  let _ = files
  let _ = callback
  Nil
}
