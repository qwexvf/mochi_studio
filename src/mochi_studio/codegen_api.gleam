// mochi_studio/codegen_api.gleam
// Erlang-target API handlers: generate code, write files, save migrations

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile
import wisp.{type Request, type Response}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type ApiField {
  ApiField(name: String, field_type: String, non_null: Bool)
}

type ApiNode {
  ApiNode(id: String, kind: String, name: String, fields: List(ApiField))
}

// ---------------------------------------------------------------------------
// Decoders
// ---------------------------------------------------------------------------

fn field_decoder() -> decode.Decoder(ApiField) {
  use name <- decode.field("name", decode.string)
  use field_type <- decode.field("field_type", decode.string)
  use non_null <- decode.field("non_null", decode.bool)
  decode.success(ApiField(name:, field_type:, non_null:))
}

fn node_decoder() -> decode.Decoder(ApiNode) {
  use id <- decode.field("id", decode.string)
  use kind <- decode.field("kind", decode.string)
  use name <- decode.field("name", decode.string)
  use fields <- decode.field("fields", decode.list(field_decoder()))
  decode.success(ApiNode(id:, kind:, name:, fields:))
}

fn nodes_decoder() -> decode.Decoder(List(ApiNode)) {
  use nodes <- decode.field("nodes", decode.list(node_decoder()))
  decode.success(nodes)
}

// ---------------------------------------------------------------------------
// POST /api/generate
// ---------------------------------------------------------------------------

pub fn handle_generate(req: Request) -> Response {
  use body <- wisp.require_string_body(req)
  case json.parse(body, nodes_decoder()) {
    Error(_) -> wisp.bad_request("Expected {\"nodes\": [...]}")
    Ok(nodes) -> {
      let out =
        json.object([
          #("gleam_types", json.string(gen_gleam_types(nodes))),
          #("sdl", json.string(gen_sdl(nodes))),
          #("sql", json.string(gen_sql(nodes))),
          #("mochi_schema", json.string(gen_mochi_schema(nodes))),
        ])
      wisp.json_response(json.to_string(out), 200)
    }
  }
}

// ---------------------------------------------------------------------------
// POST /api/write
// { "project_path": ".", "files": [{"path": "src/schema.gleam", "content": "..."}] }
// ---------------------------------------------------------------------------

fn write_decoder() -> decode.Decoder(#(String, List(#(String, String)))) {
  let file_dec = {
    use p <- decode.field("path", decode.string)
    use c <- decode.field("content", decode.string)
    decode.success(#(p, c))
  }
  use project_path <- decode.field("project_path", decode.string)
  use files <- decode.field("files", decode.list(file_dec))
  decode.success(#(project_path, files))
}

pub fn handle_write(req: Request) -> Response {
  use body <- wisp.require_string_body(req)
  case json.parse(body, write_decoder()) {
    Error(_) -> wisp.bad_request("Expected {\"project_path\":\"...\",\"files\":[...]}")
    Ok(#(project_path, files)) -> {
      let pairs =
        list.map(files, fn(f) {
          let #(rel, content) = f
          let full = project_path <> "/" <> rel
          let dir = dirname(full)
          let r =
            result.try(
              simplifile.create_directory_all(dir)
                |> result.replace_error(Nil),
              fn(_) {
                simplifile.write(to: full, contents: content)
                |> result.replace_error(Nil)
              },
            )
          #(rel, r)
        })

      let written =
        list.filter_map(pairs, fn(p) {
          case p.1 {
            Ok(_) -> Ok(p.0)
            Error(_) -> Error(Nil)
          }
        })
      let errors =
        list.filter_map(pairs, fn(p) {
          case p.1 {
            Ok(_) -> Error(Nil)
            Error(_) -> Ok(p.0 <> ": write failed")
          }
        })

      let resp =
        json.object([
          #("written", json.array(written, json.string)),
          #("errors", json.array(errors, json.string)),
        ])
      wisp.json_response(json.to_string(resp), 200)
    }
  }
}

// ---------------------------------------------------------------------------
// POST /api/migrate
// { "sql": "...", "project_path": "." }
// ---------------------------------------------------------------------------

fn migrate_decoder() -> decode.Decoder(#(String, String)) {
  use sql <- decode.field("sql", decode.string)
  use project_path <- decode.field("project_path", decode.string)
  decode.success(#(sql, project_path))
}

pub fn handle_migrate(req: Request) -> Response {
  use body <- wisp.require_string_body(req)
  case json.parse(body, migrate_decoder()) {
    Error(_) -> wisp.bad_request("Expected {\"sql\":\"...\",\"project_path\":\"...\"}")
    Ok(#(sql, project_path)) -> {
      let dir = project_path <> "/migrations"
      let filename = "migration_" <> int.to_string(now_ms()) <> ".sql"
      let full_path = dir <> "/" <> filename

      let r =
        result.try(
          simplifile.create_directory_all(dir) |> result.replace_error(Nil),
          fn(_) {
            simplifile.write(to: full_path, contents: sql)
            |> result.replace_error(Nil)
          },
        )

      case r {
        Ok(_) ->
          wisp.json_response(
            json.to_string(
              json.object([
                #("ok", json.bool(True)),
                #("file", json.string(full_path)),
                #(
                  "hint",
                  json.string("psql $DATABASE_URL -f " <> full_path),
                ),
              ]),
            ),
            200,
          )
        Error(_) ->
          wisp.json_response(
            json.to_string(
              json.object([
                #("ok", json.bool(False)),
                #("error", json.string("Failed to write migration file")),
              ]),
            ),
            500,
          )
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Code generation
// ---------------------------------------------------------------------------

fn gen_gleam_types(nodes: List(ApiNode)) -> String {
  nodes |> list.map(node_to_gleam) |> string.join("\n\n")
}

fn node_to_gleam(node: ApiNode) -> String {
  case node.kind {
    "Object" | "InputObject" -> {
      let fields =
        node.fields
        |> list.map(fn(f) { "  " <> f.name <> ": " <> gleam_type(f) })
        |> string.join(",\n")
      "pub type " <> node.name <> " {\n  " <> node.name <> "(\n" <> fields <> "\n  )\n}"
    }
    "Enum" -> {
      let vs = node.fields |> list.map(fn(f) { "  " <> f.name }) |> string.join("\n")
      "pub type " <> node.name <> " {\n" <> vs <> "\n}"
    }
    "Union" -> {
      let vs =
        node.fields
        |> list.map(fn(f) { "  " <> f.name <> "(" <> f.field_type <> ")" })
        |> string.join("\n")
      "pub type " <> node.name <> " {\n" <> vs <> "\n}"
    }
    _ -> "// unknown: " <> node.name
  }
}

fn gleam_type(f: ApiField) -> String {
  let base = case f.field_type {
    "String" | "ID" -> "String"
    "Int" -> "Int"
    "Float" -> "Float"
    "Boolean" -> "Bool"
    t -> t
  }
  case f.non_null {
    True -> base
    False -> "option.Option(" <> base <> ")"
  }
}

fn gen_sdl(nodes: List(ApiNode)) -> String {
  nodes |> list.map(node_to_sdl) |> string.join("\n\n")
}

fn node_to_sdl(node: ApiNode) -> String {
  case node.kind {
    "Object" -> {
      let fields =
        node.fields
        |> list.map(fn(f) { "  " <> f.name <> ": " <> sdl_type(f) })
        |> string.join("\n")
      "type " <> node.name <> " {\n" <> fields <> "\n}"
    }
    "InputObject" -> {
      let fields =
        node.fields
        |> list.map(fn(f) { "  " <> f.name <> ": " <> sdl_type(f) })
        |> string.join("\n")
      "input " <> node.name <> " {\n" <> fields <> "\n}"
    }
    "Enum" -> {
      let vs =
        node.fields
        |> list.map(fn(f) { "  " <> string.uppercase(f.name) })
        |> string.join("\n")
      "enum " <> node.name <> " {\n" <> vs <> "\n}"
    }
    "Union" -> {
      let members = node.fields |> list.map(fn(f) { f.field_type }) |> string.join(" | ")
      "union " <> node.name <> " = " <> members
    }
    _ -> ""
  }
}

fn sdl_type(f: ApiField) -> String {
  let base = case f.field_type {
    "ID" -> "ID"
    "String" -> "String"
    "Int" -> "Int"
    "Float" -> "Float"
    "Boolean" -> "Boolean"
    t -> t
  }
  case f.non_null { True -> base <> "!" False -> base }
}

fn gen_sql(nodes: List(ApiNode)) -> String {
  let obj = list.filter(nodes, fn(n) { n.kind == "Object" })
  let names = list.map(obj, fn(n) { n.name })
  let tables = obj |> list.map(fn(n) { node_to_sql(n, names) }) |> string.join("\n\n")
  "-- Generated by mochi studio\n\nBEGIN;\n\n" <> tables <> "\n\nCOMMIT;\n"
}

fn node_to_sql(node: ApiNode, obj_names: List(String)) -> String {
  let tbl = to_snake_case(node.name) <> "s"
  let has_id = list.any(node.fields, fn(f) { string.lowercase(f.name) == "id" })
  let id_col = case has_id { True -> [] False -> ["  id UUID PRIMARY KEY DEFAULT gen_random_uuid()"] }
  let field_cols =
    node.fields
    |> list.filter(fn(f) { string.lowercase(f.name) != "id" })
    |> list.map(fn(f) { "  " <> to_snake_case(f.name) <> " " <> sql_col_type(f, obj_names) })
  let ts = ["  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()"]
  let cols = list.flatten([id_col, field_cols, ts]) |> string.join(",\n")
  "CREATE TABLE IF NOT EXISTS " <> tbl <> " (\n" <> cols <> "\n);"
}

fn sql_col_type(f: ApiField, obj_names: List(String)) -> String {
  let t = case f.field_type {
    "String" -> "TEXT"
    "ID" -> "UUID"
    "Int" -> "INTEGER"
    "Float" -> "DOUBLE PRECISION"
    "Boolean" -> "BOOLEAN"
    other ->
      case list.contains(obj_names, other) {
        True -> "UUID REFERENCES " <> to_snake_case(other) <> "s(id)"
        False -> "TEXT"
      }
  }
  case f.non_null { True -> t <> " NOT NULL" False -> t }
}

fn gen_mochi_schema(nodes: List(ApiNode)) -> String {
  let header = "// Generated by mochi studio\nimport gleam/option\nimport mochi/query\nimport mochi/types\n\n"
  let type_defs =
    list.filter(nodes, fn(n) { n.kind == "Object" || n.kind == "InputObject" })
    |> list.map(node_to_gleam)
    |> string.join("\n\n")
  let builders =
    list.filter(nodes, fn(n) { n.kind == "Object" })
    |> list.map(node_to_builder)
    |> string.join("\n\n")
  header <> type_defs <> "\n\n" <> builders
}

fn node_to_builder(node: ApiNode) -> String {
  let fn_name = to_snake_case(node.name)
  let field_fns =
    node.fields
    |> list.map(fn(f) {
      let b = case f.field_type {
        "ID" -> "types.id"
        "String" -> "types.string"
        "Int" -> "types.int"
        "Float" -> "types.float"
        "Boolean" -> "types.bool"
        _ -> "types.string"
      }
      "  |> " <> b <> "(\"" <> f.name <> "\", fn(x: " <> node.name <> ") { x." <> f.name <> " })"
    })
    |> string.join("\n")
  "pub fn " <> fn_name <> "_type() {\n  types.object(\"" <> node.name <> "\")\n" <> field_fns <> "\n  |> types.build(fn(_) { Error(\"not implemented\") })\n}"
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn to_snake_case(s: String) -> String {
  case string.to_graphemes(s) {
    [] -> ""
    [h, ..rest] ->
      list.fold(rest, string.lowercase(h), fn(acc, ch) {
        case ch == string.lowercase(ch) {
          True -> acc <> ch
          False -> acc <> "_" <> string.lowercase(ch)
        }
      })
  }
}

fn dirname(path: String) -> String {
  let parts = string.split(path, "/")
  case list.length(parts) > 1 {
    True ->
      parts
      |> list.reverse
      |> list.drop(1)
      |> list.reverse
      |> string.join("/")
    False -> "."
  }
}

@external(erlang, "erlang", "system_time")
fn now_ms() -> Int {
  0
}
