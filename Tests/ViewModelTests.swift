import XCTest
@testable import desktop_video

final class ViewModelTests: XCTestCase {
    func testStartupDefaults() {
        let vm = StartupDisplayVM()
        XCTAssertFalse(vm.launchAtLogin)
    }
}
