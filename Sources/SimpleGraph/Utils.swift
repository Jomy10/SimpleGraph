import CSQLiteShim

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

typealias SQLite = OpaquePointer
