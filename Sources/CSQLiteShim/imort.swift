#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
#if SIMPLE_GRAPH_SQLITE_PKGCONFIG
@_exported import CSQLite3
#else
@_exported import SQLite3
#endif
#else
@_exported import CSQLite3
#endif
