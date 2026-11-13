/// A point in two dimensions.
#derive(Debug, Eq)
pub(all) struct Point {
  x : Int32
  y : UInt32
}

struct UserId(Int32)

suberror ParseError {
  Empty
  InvalidChar(Char)
}

extenum Event {
  Start
}

extenum Event += {
  Stop
}

extenum @events.Event += {
  Remote
}

trait Printable {
  print(Self) -> String
}

#deprecated("example")
pub async fn[T] Point::convert(self : Point, value : T) -> Int32 {
  let items = [for i in 0..<10 if i > 0 => i]
  let number = 1.5
  let byte = b'a'
  let bytes = b"hello"
  let pattern = re"[a-z]+"
  let message = "point: \{self.x}"
  let raw =
    #|literal \{text}
    #|  indented content
  let interpolated =
    $|point: \{self.x + 1}
    $|next
  /* A block comment. */
  guard items.length() > 0 else { return 0 }
  match items.first() {
    Some(n) => {
      println(n)
      n
    }
    None => 0
  }
}

fn pipes(value : Int32) -> Int32 {
  let first = value |> transform
  let second = transform <| first
  @example.consume(second)
}

impl Printable for Point with print(self) {
  "Point"
}

test "point" {
  let point = Point::{ x: 1, y: 2 }
  point.print()
}

test {
  ()
}

const LIMIT : Int32 = 42
