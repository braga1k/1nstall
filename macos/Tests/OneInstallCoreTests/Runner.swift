import Foundation

// Command Line Tools ship the macOS SDK, but not XCTest. These checks run as a
// standalone Swift executable; no third-party test framework is required.
class CheckSuite {
  func setUpWithError() throws {}
  func tearDownWithError() throws {}
}
struct SkipCheck: Error {
  let reason: String
  init(_ reason: String) { self.reason = reason }
}
struct CheckError: Error { let description: String }
var failures = 0
func fail(_ message: String, _ file: StaticString, _ line: UInt) {
  failures += 1
  print("FAIL \(file):\(line): \(message)")
}
func expectTrue(
  _ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line
) { if !value { fail(message, file, line) } }
func expectFalse(
  _ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line
) { expectTrue(!value, message, file: file, line: line) }
func expectEqual<T: Equatable>(
  _ lhs: T, _ rhs: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line
) { if lhs != rhs { fail("\(lhs) != \(rhs) " + message, file, line) } }
func expectError<T>(
  _ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line
) {
  do {
    _ = try expression()
    fail("Expected an error", file, line)
  } catch {}
}
func requireValue<T>(_ value: T?) throws -> T {
  guard let value else { throw CheckError(description: "Expected a value") }
  return value
}
@main enum Checks {
  static func main() {
    let c = CoreTests()
    let tests: [(String, () throws -> Void)] = [
      (
        "testInventoryFindsNestedFoldersButNotEmbeddedHelpers",
        c.testInventoryFindsNestedFoldersButNotEmbeddedHelpers
      ),
      (
        "testInventoryKeepsSeparateCopiesWithSameBundleID",
        c.testInventoryKeepsSeparateCopiesWithSameBundleID
      ),
      ("testExactAssociationsAndRealCounts", c.testExactAssociationsAndRealCounts),
      ("testSymlinkAncestorsAndLeavesCannotEscape", c.testSymlinkAncestorsAndLeavesCannotEscape),
      (
        "testNestedSymlinksMakeMeasurementNonSelectable",
        c.testNestedSymlinksMakeMeasurementNonSelectable
      ),
      ("testChangedFilesRefuseStaleReview", c.testChangedFilesRefuseStaleReview),
      ("testInstalledCopiesBlockCleanup", c.testInstalledCopiesBlockCleanup),
      ("testContainersStayProtected", c.testContainersStayProtected),
      ("testTrashAndRestoreOnlyDisposableFixture", c.testTrashAndRestoreOnlyDisposableFixture),
      (
        "testRestartNeverTurnsUnfinishedOperationIntoSuccess",
        c.testRestartNeverTurnsUnfinishedOperationIntoSuccess
      ),
      ("testProcessArgumentsAreNotShellCode", c.testProcessArgumentsAreNotShellCode),
      ("testTimeoutIsAnError", c.testTimeoutIsAnError),
      (
        "testUnownedRemovalIsRejectedWithoutInvokingBrew",
        c.testUnownedRemovalIsRejectedWithoutInvokingBrew
      ),
      (
        "testChangedCaskOrPrivilegedInstallerIsRejected",
        c.testChangedCaskOrPrivilegedInstallerIsRejected
      ),
      (
        "testCatalogAutomaticEntriesHaveChecksumsAndUniqueIdentities",
        c.testCatalogAutomaticEntriesHaveChecksumsAndUniqueIdentities
      ),
    ]
    for (name, test) in tests {
      let before = failures
      do {
        try c.setUpWithError()
        try test()
      } catch {
        failures += 1
        print("FAIL \(name): \(error)")
      }
      do { try c.tearDownWithError() } catch {
        failures += 1
        print("Fixture cleanup failed: \(error)")
      }
      if failures == before { print("PASS \(name)") }
    }
    if ProcessInfo.processInfo.environment["ONEINSTALL_LIVE_TEST_APPDIR"] != nil {
      do { try LiveBrewTests().testTwoDisposableRealInstallsAndRemovals() } catch {
        failures += 1
        print("FAIL live: \(error)")
      }
    } else {
      print("SKIP live Homebrew test: no disposable directory specified")
    }
    print("\(tests.count) core checks; \(failures) failures")
    exit(failures == 0 ? 0 : 1)
  }
}
