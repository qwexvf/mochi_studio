import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/string
import mochi_studio/codegen_api
import simplifile
import wisp/simulate

const nodes_body = "{\"nodes\": [
  {\"id\": \"1\", \"kind\": \"Object\", \"name\": \"User\", \"fields\": [
    {\"name\": \"id\", \"field_type\": \"ID\", \"non_null\": true}
  ]},
  {\"id\": \"2\", \"kind\": \"Enum\", \"name\": \"Role\", \"fields\": [
    {\"name\": \"admin\", \"field_type\": \"\", \"non_null\": false}
  ]}
]}"

fn post(path: String, body: String) {
  simulate.request(http.Post, path)
  |> simulate.string_body(body)
  |> simulate.header("content-type", "application/json")
}

fn string_field(body: String, name: String) -> String {
  let assert Ok(value) = json.parse(body, decode.at([name], decode.string))
  value
}

// Each test gets its own directory under build/ so runs don't see each
// other's files.
fn fresh_dir(name: String) -> String {
  let dir = "build/codegen_api_test/" <> name
  let _ = simplifile.delete_all([dir])
  dir
}

pub fn generate_returns_all_outputs_test() {
  let resp = codegen_api.handle_generate(post("/api/generate", nodes_body))
  assert resp.status == 200
  let body = simulate.read_body(resp)
  assert string.contains(string_field(body, "sdl"), "type User {\n  id: ID!\n}")
  assert string.contains(string_field(body, "gleam_types"), "pub type User {")
  assert string.contains(
    string_field(body, "sql"),
    "CREATE TABLE IF NOT EXISTS users (",
  )
  assert string.contains(string_field(body, "mochi_schema"), "pub fn user_type")
}

pub fn generate_uppercases_enum_values_in_sdl_test() {
  let resp = codegen_api.handle_generate(post("/api/generate", nodes_body))
  let sdl = string_field(simulate.read_body(resp), "sdl")
  assert string.contains(sdl, "enum Role {\n  ADMIN\n}")
}

pub fn generate_rejects_body_without_nodes_test() {
  let resp = codegen_api.handle_generate(post("/api/generate", "{\"x\": 1}"))
  assert resp.status == 400
}

pub fn write_creates_nested_files_test() {
  let dir = fresh_dir("write")
  let body =
    json.object([
      #("project_path", json.string(dir)),
      #(
        "files",
        json.preprocessed_array([
          json.object([
            #("path", json.string("src/generated/schema.gleam")),
            #("content", json.string("pub type User")),
          ]),
        ]),
      ),
    ])
    |> json.to_string
  let resp = codegen_api.handle_write(post("/api/write", body))
  assert resp.status == 200
  let assert Ok(written) =
    json.parse(
      simulate.read_body(resp),
      decode.at(["written"], decode.list(decode.string)),
    )
  assert written == ["src/generated/schema.gleam"]
  assert simplifile.read(dir <> "/src/generated/schema.gleam")
    == Ok("pub type User")
}

pub fn migrate_writes_sql_under_migrations_test() {
  let dir = fresh_dir("migrate")
  let sql = "CREATE TABLE users (id UUID);"
  let body =
    json.object([
      #("sql", json.string(sql)),
      #("project_path", json.string(dir)),
    ])
    |> json.to_string
  let resp = codegen_api.handle_migrate(post("/api/migrate", body))
  assert resp.status == 200
  let file = string_field(simulate.read_body(resp), "file")
  assert string.starts_with(file, dir <> "/migrations/migration_")
  assert string.ends_with(file, ".sql")
  assert simplifile.read(file) == Ok(sql)
}

pub fn migrate_rejects_body_without_project_path_test() {
  let resp =
    codegen_api.handle_migrate(post("/api/migrate", "{\"sql\": \"SELECT 1\"}"))
  assert resp.status == 400
}
