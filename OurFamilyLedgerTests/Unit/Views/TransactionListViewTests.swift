import XCTest
@testable import OurFamilyLedger

/// Tests for TransactionListView initialization behavior.
///
/// These tests guard against the regression where TransactionListView was always
/// creating its own NavigationStack, causing nested-stack navigation bugs when
/// used as a destination from ReportsView (tapping a row would pop back instead
/// of pushing the detail view).
final class TransactionListViewTests: XCTestCase {

    // MARK: - embedsNavigation default

    func testInit_defaultEmbedsNavigation_isTrue() {
        let view = TransactionListView()
        XCTAssertTrue(view.embedsNavigation)
    }

    func testInit_withoutFilters_defaultEmbedsNavigationIsTrue() {
        let view = TransactionListView(filterType: nil, filterMonth: nil)
        XCTAssertTrue(view.embedsNavigation)
    }

    // MARK: - embedsNavigation: false (used from ReportsView)

    func testInit_embedsNavigationFalse_isFalse() {
        let view = TransactionListView(embedsNavigation: false)
        XCTAssertFalse(view.embedsNavigation)
    }

    func testInit_withFiltersAndEmbedsFalse_isFalse() {
        let view = TransactionListView(
            filterType: .expense,
            filterMonth: Date(),
            embedsNavigation: false
        )
        XCTAssertFalse(view.embedsNavigation)
    }

    // MARK: - embedsNavigation: true (explicit)

    func testInit_embedsNavigationTrue_isTrue() {
        let view = TransactionListView(embedsNavigation: true)
        XCTAssertTrue(view.embedsNavigation)
    }

    // MARK: - Filter parameters are preserved regardless of embedsNavigation

    func testInit_filterTypeExpense_preservedWhenEmbedsFalse() {
        let view = TransactionListView(filterType: .expense, embedsNavigation: false)
        XCTAssertFalse(view.embedsNavigation)
    }

    func testInit_filterTypeIncome_preservedWhenEmbedsTrue() {
        let view = TransactionListView(filterType: .income, embedsNavigation: true)
        XCTAssertTrue(view.embedsNavigation)
    }
}
