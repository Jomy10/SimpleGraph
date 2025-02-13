<div align="center">
  <h1>SimpleGraph</h1>
  ❰
  <a href="https://swiftpackageindex.com/Jomy10/SimpleGraph/documentation/simplegraph">documentation</a>
  ❱
</div><br/>
<div align="center">
  <a href="https://swiftpackageindex.com/Jomy10/SimpleGraph"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FJomy10%2FSimpleGraph%2Fbadge%3Ftype%3Dswift-versions"></img></a>
  <a href="https://swiftpackageindex.com/Jomy10/SimpleGraph"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FJomy10%2FSimpleGraph%2Fbadge%3Ftype%3Dplatforms"></img></a>
</div><br/>

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
