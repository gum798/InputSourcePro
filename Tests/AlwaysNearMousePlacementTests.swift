import XCTest
@testable import Input_Source_Pro

/// Verifies how the always-near-mouse mode decides where the indicator goes:
/// hidden while scrolling, pinned to the text caret when one is found, and
/// following the mouse otherwise.
@MainActor
final class AlwaysNearMousePlacementTests: XCTestCase {
    private typealias Placement = IndicatorWindowController.AlwaysNearMouse.Placement

    private let point = CGPoint(x: 10, y: 20)

    func testScrollingHidesRegardlessOfPosition() {
        XCTAssertEqual(
            IndicatorWindowController.AlwaysNearMouse.placement(isScrolling: true, position: (.inputCursor, point)),
            Placement.hidden
        )
    }

    func testNoPositionFollowsMouse() {
        XCTAssertEqual(
            IndicatorWindowController.AlwaysNearMouse.placement(isScrolling: false, position: nil),
            Placement.mouse
        )
    }

    func testInputCursorPinsToCaret() {
        XCTAssertEqual(
            IndicatorWindowController.AlwaysNearMouse.placement(isScrolling: false, position: (.inputCursor, point)),
            Placement.caret(point)
        )
    }

    func testInputRectPinsToCaret() {
        XCTAssertEqual(
            IndicatorWindowController.AlwaysNearMouse.placement(isScrolling: false, position: (.inputRect, point)),
            Placement.caret(point)
        )
    }

    func testNonInputPositionsFollowMouse() {
        let kinds: [IndicatorActuallyPositionKind] = [.nearMouse, .windowCorner, .screenCorner, .floatingApp]

        for kind in kinds {
            XCTAssertEqual(
                IndicatorWindowController.AlwaysNearMouse.placement(isScrolling: false, position: (kind, point)),
                Placement.mouse,
                "\(kind) should follow the mouse"
            )
        }
    }
}
