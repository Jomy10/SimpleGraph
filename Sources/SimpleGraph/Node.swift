import Foundation

public protocol Node: Codable {
  associatedtype ID: Codable

  var id: ID { get }
}

public struct Edge<Source: Node, Target: Node, Properties: Codable> {
  let sourceId: Source.ID
  let targetId: Target.ID
  var properties: Properties?

  public func source(_ graphDB: SimpleGraph) throws -> Source {
    try graphDB.getNode(id: self.sourceId)!
  }

  public func target(_ graphDB: SimpleGraph) throws -> Target {
    try graphDB.getNode(id: self.targetId)!
  }
}

public struct RawEdge {
  let rawSourceId: String
  let rawTargetId: String
  let properties: String?

  /// Convert `RawEdge` into a specific `Edge`
  public func get<Source: Node, Target: Node, Properties: Codable>(
    source: Source.Type = Source.self,
    target: Target.Type = Target.self,
    properties: Properties.Type = Properties.self
  ) throws -> Edge<Source, Target, Properties> {
    let properties: Properties? = if let data = self.properties?.data(using: .utf8) {
      try SimpleGraph.decode(data)
    } else {
      nil
    }
    return Edge(
      sourceId: try SimpleGraph.decode(self.rawSourceId.data(using: .utf8)!),
      targetId: try SimpleGraph.decode(self.rawTargetId.data(using: .utf8)!),
      properties: properties
    )
  }

  public func sourceId<ID: Codable>(_: ID.Type = ID.self) throws -> ID {
    return try SimpleGraph.decode(self.rawSourceId.data(using: .utf8)!)
  }

  public func targetId<ID: Codable>(_: ID.Type = ID.self) throws -> ID {
    return try SimpleGraph.decode(self.rawTargetId.data(using: .utf8)!)
  }
}
