import AppKit
import Combine
import XCTest
@testable import Input_Source_Pro

/// Verifies how the always-near-mouse mode decides where the indicator goes:
/// hidden while a caret scrolls, pinned to the text caret when one is found, and
/// following the mouse otherwise.
@MainActor
final class AlwaysNearMousePlacementTests: XCTestCase {
    private typealias Placement = IndicatorWindowController.AlwaysNearMouse.Placement

    private let point = CGPoint(x: 10, y: 20)

    func testScrollingHidesCaret() {
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

    func testScrollingWithoutCaretKeepsFollowingMouse() {
        let positions: [PreferencesVM.IndicatorPositionInfo?] = [
            nil, (.nearMouse, point), (.windowCorner, point),
            (.screenCorner, point), (.floatingApp, point),
        ]

        for position in positions {
            let scrolling = PassthroughSubject<Bool, Never>()
            var placements: [Placement] = []
            var queryCount = 0
            let subscription = IndicatorWindowController.AlwaysNearMouse.placementPublisher(
                isScrolling: scrolling.eraseToAnyPublisher()
            ) {
                queryCount += 1
                return Just(position).eraseToAnyPublisher()
            }
            .sink { placements.append($0) }

            scrolling.send(false)
            scrolling.send(true)
            scrolling.send(true)
            XCTAssertEqual(placements, [.mouse])
            XCTAssertEqual(queryCount, 1, "Scrolling must not add Accessibility queries")

            scrolling.send(false)
            XCTAssertEqual(placements, [.mouse])
            XCTAssertEqual(queryCount, 2)
            subscription.cancel()
        }
    }

    func testCaretHidesImmediatelyWhileScrollingAndResolvesAgainAfterward() {
        for kind in [IndicatorActuallyPositionKind.inputCursor, .inputRect] {
            let scrolling = PassthroughSubject<Bool, Never>()
            let position = PassthroughSubject<PreferencesVM.IndicatorPositionInfo?, Never>()
            var placements: [Placement] = []
            var queryCount = 0
            let subscription = IndicatorWindowController.AlwaysNearMouse.placementPublisher(
                isScrolling: scrolling.eraseToAnyPublisher()
            ) {
                queryCount += 1
                return position.eraseToAnyPublisher()
            }
            .sink { placements.append($0) }

            scrolling.send(false)
            position.send((kind, point))
            scrolling.send(true)
            XCTAssertEqual(placements, [.caret(point), .hidden])
            XCTAssertEqual(queryCount, 1)

            // A query cancelled by scrolling cannot restore a stale caret.
            position.send((kind, CGPoint(x: 30, y: 40)))
            scrolling.send(true)
            XCTAssertEqual(placements, [.caret(point), .hidden])

            scrolling.send(false)
            XCTAssertEqual(queryCount, 2)
            let movedPoint = CGPoint(x: 50, y: 60)
            position.send((kind, movedPoint))
            XCTAssertEqual(placements, [.caret(point), .hidden, .caret(movedPoint)])

            // Losing text focus must also clear the remembered caret placement.
            scrolling.send(false)
            position.send(nil)
            scrolling.send(true)
            XCTAssertEqual(placements, [.caret(point), .hidden, .caret(movedPoint), .mouse])
            subscription.cancel()
        }
    }

    func testScrollingBeforeFirstCaretResultKeepsMouseFallback() {
        let scrolling = PassthroughSubject<Bool, Never>()
        let position = PassthroughSubject<PreferencesVM.IndicatorPositionInfo?, Never>()
        var placements: [Placement] = []
        let subscription = IndicatorWindowController.AlwaysNearMouse.placementPublisher(
            isScrolling: scrolling.eraseToAnyPublisher(),
            getPosition: { position.eraseToAnyPublisher() }
        )
        .sink { placements.append($0) }

        scrolling.send(false)
        scrolling.send(true)
        position.send((.inputCursor, point))
        XCTAssertEqual(placements, [.mouse])

        scrolling.send(false)
        position.send((.inputCursor, point))
        XCTAssertEqual(placements, [.mouse, .caret(point)])
        subscription.cancel()
    }

    func testFunctionKeyBadgesRemainReadableAtCaretUntilExpiry() {
        let controller = IndicatorViewController()
        let inputSource = InputSource.getCurrentInputSource()

        for mode in [FKeyMode.functionKeys, .mediaKeys] {
            let config = IndicatorViewConfig(
                inputSource: inputSource,
                kind: .iconAndTitle,
                size: .medium,
                bgColor: .black,
                textColor: .white
            )

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0

                controller.prepare(config: config)
                controller.refresh()
                controller.showAlwaysOnView()
                XCTAssertEqual(controller.normalView?.alphaValue, 0)
                XCTAssertEqual(controller.alwaysOnView?.alphaValue, 1)

                var badgeConfig = config
                badgeConfig.badge = .init(glyph: mode.badgeGlyph, title: mode.displayName)
                controller.prepare(config: badgeConfig)
                controller.refresh()
                controller.showAlwaysOnView()
                XCTAssertEqual(controller.normalView?.alphaValue, 1)
                XCTAssertEqual(controller.alwaysOnView?.alphaValue, 0)

                // Caret updates during the one-second badge lifetime must not
                // turn the function/media key feedback into an unlabelled dot.
                controller.refresh()
                controller.showAlwaysOnView()
                XCTAssertEqual(controller.normalView?.alphaValue, 1)
                XCTAssertEqual(controller.alwaysOnView?.alphaValue, 0)

                // The badge timer restores the input-source config on expiry.
                controller.prepare(config: config)
                controller.refresh()
                controller.showAlwaysOnView()
                XCTAssertEqual(controller.normalView?.alphaValue, 0)
                XCTAssertEqual(controller.alwaysOnView?.alphaValue, 1)
            }
        }
    }
}
