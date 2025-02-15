#if os(macOS)
import SQLite3
#else
import CSQLite3
#endif

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

typealias SQLite = OpaquePointer
