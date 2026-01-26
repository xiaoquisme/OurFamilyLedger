import XCTest
import SwiftData
@testable import OurFamilyLedger

/// Tests for TransactionListViewModel
@MainActor
final class TransactionListViewModelTests: XCTestCase {
    private var viewModel: TransactionListViewModel!
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()

        modelContainer = try TestModelContainer.create()
        modelContext = modelContainer.mainContext
        viewModel = TransactionListViewModel()
        viewModel.configure(modelContext: modelContext)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        modelContext = nil
        modelContainer = nil
        try super.tearDownWithError()
    }

    // Helper to create and insert transaction
    private func createTransaction(
        date: Date = Date(),
        amount: Decimal = 100,
        type: TransactionType = .expense,
        categoryId: UUID? = nil,
        payerId: UUID? = nil,
        note: String = "",
        merchant: String = ""
    ) -> TransactionRecord {
        let record = TransactionRecord(
            date: date,
            amount: amount,
            type: type,
            categoryId: categoryId,
            payerId: payerId,
            note: note,
            merchant: merchant
        )
        modelContext.insert(record)
        return record
    }

    // MARK: - Filter Tests

    func testApplyFilter_byDateRange_filtersCorrectly() {
        // Given
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!

        let t1 = createTransaction(date: today)
        let t2 = createTransaction(date: yesterday)
        let t3 = createTransaction(date: twoDaysAgo)

        viewModel.filter.startDate = yesterday
        viewModel.filter.endDate = today

        // When
        let filtered = viewModel.applyFilter(to: [t1, t2, t3])

        // Then
        XCTAssertEqual(filtered.count, 2)
    }

    func testApplyFilter_byCategory_filtersCorrectly() {
        // Given
        let categoryId1 = UUID()
        let categoryId2 = UUID()

        let t1 = createTransaction(categoryId: categoryId1)
        let t2 = createTransaction(categoryId: categoryId2)
        let t3 = createTransaction(categoryId: categoryId1)

        viewModel.filter.categoryIds = [categoryId1]

        // When
        let filtered = viewModel.applyFilter(to: [t1, t2, t3])

        // Then
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.categoryId == categoryId1 })
    }

    func testApplyFilter_byPayer_filtersCorrectly() {
        // Given
        let payerId1 = UUID()
        let payerId2 = UUID()

        let t1 = createTransaction(payerId: payerId1)
        let t2 = createTransaction(payerId: payerId2)
        let t3 = createTransaction(payerId: payerId1)

        viewModel.filter.payerIds = [payerId1]

        // When
        let filtered = viewModel.applyFilter(to: [t1, t2, t3])

        // Then
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.payerId == payerId1 })
    }

    func testApplyFilter_byAmountRange_filtersCorrectly() {
        // Given
        let t1 = createTransaction(amount: 50)
        let t2 = createTransaction(amount: 100)
        let t3 = createTransaction(amount: 200)

        viewModel.filter.minAmount = 75
        viewModel.filter.maxAmount = 150

        // When
        let filtered = viewModel.applyFilter(to: [t1, t2, t3])

        // Then
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.amount, 100)
    }

    func testApplyFilter_byType_filtersCorrectly() {
        // Given
        let t1 = createTransaction(type: .expense)
        let t2 = createTransaction(type: .income)
        let t3 = createTransaction(type: .expense)

        viewModel.filter.types = [.income]

        // When
        let filtered = viewModel.applyFilter(to: [t1, t2, t3])

        // Then
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.type, .income)
    }

    func testApplyFilter_bySearchText_filtersCorrectly() {
        // Given
        let t1 = createTransaction(note: "午餐", merchant: "餐厅A")
        let t2 = createTransaction(note: "购物", merchant: "超市")
        let t3 = createTransaction(note: "早餐", merchant: "咖啡店")

        viewModel.filter.searchText = "餐"

        // When
        let filtered = viewModel.applyFilter(to: [t1, t2, t3])

        // Then
        XCTAssertEqual(filtered.count, 2)
    }

    func testClearFilter_resetsAllFilters() {
        // Given
        viewModel.filter.startDate = Date()
        viewModel.filter.categoryIds = [UUID()]
        viewModel.filter.minAmount = 100

        // When
        viewModel.filter.reset()

        // Then
        XCTAssertNil(viewModel.filter.startDate)
        XCTAssertTrue(viewModel.filter.categoryIds.isEmpty)
        XCTAssertNil(viewModel.filter.minAmount)
        XCTAssertFalse(viewModel.filter.isActive)
    }

    // MARK: - Sort Tests

    func testApplySort_byDateDescending_sortsCorrectly() {
        // Given
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!

        let t1 = createTransaction(date: yesterday)
        let t2 = createTransaction(date: today)
        let t3 = createTransaction(date: twoDaysAgo)

        viewModel.sortOrder = .dateDescending

        // When
        let sorted = viewModel.applySort(to: [t1, t2, t3])

        // Then
        XCTAssertEqual(sorted[0].date, today)
        XCTAssertEqual(sorted[1].date, yesterday)
        XCTAssertEqual(sorted[2].date, twoDaysAgo)
    }

    func testApplySort_byAmountDescending_sortsCorrectly() {
        // Given
        let t1 = createTransaction(amount: 100)
        let t2 = createTransaction(amount: 50)
        let t3 = createTransaction(amount: 200)

        viewModel.sortOrder = .amountDescending

        // When
        let sorted = viewModel.applySort(to: [t1, t2, t3])

        // Then
        XCTAssertEqual(sorted[0].amount, 200)
        XCTAssertEqual(sorted[1].amount, 100)
        XCTAssertEqual(sorted[2].amount, 50)
    }

    func testApplySort_byAmountAscending_sortsCorrectly() {
        // Given
        let t1 = createTransaction(amount: 100)
        let t2 = createTransaction(amount: 50)
        let t3 = createTransaction(amount: 200)

        viewModel.sortOrder = .amountAscending

        // When
        let sorted = viewModel.applySort(to: [t1, t2, t3])

        // Then
        XCTAssertEqual(sorted[0].amount, 50)
        XCTAssertEqual(sorted[1].amount, 100)
        XCTAssertEqual(sorted[2].amount, 200)
    }

    // MARK: - Grouping Tests

    func testGroupByDate_groupsCorrectly() {
        // Given
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let t1 = createTransaction(date: today)
        let t2 = createTransaction(date: today)
        let t3 = createTransaction(date: yesterday)

        // When
        let grouped = viewModel.groupByDate([t1, t2, t3])

        // Then
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[0].transactions.count, 2) // today (more recent first)
        XCTAssertEqual(grouped[1].transactions.count, 1) // yesterday
    }

    // MARK: - Statistics Tests

    func testDaySummary_calculatesCorrectly() {
        // Given
        let t1 = createTransaction(amount: 100, type: .expense)
        let t2 = createTransaction(amount: 50, type: .expense)
        let t3 = createTransaction(amount: 200, type: .income)

        // When
        let summary = viewModel.daySummary(for: [t1, t2, t3])

        // Then
        XCTAssertEqual(summary.expense, 150)
        XCTAssertEqual(summary.income, 200)
        XCTAssertEqual(summary.balance, 50)
    }

    // MARK: - Multi-Select Tests

    func testToggleMultiSelectMode_togglesState() {
        // Given
        XCTAssertFalse(viewModel.isMultiSelectMode)

        // When
        viewModel.toggleMultiSelectMode()

        // Then
        XCTAssertTrue(viewModel.isMultiSelectMode)

        // When
        viewModel.toggleMultiSelectMode()

        // Then
        XCTAssertFalse(viewModel.isMultiSelectMode)
    }

    func testToggleSelection_addsAndRemovesTransactionId() {
        // Given
        let transactionId = UUID()
        XCTAssertTrue(viewModel.selectedTransactions.isEmpty)

        // When - Add
        viewModel.toggleSelection(for: transactionId)

        // Then
        XCTAssertTrue(viewModel.selectedTransactions.contains(transactionId))

        // When - Remove
        viewModel.toggleSelection(for: transactionId)

        // Then
        XCTAssertFalse(viewModel.selectedTransactions.contains(transactionId))
    }

    func testSelectAll_selectsAllTransactions() {
        // Given
        let t1 = createTransaction()
        let t2 = createTransaction()
        let t3 = createTransaction()

        // When
        viewModel.selectAll([t1, t2, t3])

        // Then
        XCTAssertEqual(viewModel.selectedTransactions.count, 3)
    }

    func testDeselectAll_clearsSelection() {
        // Given
        viewModel.selectedTransactions = [UUID(), UUID(), UUID()]

        // When
        viewModel.deselectAll()

        // Then
        XCTAssertTrue(viewModel.selectedTransactions.isEmpty)
    }
}
