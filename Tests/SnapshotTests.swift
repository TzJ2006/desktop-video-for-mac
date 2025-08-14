import XCTest
import SwiftUI

final class SnapshotTests: XCTestCase {
    func testMainWindowPreview() {
        let view = AppMainWindow().frame(width: 900, height: 600)
        XCTAssertNotNil(view.body)
    }
}
