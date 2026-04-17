// mochi_studio/sidebar.gleam

import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import mochi_studio/collection.{
  type Collection, type CollectionItem, Collection, CollectionItem, Mutation,
  Query, Subscription,
}

pub type Model {
  Model(collections: List(Collection), expanded: List(String), search: String)
}

pub type Msg {
  ToggleCategory(String)
  SearchChanged(String)
  SelectItem(CollectionItem)
  NewCollection
  NewItem(collection_id: String, kind: collection.OperationType)
  DeleteItem(collection_id: String, item_id: String)
}

pub fn init() -> Model {
  Model(
    collections: [demo_collection()],
    expanded: ["queries", "mutations"],
    search: "",
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    ToggleCategory(id) -> {
      let expanded = case list.contains(model.expanded, id) {
        True -> list.filter(model.expanded, fn(e) { e != id })
        False -> [id, ..model.expanded]
      }
      Model(..model, expanded: expanded)
    }
    SearchChanged(s) -> Model(..model, search: s)
    _ -> model
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "flex flex-col w-56 bg-gray-900 border-r border-gray-800 shrink-0",
      ),
    ],
    [
      view_search(model),
      html.div(
        [attribute.class("flex-1 overflow-y-auto")],
        list.map(model.collections, fn(col) { view_collection(col, model) }),
      ),
    ],
  )
}

fn view_search(model: Model) -> Element(Msg) {
  html.div([attribute.class("p-2 border-b border-gray-800")], [
    html.input([
      attribute.class(
        "w-full bg-gray-800 rounded px-2 py-1.5 text-xs text-gray-200 placeholder-gray-600 outline-none focus:ring-1 focus:ring-pink-500",
      ),
      attribute.placeholder("Search…"),
      attribute.value(model.search),
      event.on_input(SearchChanged),
    ]),
  ])
}

fn view_collection(col: Collection, model: Model) -> Element(Msg) {
  let queries = list.filter(col.items, fn(i) { i.operation == Query })
  let mutations = list.filter(col.items, fn(i) { i.operation == Mutation })
  let subscriptions =
    list.filter(col.items, fn(i) { i.operation == Subscription })

  html.div([attribute.class("py-1")], [
    html.div(
      [
        attribute.class(
          "px-2 py-1 text-xs font-semibold text-gray-400 uppercase tracking-wider",
        ),
      ],
      [html.text(col.name)],
    ),
    view_category("queries", "Queries", queries, model),
    view_category("mutations", "Mutations", mutations, model),
    view_category("subscriptions", "Subscriptions", subscriptions, model),
  ])
}

fn view_category(
  id: String,
  label: String,
  items: List(CollectionItem),
  model: Model,
) -> Element(Msg) {
  let is_open = list.contains(model.expanded, id)
  let filtered = case model.search {
    "" -> items
    s -> list.filter(items, fn(i) { string_contains(i.name, s) })
  }
  let count = list.length(filtered)

  html.div([], [
    html.button(
      [
        attribute.class(
          "flex items-center gap-1 w-full px-2 py-1 text-xs text-gray-400 hover:text-gray-200 hover:bg-gray-800 transition-colors",
        ),
        event.on_click(ToggleCategory(id)),
      ],
      [
        html.span([], [
          html.text(case is_open {
            True -> "▾"
            False -> "▸"
          }),
        ]),
        html.span([attribute.class("flex-1 text-left")], [html.text(label)]),
        html.span([attribute.class("text-gray-600 text-xs")], [
          html.text(case count {
            0 -> ""
            _ -> int_to_string(count)
          }),
        ]),
      ],
    ),
    case is_open {
      False -> html.div([], [])
      True ->
        html.div([], case filtered {
          [] -> [
            html.div(
              [attribute.class("px-6 py-1 text-xs text-gray-700 italic")],
              [html.text("empty")],
            ),
          ]
          _ -> list.map(filtered, view_item)
        })
    },
  ])
}

fn view_item(item: CollectionItem) -> Element(Msg) {
  html.button(
    [
      attribute.class(
        "flex items-center gap-2 w-full px-6 py-1 text-xs text-gray-400 hover:text-gray-100 hover:bg-gray-800 text-left transition-colors group",
      ),
      event.on_click(SelectItem(item)),
    ],
    [
      html.span([attribute.class("flex-1 truncate")], [html.text(item.name)]),
      html.span(
        [
          attribute.class(
            "text-pink-500 opacity-0 group-hover:opacity-100 text-xs",
          ),
        ],
        [html.text(operation_badge(item.operation))],
      ),
    ],
  )
}

fn operation_badge(op: collection.OperationType) -> String {
  case op {
    Query -> "Q"
    Mutation -> "M"
    Subscription -> "S"
  }
}

fn demo_collection() -> Collection {
  Collection(id: "default", name: "My Collection", items: [
    CollectionItem(
      id: "1",
      name: "Get users",
      query: "{ users { id name } }",
      variables: "{}",
      operation: Query,
    ),
    CollectionItem(
      id: "2",
      name: "Get user by ID",
      query: "query GetUser($id: ID!) {\n  user(id: $id) {\n    id\n    name\n  }\n}",
      variables: "{\"id\": \"1\"}",
      operation: Query,
    ),
    CollectionItem(
      id: "3",
      name: "Create user",
      query: "mutation CreateUser($name: String!) {\n  createUser(name: $name) {\n    id\n    name\n  }\n}",
      variables: "{\"name\": \"Alice\"}",
      operation: Mutation,
    ),
  ])
}

@external(javascript, "./sidebar_ffi.mjs", "stringContains")
fn string_contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}

@external(javascript, "./sidebar_ffi.mjs", "intToString")
fn int_to_string(n: Int) -> String {
  int.to_string(n)
}
