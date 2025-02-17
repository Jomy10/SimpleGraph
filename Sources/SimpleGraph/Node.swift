import Foundation

public protocol Node: Codable {
  /// A unique identifier for the Node
  var id: String { get }
}

public struct Edge<Properties: Codable> {
  let sourceId: String
  let targetId: String
  var properties: Properties?

  public func source<Source: Node>(_ graphDB: SimpleGraph) throws -> Source {
    try graphDB.getNode(id: self.sourceId)!
  }

  public func target<Target: Node>(_ graphDB: SimpleGraph) throws -> Target {
    try graphDB.getNode(id: self.targetId)!
  }
}

public struct RawEdge {
  public let sourceId: String
  public let targetId: String
  let properties: String?

  /// Convert `RawEdge` into a specific `Edge`
  public func get<Properties: Codable>(
    properties: Properties.Type = Properties.self
  ) throws -> Edge<Properties> {
    let properties: Properties? = if let data = self.properties?.data(using: .utf8) {
      try SimpleGraph.decode(data)
    } else {
      nil
    }
    return Edge(
      sourceId: self.sourceId,
      targetId: self.targetId,
      properties: properties
    )
  }
}
