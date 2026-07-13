import Darwin
import Foundation

typealias LogWriteOperation = (
  _ fileDescriptor: Int32,
  _ buffer: UnsafeRawPointer,
  _ count: Int
) -> Int

/// Write all bytes through a POSIX-style operation, returning false on the
/// first failure. The operation is injectable so ENOSPC can be regression
/// tested without actually exhausting a disk.
@discardableResult
func writeLogData(
  _ data: Data,
  to fileDescriptor: Int32,
  using writeOperation: LogWriteOperation = { Darwin.write($0, $1, $2) }
) -> Bool {
  var succeeded = true
  data.withUnsafeBytes { rawBuffer in
    guard var base = rawBuffer.baseAddress else { return }
    var remaining = rawBuffer.count
    while remaining > 0 {
      let written = writeOperation(fileDescriptor, base, remaining)
      if written <= 0 {
        succeeded = false
        return
      }
      remaining -= written
      base = base.advanced(by: written)
    }
  }
  return succeeded
}
