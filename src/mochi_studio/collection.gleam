// mochi_studio/collection.gleam
// Saved query/mutation collections (like Insomnia collections)

pub type Collection {
  Collection(id: String, name: String, items: List(CollectionItem))
}

pub type CollectionItem {
  CollectionItem(
    id: String,
    name: String,
    query: String,
    variables: String,
    operation: OperationType,
  )
}

pub type OperationType {
  Query
  Mutation
  Subscription
}
