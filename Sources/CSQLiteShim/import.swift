#if SIMPLE_GRAPH_SQLITE_PKGCONFIG
@_exported import CSQLite3
#elseif os(iOS) || os(tvOS) || os(watchOS)
@_exported import SQLite3
#else
@_exported import CSQLite3
#endif
