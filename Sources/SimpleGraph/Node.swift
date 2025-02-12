import Foundation

public protocol Node: Codable {
  associatedtype ID: Codable

  var id: ID { get }
}

public struct Edge<Source: Node, Target: Node, Properties: Codable> {
  let source: Source
  let target: Target
  var properties: Properties?
}

public struct RawEdge {
  let source: String
  let target: String
  let properties: String?
}
