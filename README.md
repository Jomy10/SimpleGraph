# SimpleGraph

Swift implementation of [simple-graph](https://github.com/dpapathanasiou/simple-graph). A graph database in SQLite.

## Usage

```swift
import SimpleGraph

struct MyNode: Node {
  var id = UUID()
  let data: String
}

let db = try SimpleGraph(at: URL(filePath: "test.db"))

let a = MyNode(data: "Hello")
let b = MyNode(data: "my")
let c = MyNode(data: "friend")

try db.insertNode(a)
try db.insertNode(b)
try db.insertNode(c)
try db.insertEdge(source: a, target: b)
try db.insertEdge(source: b, target: c, properties: "some data")

// Traverse from b up, to c
let ids: [String] = try db.traverse(fromNode: b, inbound: false, outbound: true)
#expect(UUID(uuidString: ids[0])! == b.id)
#expect(UUID(uuidString: ids[1])! == c.id)
```

## TODO

- `searchNode`
- `search(where: )`
- `db.insert(a <- b)` and `db.insert(b -> a)` (= `db.insert(source: b, target: a)`)
- full test coverage

Pull request are always welcome!

# License

(c) Jonas Everaert, licensed under the [MIT license](LICENSE).
