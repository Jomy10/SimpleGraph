import Foundation
import Testing
@testable import SimpleGraph

#if os(macOS)
import SQLite3
#else
import CSQLite
#endif

struct TestError: Error {
  let message: String

  init(_ message: String) {
    self.message = message
  }
}

func sqlexec(db: SQLite, _ query: String) throws {
  if sqlite3_exec(db, query, nil, nil, nil) != SQLITE_OK {
    throw TestError(String(cString: sqlite3_errmsg(db)))
    }
}

func sqlprep(db: SQLite, _ query: String) throws -> SQLiteStatement {
  var stmtHandle: OpaquePointer? = nil
  if sqlite3_prepare_v2(db, query, -1, &stmtHandle, nil) != SQLITE_OK {
    throw SimpleGraphError.queryExecutionError(message: String(cString: sqlite3_errmsg(db)), query: query)
  }
  return SQLiteStatement(handle: stmtHandle!)
}

struct MyNode: Node, Equatable {
  var uid = UUID()
  let data: String

  var id: String {
    get { self.uid.uuidString }
    set { self.uid = UUID(uuidString: newValue)! }
  }

  init(data: String) {
    self.data = data
  }

  static func fromJSON(_ json: String) throws -> MyNode {
    return try JSONDecoder().decode(MyNode.self, from: json.data(using: .utf8)!)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case data
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.uid = UUID(uuidString: try container.decode(String.self, forKey: .id))!
    self.data = try container.decode(String.self, forKey: .data)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.id, forKey: .id)
    try container.encode(self.data, forKey: .data)
  }
}

func dbFile(_ testName: String) throws -> URL {
  let dbFile = FileManager.default.temporaryDirectory.appending(path: testName)
  if FileManager.default.fileExists(atPath: dbFile.path) {
    try FileManager.default.removeItem(at: dbFile)
  }
  print("[\(testName)] \(dbFile.path)")
  return dbFile
}

@Test func insertNode() async throws {
  let dbFile = try dbFile("insertNode")
  let db: SimpleGraph = try SimpleGraph(at: dbFile)
  db.trace({ message in print("[insertNode] " + message) })

  let node = MyNode(data: "Hello world")
  try db.insertNode(node)

  let stmt = try sqlprep(db: db.db, "select id, body from nodes")
  var c = 0
  while try stmt.step() {
    c += 1
    let id = String(cString: UnsafeRawPointer(sqlite3_column_text(stmt.handle, 0)!).assumingMemoryBound(to: CChar.self), encoding: .utf8)!
    let data: String? = if let dataCStr = UnsafeRawPointer(sqlite3_column_text(stmt.handle, 1))?.assumingMemoryBound(to: CChar.self) {
      String(cString: dataCStr, encoding: .utf8)!
    } else {
      nil
    }
    #expect(id == String(describing: node.id))
    let expectedNode = try MyNode.fromJSON(data!)
    #expect(node == expectedNode)
  }
  #expect(c == 1)
}

@Test func deleteNode() async throws {
  let dbFile = try dbFile("deleteNode")
  let db: SimpleGraph = try SimpleGraph(at: dbFile)
  db.trace({ message in print("[deleteNode] " + message) })

  let node = MyNode(data: "Hello world")
  try db.insertNode(node)

  let stmt = try sqlprep(db: db.db, "select id, body from nodes")
  var c = 0
  while try stmt.step() {
    c += 1
    let id = String(cString: UnsafeRawPointer(sqlite3_column_text(stmt.handle, 0)!).assumingMemoryBound(to: CChar.self), encoding: .utf8)!
    let data: String? = if let dataCStr = UnsafeRawPointer(sqlite3_column_text(stmt.handle, 1))?.assumingMemoryBound(to: CChar.self) {
      String(cString: dataCStr, encoding: .utf8)!
    } else {
      nil
    }
    #expect(id == String(describing: node.id))
    let expectedNode = try MyNode.fromJSON(data!)
    #expect(node == expectedNode)
  }
  #expect(c == 1)

  try db.deleteNode(id: node.id)
  let stmt2 = try sqlprep(db: db.db, "select id, body from nodes")
  c = 0
  while try stmt2.step() {
    c += 1
  }
  #expect(c == 0)
}

@Test func traverse() async throws {
  let dbFile = try dbFile("traverse")
  let db: SimpleGraph = try SimpleGraph(at: dbFile)
  db.trace({ message in print("[traverse] " + message) })

  let a = MyNode(data: "Hello")
  let b = MyNode(data: "my")
  let c = MyNode(data: "friend")

  try db.insertNode(a)
  try db.insertNode(b)
  try db.insertNode(c)
  try db.insertEdge(source: a, target: b)
  try db.insertEdge(source: b, target: c, properties: "some data")

  print("[traverse]", a.id, b.id, c.id)

  let ids: [String] = try db.traverse(fromNode: b, inbound: false, outbound: true)
  print(ids)
  #expect(ids.count == 2)
  let cid = UUID(uuidString: ids[1])!
  #expect(cid == c.uid)

  let ids2: [String] = try db.traverse(fromNode: b, inbound: true, outbound: false)
  print(ids2)
  #expect(ids2.count == 2)
  let aid = UUID(uuidString: ids2[1])!
  #expect(aid == a.uid)

  let allIds: [String] = try db.traverse(fromNode: b, inbound: true, outbound: true)
  #expect(allIds.count == 3)
}

@Test func traverseWithBodies() async throws {
  let dbFile = try dbFile("traverseWithBodies")
  let db: SimpleGraph = try SimpleGraph(at: dbFile)
  db.trace({ message in print("[traverseWithBodies] " + message) })

  let a = MyNode(data: "Hello")
  let b = MyNode(data: "my")
  let c = MyNode(data: "friend")

  try db.insertNode(a)
  try db.insertNode(b)
  try db.insertNode(c)
  try db.insertEdge(source: a, target: b)
  try db.insertEdge(source: b, target: c, properties: "some data")

  print("[traverseWithBodies]", a.id, b.id, c.id)

  let decoder = SimpleGraph.decoder
  let ids: [(String, String, Data?)] = try db.traverse(fromNode: b, inbound: false, outbound: true)
  #expect(ids.count == 3)

  let cid = UUID(uuidString: ids[1].0)!
  #expect(cid == c.uid)
  let rel = ids[1].1
  #expect(rel == "->")
  let body: String = try decoder.decode(String.self, from: ids[1].2!)
  #expect(body == "some data")

  let cid2 = UUID(uuidString: ids[2].0)!
  #expect(cid2 == c.uid)
  let rel2 = ids[2].1
  #expect(rel2 == "()")
  let body2 = try decoder.decode(MyNode.self, from: ids[2].2!)
  #expect(body2 == c)
}
