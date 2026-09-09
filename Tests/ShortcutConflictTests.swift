import XCTest
@testable import Input_Source_Pro

final class ShortcutConflictTests: XCTestCase {
    private let abc = ShortcutAssignment(id: "abc", displayName: "ABC", shortcut: "⌘⇧A")
    private let pinyin = ShortcutAssignment(id: "pinyin", displayName: "Pinyin", shortcut: "⌘⇧B")
    private let functionKeys = ShortcutAssignment(
        id: "toggle-function-keys",
        displayName: "Toggle Function Keys",
        shortcut: "⌘⇧F"
    )

    private var assignments: [ShortcutAssignment<String>] {
        [abc, pinyin, functionKeys]
    }

    func testIgnoresTheRecorderThatIsBeingEdited() {
        XCTAssertNil(ShortcutConflict.owner(of: "⌘⇧A", excluding: "abc", in: assignments))
    }

    func testFindsTheExistingOwnerOfADuplicateShortcut() {
        let conflict = ShortcutConflict.owner(of: "⌘⇧A", excluding: "pinyin", in: assignments)

        XCTAssertEqual(conflict?.id, "abc")
        XCTAssertEqual(conflict?.displayName, "ABC")
    }

    func testStillConflictsWhenAnotherOwnerAlreadySharesTheShortcut() {
        let duplicateFunctionKeys = ShortcutAssignment(
            id: "toggle-function-keys",
            displayName: "Toggle Function Keys",
            shortcut: "⌘⇧A"
        )
        let conflict = ShortcutConflict.owner(
            of: "⌘⇧A",
            excluding: "abc",
            in: [abc, duplicateFunctionKeys]
        )

        XCTAssertEqual(conflict?.id, "toggle-function-keys")
    }

    func testFindsConflictAgainstFunctionKeysToggle() {
        let conflict = ShortcutConflict.owner(
            of: "⌘⇧F",
            excluding: "unrelated",
            in: assignments
        )

        XCTAssertEqual(conflict?.id, "toggle-function-keys")
        XCTAssertEqual(conflict?.displayName, "Toggle Function Keys")
    }

    func testAcceptsAUniqueShortcut() {
        let result = ShortcutConflict.resolve(
            proposed: "⌘⇧C",
            currentId: "pinyin",
            lastAccepted: pinyin.shortcut,
            assignments: assignments
        )

        XCTAssertEqual(result.accepted, "⌘⇧C")
        XCTAssertNil(result.conflictOwnerName)
    }

    func testRejectsAConflictAndKeepsThePreviousShortcut() {
        let result = ShortcutConflict.resolve(
            proposed: "⌘⇧A",
            currentId: "pinyin",
            lastAccepted: pinyin.shortcut,
            assignments: assignments
        )

        XCTAssertEqual(result.accepted, "⌘⇧B")
        XCTAssertEqual(result.conflictOwnerName, "ABC")
    }

    func testRejectsAConflictWhenTheRecorderWasEmpty() {
        let result = ShortcutConflict.resolve(
            proposed: "⌘⇧A",
            currentId: "new-row",
            lastAccepted: nil,
            assignments: assignments
        )

        XCTAssertNil(result.accepted)
        XCTAssertEqual(result.conflictOwnerName, "ABC")
    }

    func testClearingAShortcutIsNotAConflict() {
        let result = ShortcutConflict.resolve(
            proposed: nil as String?,
            currentId: "abc",
            lastAccepted: abc.shortcut,
            assignments: assignments
        )

        XCTAssertNil(result.accepted)
        XCTAssertNil(result.conflictOwnerName)
    }

    func testConflictMessageNamesTheExistingShortcut() {
        let message = ShortcutConflict.message(with: "ABC")

        XCTAssertTrue(message.contains("ABC"), "message should name the existing shortcut, got: \(message)")
        XCTAssertFalse(message.hasPrefix("**"), "message should be localized, got: \(message)")
    }

    func testPersistWritesRestoresCurrentAndReassertsOwnerShortcut() {
        let writes = ShortcutConflict.persistWrites(
            proposed: "⌘⇧A",
            currentId: "pinyin",
            decision: .init(accepted: "⌘⇧B", conflictOwnerName: "ABC"),
            assignments: assignments
        )

        XCTAssertEqual(
            writes,
            [
                ShortcutConflict.PersistWrite(id: "pinyin", shortcut: "⌘⇧B"),
                ShortcutConflict.PersistWrite(id: "abc", shortcut: "⌘⇧A")
            ]
        )
    }

    func testPersistWritesReassertsOwnerWhenCurrentHadNoShortcut() {
        let writes = ShortcutConflict.persistWrites(
            proposed: "⌘⇧A",
            currentId: "new-row",
            decision: .init(accepted: nil, conflictOwnerName: "ABC"),
            assignments: assignments
        )

        XCTAssertEqual(
            writes,
            [
                ShortcutConflict.PersistWrite(id: "new-row", shortcut: nil),
                ShortcutConflict.PersistWrite(id: "abc", shortcut: "⌘⇧A")
            ]
        )
    }

    func testPersistWritesNoOpsWhenThereIsNoConflict() {
        let writes = ShortcutConflict.persistWrites(
            proposed: "⌘⇧C",
            currentId: "pinyin",
            decision: .init(accepted: "⌘⇧C", conflictOwnerName: nil),
            assignments: assignments
        )

        XCTAssertTrue(writes.isEmpty)
    }

    func testModifierComboConflictsUseTheSameResolver() {
        let leftShift = ModifierCombo(keys: [.leftShift])
        let rightCommand = ModifierCombo(keys: [.rightCommand])
        let assignments = [
            ShortcutAssignment(id: "abc", displayName: "ABC", shortcut: leftShift)
        ]

        let result = ShortcutConflict.resolve(
            proposed: leftShift,
            currentId: "pinyin",
            lastAccepted: rightCommand,
            assignments: assignments
        )

        XCTAssertEqual(result.accepted, rightCommand)
        XCTAssertEqual(result.conflictOwnerName, "ABC")
    }
}
