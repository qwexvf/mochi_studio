// mochi_studio/server.gleam
// Erlang-target HTTP server for mochi studio
// Start with: gleam run -m mochi_studio/server --target erlang

@target(erlang)
import gleam/erlang/process
@target(erlang)
import gleam/json
@target(erlang)
import mist
@target(erlang)
import mochi_studio/codegen_api
@target(erlang)
import wisp
@target(erlang)
import wisp/wisp_mist

@target(erlang)
pub fn main() {
  wisp.configure_logger()
  let secret = wisp.random_string(64)

  let assert Ok(_) =
    handle_request
    |> wisp_mist.handler(secret)
    |> mist.new
    |> mist.port(4000)
    |> mist.start
  process.sleep_forever()
}

@target(erlang)
fn handle_request(req: wisp.Request) -> wisp.Response {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  let resp = case wisp.path_segments(req) {
    ["api", "generate"] -> codegen_api.handle_generate(req)
    ["api", "write"] -> codegen_api.handle_write(req)
    ["api", "migrate"] -> codegen_api.handle_migrate(req)
    ["api", "status"] -> handle_status()
    _ -> wisp.not_found()
  }
  // CORS for the Lustre dev server on port 1234
  resp
  |> wisp.set_header("access-control-allow-origin", "*")
  |> wisp.set_header("access-control-allow-methods", "GET, POST, OPTIONS")
  |> wisp.set_header("access-control-allow-headers", "content-type")
}

@target(erlang)
fn handle_status() -> wisp.Response {
  let body =
    json.object([
      #("status", json.string("ok")),
      #("version", json.string("0.1.0")),
    ])
    |> json.to_string
  wisp.json_response(body, 200)
}
