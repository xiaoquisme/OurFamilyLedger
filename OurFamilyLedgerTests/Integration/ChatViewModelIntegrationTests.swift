import XCTest
import SwiftData
@testable import OurFamilyLedger

/// Integration tests for ChatViewModel with SwiftData
@MainActor
final class ChatViewModelIntegrationTests: XCTestCase {
    private var viewModel: ChatViewModel!
    private var mockOCRService: MockOCRService!
    private var mockKeychainService: MockKeychainService!
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!

    override func setUp() async throws {
        try await super.setUp()

        mockOCRService = MockOCRService()
        mockKeychainService = MockKeychainService()

        viewModel = ChatViewModel(
            ocrService: mockOCRService,
            keychainService: mockKeychainService
        )

        // Set up in-memory SwiftData container
        modelContainer = try TestModelContainer.create()
        modelContext = modelContainer.mainContext
        viewModel.configure(modelContext: modelContext)

        // Set up default member
        await setupDefaultMember()
    }

    override func tearDown() async throws {
        viewModel = nil
        mockOCRService = nil
        mockKeychainService = nil
        modelContext = nil
        modelContainer = nil

        // Clean up UserDefaults
        UserDefaults.standard.removeObject(forKey: "defaultMemberId")

        try await super.tearDown()
    }

    private func setupDefaultMember() async {
        let member = Member(name: "测试用户", isCurrentUser: true)
        modelContext.insert(member)
        try? modelContext.save()

        UserDefaults.standard.set(member.id.uuidString, forKey: "defaultMemberId")
    }

    // MARK: - Integration Tests

    func testConfirmDraft_createsTransactionInSwiftData() async throws {
        // Given
        let category = OurFamilyLedger.Category(name: "餐饮", type: .expense)
        modelContext.insert(category)
        try modelContext.save()

        let draft = TransactionDraft(
            amount: 150,
            categoryName: "餐饮",
            payerName: "测试用户",
            participantNames: ["测试用户"]
        )
        viewModel.pendingDrafts.append(draft)

        // When
        await viewModel.confirmDraft(draft)

        // Then
        let descriptor = FetchDescriptor<TransactionRecord>()
        let transactions = try modelContext.fetch(descriptor)

        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions[0].amount, 150)
        XCTAssertEqual(transactions[0].type, .expense)
    }

    func testConfirmDraft_createsNewCategoryIfNotExists() async throws {
        // Given
        let draft = TransactionDraft(
            amount: 100,
            categoryName: "新分类",
            payerName: "测试用户"
        )
        viewModel.pendingDrafts.append(draft)

        // When
        await viewModel.confirmDraft(draft)

        // Then
        let categoryDescriptor = FetchDescriptor<OurFamilyLedger.Category>()
        let categories = try modelContext.fetch(categoryDescriptor)

        XCTAssertTrue(categories.contains { $0.name == "新分类" })
    }

    func testConfirmDraft_createsMemberIfNotExists() async throws {
        // Given
        let draft = TransactionDraft(
            amount: 100,
            categoryName: "餐饮",
            payerName: "新用户",
            participantNames: ["新用户"]
        )
        viewModel.pendingDrafts.append(draft)

        // When
        await viewModel.confirmDraft(draft)

        // Then
        let memberDescriptor = FetchDescriptor<Member>(
            predicate: #Predicate { $0.name == "新用户" }
        )
        let members = try modelContext.fetch(memberDescriptor)

        XCTAssertFalse(members.isEmpty)
    }

    func testConfirmAllDrafts_persistsAllToSwiftData() async throws {
        // Given
        let drafts = [
            TransactionDraft(amount: 50, categoryName: "餐饮", payerName: "用户1"),
            TransactionDraft(amount: 100, categoryName: "购物", payerName: "用户2"),
            TransactionDraft(amount: 200, categoryName: "交通", payerName: "用户3")
        ]
        viewModel.pendingDrafts.append(contentsOf: drafts)

        // When
        await viewModel.confirmAllDrafts()

        // Then
        let descriptor = FetchDescriptor<TransactionRecord>()
        let transactions = try modelContext.fetch(descriptor)

        XCTAssertEqual(transactions.count, 3)
        XCTAssertTrue(viewModel.pendingDrafts.isEmpty)
    }

    func testFullFlow_textInputToTransaction() async throws {
        // Given - No AI service configured, will use simple parsing
        let inputText = "午餐 ¥128"

        // When
        await viewModel.processInput(text: inputText, images: [])

        // Then - Should have user message and assistant response
        XCTAssertFalse(viewModel.messages.isEmpty)
        XCTAssertEqual(viewModel.messages.first?.type, .user)
    }

    func testFullFlow_imageInputWithOCR() async throws {
        // Given
        mockOCRService.setResult(text: "支付宝\n¥50.00\n交易成功")
        let testImage = UIImage()

        // When
        await viewModel.processInput(text: "", images: [testImage])

        // Then
        XCTAssertEqual(mockOCRService.recognizeTextCallCount, 1)
        XCTAssertFalse(viewModel.messages.isEmpty)
    }

    func testTransactionLifecycle_createEditDelete() async throws {
        // Given - Create
        let draft = TransactionDraft(
            amount: 100,
            categoryName: "餐饮",
            payerName: "测试用户"
        )
        viewModel.pendingDrafts.append(draft)

        // When - Confirm creates record
        await viewModel.confirmDraft(draft)

        // Then - Record exists
        var descriptor = FetchDescriptor<TransactionRecord>()
        var transactions = try modelContext.fetch(descriptor)
        XCTAssertEqual(transactions.count, 1)
        let recordId = transactions[0].id

        // When - Delete
        let recordToDelete = transactions[0]
        modelContext.delete(recordToDelete)
        try modelContext.save()

        // Then - Record is deleted
        transactions = try modelContext.fetch(descriptor)
        XCTAssertEqual(transactions.count, 0)
    }

    // MARK: - SwiftData Relationship Tests

    func testTransactionWithCategory_preservesRelationship() async throws {
        // Given
        let category = OurFamilyLedger.Category(name: "测试分类", icon: "star", type: .expense)
        modelContext.insert(category)
        try modelContext.save()

        let draft = TransactionDraft(
            amount: 100,
            categoryName: "测试分类",
            payerName: "测试用户"
        )
        viewModel.pendingDrafts.append(draft)

        // When
        await viewModel.confirmDraft(draft)

        // Then
        let descriptor = FetchDescriptor<TransactionRecord>()
        let transactions = try modelContext.fetch(descriptor)

        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions[0].categoryId, category.id)
    }

    func testTransactionWithMultipleParticipants_preservesAll() async throws {
        // Given
        let member1 = Member(name: "成员1")
        let member2 = Member(name: "成员2")
        modelContext.insert(member1)
        modelContext.insert(member2)
        try modelContext.save()

        let draft = TransactionDraft(
            amount: 100,
            categoryName: "餐饮",
            payerName: "成员1",
            participantNames: ["成员1", "成员2"]
        )
        viewModel.pendingDrafts.append(draft)

        // When
        await viewModel.confirmDraft(draft)

        // Then
        let descriptor = FetchDescriptor<TransactionRecord>()
        let transactions = try modelContext.fetch(descriptor)

        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions[0].participantIds.count, 2)
        XCTAssertTrue(transactions[0].participantIds.contains(member1.id))
        XCTAssertTrue(transactions[0].participantIds.contains(member2.id))
    }
}
