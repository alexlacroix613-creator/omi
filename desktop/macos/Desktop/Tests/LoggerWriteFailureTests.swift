import Darwin
import Foundation

private func exerciseDiskFullWrite() -> (succeeded: Bool, writeCalls: Int, errnoValue: Int32) {
  let payload = Data("still alive".utf8)
  var writeCalls = 0

  let succeeded = writeLogData(payload, to: 42) { fileDescriptor, _, byteCount in
    precondition(fileDescriptor == 42)
    precondition(byteCount == payload.count)
    writeCalls += 1
    errno = ENOSPC
    return -1
  }

  return (succeeded, writeCalls, errno)
}

#if LOGGER_WRITE_FAILURE_STANDALONE
@main
private struct LoggerWriteFailureStandalone {
  static func main() {
    let result = exerciseDiskFullWrite()
    precondition(!result.succeeded)
    precondition(result.writeCalls == 1)
    precondition(result.errnoValue == ENOSPC)
    print("Logger ENOSPC regression: PASS")
  }
}
#else
import XCTest

@testable import Omi_Computer

final class LoggerWriteFailureTests: XCTestCase {
  func testDiskFullWriteFailsClosedWithoutCrashing() {
    let result = exerciseDiskFullWrite()
    XCTAssertFalse(result.succeeded)
    XCTAssertEqual(result.writeCalls, 1)
    XCTAssertEqual(result.errnoValue, ENOSPC)
  }
}
#endif
