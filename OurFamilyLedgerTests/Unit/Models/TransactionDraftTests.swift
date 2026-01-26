import XCTest
@testable import OurFamilyLedger

/// Tests for TransactionDraft
final class TransactionDraftTests: XCTestCase {

    // MARK: - Split Amount Tests

    func testSplitAmount_dividesEvenly() {
        // Given
        let draft = TransactionDraft(
            amount: 100,
            categoryName: "餐饮",
            payerName: "用户1",
            participantNames: ["用户1", "用户2"]
        )

        // When
        let splitAmount = draft.splitAmount

        // Then
        XCTAssertEqual(splitAmount, 50)
    }

    func testSplitAmount_threeParticipants() {
        // Given
        let draft = TransactionDraft(
            amount: 99,
            categoryName: "餐饮",
            payerName: "用户1",
            participantNames: ["用户1", "用户2", "用户3"]
        )

        // When
        let splitAmount = draft.splitAmount

        // Then
        XCTAssertEqual(splitAmount, 33) // 99 / 3 = 33
    }

    func testSplitAmount_singleParticipant() {
        // Given
        let draft = TransactionDraft(
            amount: 100,
            categoryName: "餐饮",
            payerName: "用户1",
            participantNames: ["用户1"]
        )

        // When
        let splitAmount = draft.splitAmount

        // Then
        XCTAssertEqual(splitAmount, 100)
    }

    func testSplitAmount_emptyParticipants_returnsFullAmount() {
        // Given
        let draft = TransactionDraft(
            amount: 100,
            categoryName: "餐饮",
            payerName: "用户1",
            participantNames: []
        )

        // When
        let splitAmount = draft.splitAmount

        // Then
        XCTAssertEqual(splitAmount, 100)
    }

    // MARK: - Initialization Tests

    func testInit_defaultValues() {
        // When
        let draft = TransactionDraft(
            amount: 50,
            categoryName: "餐饮",
            payerName: "测试"
        )

        // Then
        XCTAssertNotEqual(draft.id, UUID()) // Has a unique ID
        XCTAssertEqual(draft.amount, 50)
        XCTAssertEqual(draft.type, .expense)
        XCTAssertEqual(draft.categoryName, "餐饮")
        XCTAssertEqual(draft.payerName, "测试")
        XCTAssertTrue(draft.participantNames.isEmpty)
        XCTAssertEqual(draft.note, "")
        XCTAssertEqual(draft.merchant, "")
        XCTAssertEqual(draft.source, .text)
        XCTAssertNil(draft.ocrText)
        XCTAssertNil(draft.confidenceAmount)
        XCTAssertNil(draft.confidenceDate)
    }

    func testInit_customValues() {
        // Given
        let customId = UUID()
        let customDate = Date(timeIntervalSince1970: 0)

        // When
        let draft = TransactionDraft(
            id: customId,
            date: customDate,
            amount: 150.50,
            type: .income,
            categoryName: "工资",
            payerName: "公司",
            participantNames: ["我"],
            note: "月薪",
            merchant: "ABC公司",
            source: .manual,
            ocrText: "OCR结果",
            confidenceAmount: 0.95,
            confidenceDate: 0.8
        )

        // Then
        XCTAssertEqual(draft.id, customId)
        XCTAssertEqual(draft.date, customDate)
        XCTAssertEqual(draft.amount, 150.50)
        XCTAssertEqual(draft.type, .income)
        XCTAssertEqual(draft.categoryName, "工资")
        XCTAssertEqual(draft.payerName, "公司")
        XCTAssertEqual(draft.participantNames, ["我"])
        XCTAssertEqual(draft.note, "月薪")
        XCTAssertEqual(draft.merchant, "ABC公司")
        XCTAssertEqual(draft.source, .manual)
        XCTAssertEqual(draft.ocrText, "OCR结果")
        XCTAssertEqual(draft.confidenceAmount, 0.95)
        XCTAssertEqual(draft.confidenceDate, 0.8)
    }

    // MARK: - Equatable Tests

    func testEquatable_sameValues_isEqual() {
        // Given
        let id = UUID()
        let date = Date()
        let draft1 = TransactionDraft(
            id: id,
            date: date,
            amount: 100,
            categoryName: "餐饮",
            payerName: "用户"
        )
        let draft2 = TransactionDraft(
            id: id,
            date: date,
            amount: 100,
            categoryName: "餐饮",
            payerName: "用户"
        )

        // Then - Swift struct Equatable compares all properties
        XCTAssertEqual(draft1, draft2)
    }

    func testEquatable_differentId_isNotEqual() {
        // Given
        let draft1 = TransactionDraft(
            amount: 100,
            categoryName: "餐饮",
            payerName: "用户"
        )
        let draft2 = TransactionDraft(
            amount: 100,
            categoryName: "餐饮",
            payerName: "用户"
        )

        // Then
        XCTAssertNotEqual(draft1, draft2)
    }
}
