import Foundation
import Jinja

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import SQLite3
#else
import CSQLite3
#endif

public enum SimpleGraphError: Swift.Error, @unchecked Sendable {
  case createDBError(String)
  case queryExecutionError(message: String, query: String)
  case bindingError(String)
  case encodingError(any Swift.Error)
  case decodingError(any Swift.Error)
  case noNode(withId: any Codable)
  case templateError(any Error)
}

fileprivate struct Queries {
  static let schema = String(bytes: PackageResources.schema_sql, encoding: .utf8)!

  static let insertNode = String(bytes: PackageResources.insert_node_sql, encoding: .utf8)!
  static let deleteNode = String(bytes: PackageResources.delete_node_sql, encoding: .utf8)!

  static let insertEdge = String(bytes: PackageResources.insert_edge_sql, encoding: .utf8)!
  static let deleteEdge = String(bytes: PackageResources.delete_edge_sql, encoding: .utf8)!
  static let deleteEdges = String(bytes: PackageResources.delete_edges_sql, encoding: .utf8)!
  static let deleteIncomingEdges = String(bytes: PackageResources.delete_incoming_edges_sql, encoding: .utf8)!
  static let deleteOutgoingEdges = String(bytes: PackageResources.delete_outgoing_edges_sql, encoding: .utf8)!

  static let searchEdges = String(bytes: PackageResources.search_edges_sql, encoding: .utf8)!
  static let searchEdgesInbound = String(bytes: PackageResources.search_edges_inbound_sql, encoding: .utf8)!
  static let searchEdgesOutbound = String(bytes: PackageResources.search_edges_outbound_sql, encoding: .utf8)!

  static let searchNodeTemplate = String(bytes: PackageResources.search_node_template, encoding: .utf8)!
  static let searchWhereTemplate = String(bytes: PackageResources.search_where_template, encoding: .utf8)!

  static let updateEdge = String(bytes: PackageResources.update_edge_sql, encoding: .utf8)!
  static let updateNode = String(bytes: PackageResources.update_node_sql, encoding: .utf8)!

  static let traverseTemplate = String(bytes: PackageResources.traverse_template, encoding: .utf8)!.replacing("UNION", with: " UNION")
}

public final class SimpleGraph: @unchecked Sendable {
  let db: SQLite
  public static let decoder = JSONDecoder()
  private static let encoder = JSONEncoder()

  /// - `dbFile`: the database file to open
  /// - `sqliteFlags`: the default is SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX.
  ///   This means the database file will be opened for reading and writing, will be created if it
  ///   doesn't exsit and the database can be accessed from multiple threads.
  public init(at dbFile: URL, sqliteFlags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX) throws(SimpleGraphError) {
    var db: OpaquePointer? = nil
    if sqlite3_open_v2(dbFile.path, &db, sqliteFlags, nil) != SQLITE_OK {
      throw .createDBError(String(cString: sqlite3_errmsg(db)))
    }
    self.db = db!

    try self.execute(Queries.schema)
  }

  public convenience init(atPath dbFile: String) throws(SimpleGraphError) {
    try self.init(at: URL(fileURLWithPath: dbFile))
  }

  private typealias TraceFn = @convention(block) (UnsafeRawPointer) -> Void
  private var traceFn: TraceFn? = nil

  public func trace(_ callback: @escaping (String) -> Void, traceRow: Bool = false) {
    var traceMask: UInt32 = UInt32(SQLITE_TRACE_STMT)
    if traceRow {
      traceMask |= UInt32(SQLITE_TRACE_ROW)
    }
    self.traceFn = { (pointer: UnsafeRawPointer) in
      let strPtr = pointer.assumingMemoryBound(to: CChar.self)
      let message = String(cString: strPtr, encoding: .utf8)
      if let message {
        callback(message)
      }
    }
    if #available(iOS 10.0, macOS 10.12, tvOS 10.0, watchOS 3.0, *) {
      sqlite3_trace_v2(
        self.db,
        traceMask,
        { (traceReason: UInt32, ctx: UnsafeMutableRawPointer?, pointer: UnsafeMutableRawPointer?, _: UnsafeMutableRawPointer?) -> Int32 in
          if let pointer,
             let expandedSQL = sqlite3_expanded_sql(OpaquePointer(pointer))
          {
            unsafeBitCast(ctx, to: TraceFn.self)(expandedSQL)
            sqlite3_free(expandedSQL)
          }
          return 0
        },
        unsafeBitCast(self.traceFn, to: UnsafeMutableRawPointer.self)
      )
    } else {
      sqlite3_trace(
        self.db,
        { (context: UnsafeMutableRawPointer?, query: UnsafePointer<Int8>?) in
          if let context,
             let query
          {
            unsafeBitCast(context, to: TraceFn.self)(query)
          }
        },
        unsafeBitCast(self.traceFn, to: UnsafeMutableRawPointer.self)
      )
    }
  }

  static func encode(_ v: some Encodable) throws(SimpleGraphError) -> Data {
    var data: Data
    do {
      data = try Self.encoder.encode(v)
      if data.count == 0 {
        data = "{}".data(using: .utf8)!
      }
    } catch {
      throw .encodingError(error)
    }
    return data
  }

  static func encodeId(_ id: some Encodable) throws(SimpleGraphError) -> Data {
    var data = try Self.encode(id)
    if data.first == Character("\"").asciiValue {
      data = data.dropFirst().dropLast()
    }
    return data
  }

  static func decode<T: Decodable>(_ data: Data) throws(SimpleGraphError) -> T {
    do {
      return try Self.decoder.decode(T.self, from: data)
    } catch {
      throw .decodingError(error)
    }
  }

  public func insertNode(_ node: some Node) throws(SimpleGraphError) {
    let data = try Self.encode(node)
    var stmt = try self.prepare(Queries.insertNode)
    try stmt.bind(utf8StringData: data)
    try stmt.step()
  }

  public func insertNodeIfNotExists(_ node: some Node) throws(SimpleGraphError) {
    if try self.nodeExists(id: node.id) { return }
    try self.insertNode(node)
  }

  public func nodeExists(id: some Codable) throws(SimpleGraphError) -> Bool {
    var stmt = try self.prepare("select id from nodes where id = ?")
    try stmt.bind(utf8StringData: try Self.encodeId(id))
    return try stmt.step()
  }

  public func getNode<ResultNode: Node>(id: some Codable, ofType: ResultNode.Type = ResultNode.self) throws(SimpleGraphError) -> ResultNode? {
    let nodeId = try Self.encodeId(id)
    var stmt = try self.prepare("select body from nodes where id = ?")
    try stmt.bind(utf8StringData: nodeId)
    if try stmt.step() {
      if let body = stmt.column(0) {
        return try Self.decode(body.data(using: .utf8)!)
      } else {
        return nil
      }
    } else {
      return nil
    }
  }

  public func deleteNode(_ node: some Node) throws(SimpleGraphError) {
    try self.deleteNode(id: node.id)
  }

  public func deleteNode<ID: Codable>(id: ID) throws(SimpleGraphError) {
    //let idString = String(describing: id)
    // Delete edges
    try self.deleteEdges(ofNodeId: id)

    // Delete node
    var stmt = try self.prepare(Queries.deleteNode)
    try stmt.bind(utf8StringData: try Self.encodeId(id))
    try stmt.step()
  }

  public func insertEdge<Source: Node, Target: Node, Properties: Codable>(_ edge: Edge<Source, Target, Properties>) throws(SimpleGraphError) {
    try self.insertEdge(sourceId: edge.sourceId, targetId: edge.targetId, properties: edge.properties)
  }

  public func insertEdge(source: some Node, target: some Node, properties: some Codable) throws(SimpleGraphError) {
    try self.insertEdge(sourceId: source.id, targetId: target.id, properties: properties)
  }

  public func insertEdge(source: some Node, target: some Node) throws(SimpleGraphError) {
    try self.insertEdge(sourceId: source.id, targetId: target.id)
  }

  public func insertEdgeIfNotExists(source: some Node, target: some Node) throws(SimpleGraphError) {
    if try self.edgeExists(source: source, target: target) { return }
    try self.insertEdge(source: source, target: target)
  }

  public func insertEdge(sourceId: some Codable, targetId: some Codable, properties: some Codable) throws(SimpleGraphError) {
    var stmt = try self.prepare(Queries.insertEdge)
    try stmt.bind(utf8StringData: try Self.encodeId(sourceId))
    try stmt.bind(utf8StringData: try Self.encodeId(targetId))
    let data = try Self.encode(properties)
    try stmt.bind(utf8StringData: data)
    try stmt.step()
  }

  public func insertEdge(sourceId: some Codable, targetId: some Codable) throws(SimpleGraphError) {
    var stmt = try self.prepare(Queries.insertEdge)
    try stmt.bind(utf8StringData: try Self.encodeId(sourceId))
    try stmt.bind(utf8StringData: try Self.encodeId(targetId))
    try stmt.bindNil()
    try stmt.step()
  }

  // TODO: edgeExists with properties

  public func edgeExists(source: some Node, target: some Node) throws(SimpleGraphError) -> Bool {
    return try self.edgeExists(sourceId: source.id, targetId: target.id)
  }

  public func edgeExists(sourceId: some Codable, targetId: some Codable) throws(SimpleGraphError) -> Bool {
    var stmt = try self.prepare("SELECT * FROM edges WHERE source = ? and target = ? and properties = ?")
    try stmt.bind(utf8StringData: try Self.encodeId(sourceId))
    try stmt.bind(utf8StringData: try Self.encodeId(targetId))
    try stmt.bindNil()
    return try stmt.step()
  }

  /// Deletes the edge between source and target
  public func deleteEdge<Source: Node, Target: Node, Properties: Codable>(_ edge: Edge<Source, Target, Properties>) throws(SimpleGraphError) {
    try self.deleteEdge(sourceId: edge.sourceId, targetId: edge.targetId)
  }

  /// Deletes the edge between source and target
  public func deleteEdge(source: some Node, target: some Node) throws(SimpleGraphError) {
    try self.deleteEdge(sourceId: source.id, targetId: target.id)
  }

  /// Deletes the edge between source and target
  public func deleteEdge(sourceId: some Codable, targetId: some Codable) throws(SimpleGraphError) {
    var stmt = try self.prepare(Queries.deleteEdge)
    try stmt.bind(utf8StringData: try Self.encodeId(sourceId))
    try stmt.bind(utf8StringData: try Self.encodeId(targetId))
  }

  /// Deletes all edges of the node
  public func deleteEdges(ofNode node: some Node) throws(SimpleGraphError) {
    try self.deleteEdges(ofNodeId: node.id)
  }

  /// Deletes all edges of the node
  public func deleteEdges(ofNodeId id: some Codable) throws(SimpleGraphError) {
    var stmt = try self.prepare(Queries.deleteEdges)
    //let idStr = String(describing: id)
    let idEncoded = try Self.encodeId(id)
    try stmt.bind(utf8StringData: idEncoded)
    try stmt.bind(utf8StringData: idEncoded)
  }

  /// Deletes incoming edges of the target node
  public func deleteEdges(ofTarget target: some Node) throws(SimpleGraphError) {
    try self.deleteEdges(ofTargetId: target.id)
  }

  /// Deletes incoming edges of the target node
  public func deleteEdges(ofTargetId id: some Codable) throws(SimpleGraphError) {
    var stmt = try self.prepare(Queries.deleteIncomingEdges)
    try stmt.bind(utf8StringData: try Self.encodeId(id))
    try stmt.step()
  }

  /// Deletes outgoing edges of the source node
  public func deleteEdges(ofSource source: some Node) throws(SimpleGraphError) {
    try self.deleteEdges(ofSourceId: source.id)
  }

  /// Deletes outgoing edges of the source node
  public func deleteEdges(ofSourceId id: some Codable) throws(SimpleGraphError) {
    var stmt = try self.prepare(Queries.deleteOutgoingEdges)
    try stmt.bind(utf8StringData: try Self.encodeId(id))
    try stmt.step()
  }

  @available(macOS 10.15, *)
  public func searchEdges(ofNode node: some Node) throws(SimpleGraphError) -> AsyncThrowingStream<RawEdge, any Error> {
    return try self.searchEdges(ofNodeId: node.id)
  }

  @available(macOS 10.15, *)
  public func searchEdges(ofNodeId id: some Codable) throws(SimpleGraphError) -> AsyncThrowingStream<RawEdge, any Error> {
    return try self.executeSearchEdges(try self.searchEdgesStmt(nodeId: id, query: Queries.searchEdges))
  }

  public func searchEdges(ofNode node: some Node) throws(SimpleGraphError) -> [RawEdge] {
    return try self.searchEdges(ofNodeId: node.id)
  }

  public func searchEdges(ofNodeId id: some Codable) throws(SimpleGraphError) -> [RawEdge] {
    return try self.executeSearchEdges(try self.searchEdgesStmt(nodeId: id, query: Queries.searchEdges))
  }

  @available(macOS 10.15, *)
  public func searchEdges(ofSource source: some Node) throws(SimpleGraphError) -> AsyncThrowingStream<RawEdge, any Error> {
    return try self.searchEdges(ofSourceId: source.id)
  }

  @available(macOS 10.15, *)
  public func searchEdges(ofSourceId id: some Codable) throws(SimpleGraphError) -> AsyncThrowingStream<RawEdge, any Error> {
    return try self.executeSearchEdges(try self.searchEdgesStmt(nodeId: id, query: Queries.searchEdgesInbound))
  }

  public func searchEdges(ofSource source: some Node) throws(SimpleGraphError) -> [RawEdge] {
    return try self.searchEdges(ofSourceId: source.id)
  }

  public func searchEdges(ofSourceId id: some Codable) throws(SimpleGraphError) -> [RawEdge] {
    return try self.executeSearchEdges(try self.searchEdgesStmt(nodeId: id, query: Queries.searchEdgesInbound))
  }

  @available(macOS 10.15, *)
  public func searchEdges(ofTarget target: some Node) throws(SimpleGraphError) -> AsyncThrowingStream<RawEdge, any Error> {
    return try self.searchEdges(ofTargetId: target.id)
  }

  @available(macOS 10.15, *)
  public func searchEdges(ofTargetId id: some Codable) throws(SimpleGraphError) -> AsyncThrowingStream<RawEdge, any Error> {
    return try self.executeSearchEdges(try self.searchEdgesStmt(nodeId: id, query: Queries.searchEdgesOutbound))
  }

  public func searchEdges(ofTarget target: some Node) throws(SimpleGraphError) -> [RawEdge] {
    return try self.searchEdges(ofTargetId: target.id)
  }

  public func searchEdges(ofTargetId id: some Codable) throws(SimpleGraphError) -> [RawEdge] {
    return try self.executeSearchEdges(try self.searchEdgesStmt(nodeId: id, query: Queries.searchEdgesOutbound))
  }

  private func searchEdgesStmt(nodeId: some Codable, query: String) throws(SimpleGraphError) -> SQLiteStatement {
    var stmt = try self.prepare(query)
    let idEncoded = try Self.encodeId(nodeId)
    try stmt.bind(utf8StringData: idEncoded)
    try stmt.bind(utf8StringData: idEncoded)
    return stmt
  }

  // the async stream only ever throws a `SimpleGraphError` (see: https://github.com/swiftlang/swift/issues/75853)
  @available(macOS 10.15, *)
  private func executeSearchEdges(_ stmt: consuming SQLiteStatement) throws(SimpleGraphError) -> AsyncThrowingStream<RawEdge, any Error> {
    return AsyncThrowingStream { continuation in
      do {
        while try stmt.step() {
          continuation.yield(RawEdge(
            rawSourceId: stmt.column(0)!,
            rawTargetId: stmt.column(1)!,
            properties: stmt.column(2)
          ))
        }
      } catch let error as SimpleGraphError {
        continuation.finish(throwing: error)
      } catch {
        fatalError("unreachable \(error)")
      }
      continuation.finish()
    }
  }

  private func executeSearchEdges(_ stmt: consuming SQLiteStatement) throws(SimpleGraphError) -> [RawEdge] {
    var edges = [RawEdge]()
    while try stmt.step() {
      edges.append(RawEdge(rawSourceId: stmt.column(0)!, rawTargetId: stmt.column(1)!, properties: stmt.column(2)))
    }
    return edges
  }

  // TODO: search-node
  // TODO: search-where
  // TODO: get orphaned nodes

  /// Traverses the the graph, starting from `node`.
  ///
  /// # Parametes
  /// - `node`: the node to start from
  /// - `inbound`: when true, traverses up. e.g. when `node` is the target in an edge, then it will traverse to the source
  /// - `outbound`: when true, traverses down. e.g. when `node` is the source in an edge, then it will traver to the target
  ///
  /// # Returns
  /// The id's of the node as a String
  public func traverse(fromNode node: some Node, inbound: Bool = true, outbound: Bool = true) throws(SimpleGraphError) -> [String] {
    try self.traverse(fromNodeId: node.id, inbound: inbound, outbound: outbound)
  }

  public func traverse(fromNodeId id: some Codable, inbound: Bool = true, outbound: Bool = true) throws(SimpleGraphError) -> [String] {
    var stmt = try self.prepare(try self.traverseQuery(withBodies: false, withInboundEdges: inbound, withOutboundEdges: outbound))
    try stmt.bind(utf8StringData: try Self.encodeId(id))
    var ids = [String]()
    while try stmt.step() {
      let id = stmt.column(0)!
      ids.append(id)
    }
    return ids
  }

  public func traverse(fromNode node: some Node, inbound: Bool = true, outbound: Bool = true) throws(SimpleGraphError) -> AsyncThrowingStream<String, any Error> {
    try self.traverse(fromNodeId: node.id, inbound: inbound, outbound: outbound)
  }

  public func traverse(fromNodeId id: some Codable, inbound: Bool = true, outbound: Bool = true) throws(SimpleGraphError) -> AsyncThrowingStream<String, any Error> {
    var stmt = try self.prepare(try self.traverseQuery(withBodies: false, withInboundEdges: inbound, withOutboundEdges: outbound))
    try stmt.bind(utf8StringData: try Self.encodeId(id))
    return AsyncThrowingStream { continuation in
      do {
        while try stmt.step() {
          let id = stmt.column(0)!
          continuation.yield(id)
        }
      } catch let error {
        continuation.finish(throwing: error)
      }
    }
  }

  /// Traversal with bodies of edges and node data
  public func traverse(fromNode node: some Node, inbound: Bool = true, outbound: Bool = true) throws(SimpleGraphError) -> [(String, String, Data?)] {
    try self.traverse(fromNodeId: node.id, inbound: inbound, outbound: outbound)
  }

  public func traverse(fromNodeId id: some Codable, inbound: Bool = true, outbound: Bool = true) throws(SimpleGraphError) -> [(String, String, Data?)] {
    var stmt = try self.prepare(try self.traverseQuery(withBodies: true, withInboundEdges: inbound, withOutboundEdges: outbound))
    try stmt.bind(utf8StringData: try Self.encodeId(id))
    var res = [(String, String, Data?)]()
    while try stmt.step() {
      let id = stmt.column(0)!
      let rel = stmt.column(1)!
      let body = stmt.column(2)?.data(using: .utf8)
      res.append((id, rel, body))
    }
    return res
  }

  public func traverse(fromNode node: some Node, inbound: Bool = true, outbound: Bool = true) throws(SimpleGraphError) -> AsyncThrowingStream<(String, String, Data?), any Error> {
    try self.traverse(fromNodeId: node.id, inbound: inbound, outbound: outbound)
  }

  public func traverse(fromNodeId id: some Codable, inbound: Bool = true, outbound: Bool = true) throws(SimpleGraphError) -> AsyncThrowingStream<(String, String, Data?), any Error> {
    var stmt = try self.prepare(try self.traverseQuery(withBodies: true, withInboundEdges: inbound, withOutboundEdges: outbound))
    try stmt.bind(utf8StringData: try Self.encodeId(id))
    return AsyncThrowingStream { continuation in
      do {
        while try stmt.step() {
          let id = stmt.column(0)!
          let rel = stmt.column(1)!
          let body = stmt.column(2)?.data(using: .utf8)
          continuation.yield((id, rel, body))
        }
      } catch let error {
        continuation.finish(throwing: error)
      }
    }
  }

  /// Use with caution.
  ///
  /// Can be used for custom SQL Queries
  public func traverseQuery(withBodies: Bool, withInboundEdges: Bool, withOutboundEdges: Bool) throws(SimpleGraphError) -> String {
    do {
      return try Template(Queries.traverseTemplate).render([
        "with_bodies": withBodies,
        "inbound": withInboundEdges,
        "outbound": withOutboundEdges
      ])
    } catch let error {
      throw SimpleGraphError.templateError(error)
    }
  }

  public func updateEdge(withSource source: some Node, withTarget target: some Node, properties: some Codable) throws(SimpleGraphError) {
    try self.updateEdge(withSourceId: source.id, withTargetId: target.id, properties: properties)
  }

  public func updateEdge(withSourceId sourceId: some Codable, withTargetId targetId: some Codable, properties: some Codable) throws(SimpleGraphError) {
    var stmt = try self.prepare(Queries.updateEdge)
    try stmt.bind(utf8StringData: try Self.encode(properties))
    try stmt.bind(utf8StringData: try Self.encodeId(sourceId))
    try stmt.bind(utf8StringData: try Self.encodeId(targetId))
    try stmt.step()
    // TODO: check if at least one row was updated?
  }

  public func updateNode(node: some Node) throws(SimpleGraphError) {
    var stmt = try self.prepare(Queries.updateNode)
    try stmt.bind(utf8StringData: try Self.encode(node))
    try stmt.bind(utf8StringData: try Self.encodeId(node.id))
    //try self.sync { () throws(SimpleGraphError) in
    try stmt.step()
    if sqlite3_changes(self.db) == 0 { // <<- TODO: this probably isn't thread safe, how can we handle this better?
      throw SimpleGraphError.noNode(withId: node.id)
    }
    //}
  }

  /// Use with caution
  ///
  /// Create a new SQLiteStatement from arbitrary SQL
  private func prepare(_ query: String) throws(SimpleGraphError) -> SQLiteStatement {
    //var stmt: SQLiteStatement? = nil
    //try self.sync { () throws(SimpleGraphError) -> Void in
    var stmtHandle: OpaquePointer? = nil
    if sqlite3_prepare_v2(self.db, query, -1, &stmtHandle, nil) != SQLITE_OK {
      throw SimpleGraphError.queryExecutionError(message: String(cString: sqlite3_errmsg(db)), query: query)
    }
    return SQLiteStatement(handle: stmtHandle!)
    //}
    //return stmt.take()!
  }

  private func execute(_ query: String) throws(SimpleGraphError) {
    if sqlite3_exec(self.db, query, nil, nil, nil) != SQLITE_OK {
      throw SimpleGraphError.queryExecutionError(message: String(cString: sqlite3_errmsg(db)), query: query)
    }
  }

  //private let queue = DispatchQueue(label: "SimpleGraph", attributes: [])
  //private var queueContext: Int = UUID().hashValue
  //private let queueKey = DispatchSpecificKey<Int>()
  //private func sync<Result>(_ block: () throws(SimpleGraphError) -> Result) throws(SimpleGraphError) -> Result {
  //  if DispatchQueue.getSpecific(key: queueKey) == queueContext {
  //    return try block()
  //  } else {
  //    do {
  //      return try self.queue.sync(execute: block)
  //    } catch let error as SimpleGraphError {
  //      throw error
  //    } catch {
  //      fatalError("unreachable: \(error)")
  //    }
  //  }
  //}

  deinit {
    sqlite3_close_v2(self.db)
  }
}
