import Foundation

import CSQLiteShim

struct SQLiteStatement: ~Copyable {
  let handle: OpaquePointer
  var bindingIndex: Int32 = 1

  mutating func bindNil() throws(SimpleGraphError) {
    try self.check(sqlite3_bind_null(self.handle, self.bindingIndex))
    self.bindingIndex += 1
  }

  mutating func bind(_ integer: Int64) throws(SimpleGraphError) {
    try self.check(sqlite3_bind_int64(self.handle, self.bindingIndex, integer))
    self.bindingIndex += 1
  }

  mutating func bind(_ double: Double) throws(SimpleGraphError) {
    try self.check(sqlite3_bind_double(self.handle, self.bindingIndex, double))
    self.bindingIndex += 1
  }

  mutating func bind(utf8String text: String) throws(SimpleGraphError) {
    try self.check(sqlite3_bind_text(self.handle, self.bindingIndex, text, -1, SQLITE_TRANSIENT))
    self.bindingIndex += 1
  }

  mutating func bind(utf8StringData: Data) throws(SimpleGraphError) {
    do {
      try utf8StringData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
        // for some reason this function does not work with SQLITE_STATIC, so we have to deal with the unnecessary cast
        try self.check(sqlite3_bind_text(self.handle, self.bindingIndex, ptr.baseAddress!, Int32(ptr.count), SQLITE_TRANSIENT))
      }
    } catch let error as SimpleGraphError {
      throw error
    } catch {
      fatalError("unreachable: \(error)")
    }
    self.bindingIndex += 1
  }

  /// Returns true if row data is available
  @discardableResult
  func step() throws(SimpleGraphError) -> Bool {
    let ret = sqlite3_step(self.handle)
    if ret == SQLITE_ROW {
      return true
    } else if ret == SQLITE_DONE || ret == SQLITE_OK {
      return false
    } else {
      throw SimpleGraphError.bindingError(String(cString: sqlite3_errstr(ret)))
    }
  }

  /// Get a string column from the statement's current row result
  func column(_ idx: Int32) -> String? {
    if let ptr = UnsafeRawPointer(sqlite3_column_text(self.handle, idx))?.assumingMemoryBound(to: CChar.self) {
      String(cString: ptr, encoding: .utf8)
    } else {
      nil
    }
  }

  /// A column value
  enum Column {
    case string(String)
    case data(Data)
    case double(Double)
    case int(Int64)
    /// `NULL`
    case none
  }

  func column(at idx: Int32) -> Column {
    switch (sqlite3_column_type(self.handle, idx)) {
      case SQLITE_NULL: return .none
      case SQLITE_TEXT: return .string(self.column(idx)!)
      case SQLITE_BLOB:
        if let ptr = sqlite3_column_blob(self.handle, idx) {
          return .data(Data(bytes: ptr, count: Int(sqlite3_column_bytes(self.handle, idx))))
        } else {
          return .data(Data())
        }
      case SQLITE_FLOAT: return .double(sqlite3_column_double(self.handle, idx))
      case SQLITE_INTEGER: return .int(sqlite3_column_int64(self.handle, idx))
      default: fatalError("unreacheable")
    }
  }

  @inline(__always)
  private func check(_ code: Int32) throws(SimpleGraphError) {
    if code != SQLITE_OK {
      throw SimpleGraphError.bindingError(String(cString: sqlite3_errstr(code)))
    }
  }

  deinit {
    sqlite3_finalize(self.handle)
  }
}
