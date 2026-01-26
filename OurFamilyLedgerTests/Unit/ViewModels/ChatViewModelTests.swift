import XCTest
import SwiftData
import UIKit
@testable import OurFamilyLedger

/// Tests for ChatViewModel
@MainActor
final class ChatViewModelTests: XCTestCase {
    private var viewModel: ChatViewModel!
    private var mockOCRService: MockOCRService!
    private var mockKeychainService: MockKeychainService!
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()

        mockOCRService = MockOCRService()
        mockKeychainService = MockKeychainService()

        viewModel = ChatViewModel(
            ocrService: mockOCRService,
            keychainService: mockKeychainService
        )

        // Set up in-memory SwiftData context
        modelContainer = try TestModelContainer.create()
        modelContext = modelContainer.mainContext
        viewModel.configure(modelContext: modelContext)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        mockOCRService = nil
        mockKeychainService = nil
        modelContext = nil
        modelContainer = nil

        try super.tearDownWithError()
    }

    // MARK: - State Tests

    func testIsProcessing_falseInitially() {
        XCTAssertFalse(viewModel.isProcessing)
    }

    func testCanRetry_falseInitially() {
        XCTAssertFalse(viewModel.canRetry)
    }

    func testPendingDrafts_emptyInitially() {
        XCTAssertTrue(viewModel.pendingDrafts.isEmpty)
    }

    func testMessages_emptyInitially() {
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    // MARK: - Input Processing Tests

    func testProcessInput_emptyInput_doesNotProcess() async {
        // When
        await viewModel.processInput(text: "", images: [])

        // Then
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertFalse(viewModel.isProcessing)
    }

    func testProcessInput_withText_addsUserMessage() async {
        // Given
        let testText = "今天午餐花了50元"

        // When
        await viewModel.processInput(text: testText, images: [])

        // Then
        XCTAssertFalse(viewModel.messages.isEmpty)
        XCTAssertEqual(viewModel.messages.first?.type, .user)
        XCTAssertEqual(viewModel.messages.first?.text, testText)
    }

    func testProcessInput_withoutAIService_usesSimpleParsing() async {
        // Given - No AI key configured, so simple parsing is used
        let testText = "午餐花了 ¥128.50"

        // When
        await viewModel.processInput(text: testText, images: [])

        // Then - User message should be added
        XCTAssertFalse(viewModel.messages.isEmpty)
        XCTAssertEqual(viewModel.messages.first?.type, .user)
    }

    // MARK: - Retry Tests

    func testRetry_withoutCanRetry_doesNothing() async {
        // Given - canRetry is false by default
        XCTAssertFalse(viewModel.canRetry)

        // When
        await viewModel.retry()

        // Then - No messages should be added
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertFalse(viewModel.isProcessing)
    }

    // MARK: - Draft Management Tests

    func testDeleteDraft_removesDraftFromPending() {
        // Given
        let draft = TestFixtures.transactionDraft()
        viewModel.pendingDrafts.append(draft)
        XCTAssertEqual(viewModel.pendingDrafts.count, 1)

        // When
        viewModel.deleteDraft(draft)

        // Then
        XCTAssertTrue(viewModel.pendingDrafts.isEmpty)
    }

    func testUpdateDraft_updatesExistingDraft() {
        // Given
        let originalDraft = TestFixtures.transactionDraft(amount: 100)
        viewModel.pendingDrafts.append(originalDraft)

        let updatedDraft = TransactionDraft(
            id: originalDraft.id,
            date: originalDraft.date,
            amount: 200,
            type: .expense,
            categoryName: "更新的分类",
            payerName: originalDraft.payerName,
            participantNames: originalDraft.participantNames,
            note: originalDraft.note,
            merchant: originalDraft.merchant,
            source: originalDraft.source
        )

        // When
        viewModel.updateDraft(originalDraft, with: updatedDraft)

        // Then
        XCTAssertEqual(viewModel.pendingDrafts.count, 1)
        XCTAssertEqual(viewModel.pendingDrafts.first?.amount, 200)
        XCTAssertEqual(viewModel.pendingDrafts.first?.categoryName, "更新的分类")
    }

    func testConfirmDraft_createsTransactionRecord() async {
        // Given
        let draft = TestFixtures.transactionDraft(
            amount: 150,
            categoryName: "餐饮",
            payerName: "测试用户"
        )
        viewModel.pendingDrafts.append(draft)

        // When
        await viewModel.confirmDraft(draft)

        // Then
        XCTAssertTrue(viewModel.pendingDrafts.isEmpty)

        // Verify system message was added
        let systemMessages = viewModel.messages.filter { $0.type == .system }
        XCTAssertFalse(systemMessages.isEmpty)
    }

    func testConfirmAllDrafts_confirmsAllPendingDrafts() async {
        // Given
        let drafts = TestFixtures.sampleTransactionDrafts
        viewModel.pendingDrafts.append(contentsOf: drafts)
        XCTAssertEqual(viewModel.pendingDrafts.count, 3)

        // When
        await viewModel.confirmAllDrafts()

        // Then
        XCTAssertTrue(viewModel.pendingDrafts.isEmpty)
    }

    // MARK: - OCR Integration Tests

    func testProcessImages_callsOCRService() async {
        // Given
        let testImage = UIImage()
        mockOCRService.setResult(text: "午餐 ¥50")

        // When
        await viewModel.processInput(text: "", images: [testImage])

        // Then
        XCTAssertEqual(mockOCRService.recognizeTextCallCount, 1)
    }

    func testProcessImages_withMultipleImages_callsOCRMultipleTimes() async {
        // Given
        let testImages = [UIImage(), UIImage()]
        mockOCRService.setResult(text: "午餐 ¥50")

        // When
        await viewModel.processInput(text: "", images: testImages)

        // Then
        XCTAssertEqual(mockOCRService.recognizeTextCallCount, 2)
    }

    // MARK: - Clarification Tests

    func testHandleClarification_updatesAmount() async {
        // Given
        let draft = TestFixtures.transactionDraft(amount: 100)
        viewModel.pendingDrafts.append(draft)

        // When
        await viewModel.handleClarification("应该是150元", for: draft)

        // Then
        XCTAssertEqual(viewModel.pendingDrafts.first?.amount, 150)
    }

    func testHandleClarification_updatesTypeToIncome() async {
        // Given
        let draft = TestFixtures.transactionDraft(type: .expense)
        viewModel.pendingDrafts.append(draft)

        // When
        await viewModel.handleClarification("这是收入", for: draft)

        // Then
        XCTAssertEqual(viewModel.pendingDrafts.first?.type, .income)
    }
}
