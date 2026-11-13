pub fn choose(
  input : Option[Int32],
  fallback : Int32,
) -> Int32 {
  let selected = match input {
    Some(value) =>
      consume(
        value,
        fallback,
      )
    None => fallback
  }
  selected
    |> adjust
    |> adjust
}

fn chain(items : Array[Int32]) {
  items
    .map(fn(item) { item + 1 })
    .filter(fn(item) { item > 0 })
}
