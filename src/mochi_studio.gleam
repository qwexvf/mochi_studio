//// GraphQL Studio for mochi.
////
//// A browser-based GraphQL IDE with:
//// - Interactive query/mutation playground with syntax highlighting
//// - Saved collections — organize queries and mutations like Insomnia
//// - URL sharing — encode query + variables into a shareable link
//// - Schema explorer — browse types, fields, and docs via introspection
//// - Visual schema builder — compose GraphQL types and generate Gleam code
////
//// ## Usage
////
//// Embed the studio in your Gleam/Wisp app:
////
//// ```gleam
//// import mochi_studio
////
//// // Serve the studio HTML at a route
//// let html = mochi_studio.html(endpoint: "/graphql")
////
//// // Or mount as a full Lustre SPA
//// mochi_studio.start(endpoint: "/graphql")
//// ```

import lustre
import mochi_studio/app

pub fn start(endpoint endpoint: String) {
  let assert Ok(_) =
    lustre.application(app.init(endpoint), app.update, app.view)
    |> lustre.start("#mochi-studio", Nil)
  Nil
}
