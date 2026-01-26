import XCTest
@testable import OurFamilyLedger

/// Tests for Date Extensions
final class DateExtensionsTests: XCTestCase {

    // MARK: - Date Formatting Tests

    func testDateString_formatsCorrectly() {
        // Given
        var dateComponents = DateComponents()
        dateComponents.year = 2024
        dateComponents.month = 3
        dateComponents.day = 15
        let date = Calendar.current.date(from: dateComponents)!

        // When
        let result = date.dateString

        // Then
        XCTAssertEqual(result, "2024-03-15")
    }

    func testYearMonthString_formatsCorrectly() {
        // Given
        var dateComponents = DateComponents()
        dateComponents.year = 2024
        dateComponents.month = 3
        dateComponents.day = 15
        let date = Calendar.current.date(from: dateComponents)!

        // When
        let result = date.yearMonthString

        // Then
        XCTAssertEqual(result, "2024-03")
    }

    func testIso8601String_formatsCorrectly() {
        // Given
        let date = Date(timeIntervalSince1970: 0)

        // When
        let result = date.iso8601String

        // Then
        XCTAssertTrue(result.contains("1970"))
    }

    // MARK: - Friendly String Tests

    func testFriendlyString_today_returnsToday() {
        // Given
        let date = Date()

        // When
        let result = date.friendlyString

        // Then
        XCTAssertEqual(result, "今天")
    }

    func testFriendlyString_yesterday_returnsYesterday() {
        // Given
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        // When
        let result = yesterday.friendlyString

        // Then
        XCTAssertEqual(result, "昨天")
    }

    func testFriendlyString_tomorrow_returnsTomorrow() {
        // Given
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

        // When
        let result = tomorrow.friendlyString

        // Then
        XCTAssertEqual(result, "明天")
    }

    func testFriendlyString_thisYear_noYearInOutput() {
        // Given
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = calendar.component(.year, from: Date())
        components.month = 6
        components.day = 15
        let date = calendar.date(from: components)!

        // When
        let result = date.friendlyString

        // Then
        // If it's today, yesterday, or tomorrow, it will be those strings
        // Otherwise it should be like "6月15日" (no year)
        let isSpecialDay = calendar.isDateInToday(date) ||
                          calendar.isDateInYesterday(date) ||
                          calendar.isDateInTomorrow(date)

        if !isSpecialDay {
            XCTAssertTrue(result.contains("月"))
            XCTAssertTrue(result.contains("日"))
            XCTAssertFalse(result.contains("年"))
        }
    }

    func testFriendlyString_differentYear_includesYear() {
        // Given
        var components = DateComponents()
        components.year = 2020
        components.month = 6
        components.day = 15
        let date = Calendar.current.date(from: components)!

        // When
        let result = date.friendlyString

        // Then
        XCTAssertTrue(result.contains("2020年"))
        XCTAssertTrue(result.contains("6月"))
        XCTAssertTrue(result.contains("15日"))
    }

    // MARK: - Month Boundary Tests

    func testStartOfMonth_returnsFirstDay() {
        // Given
        var components = DateComponents()
        components.year = 2024
        components.month = 3
        components.day = 15
        let date = Calendar.current.date(from: components)!

        // When
        let startOfMonth = date.startOfMonth

        // Then
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.day, from: startOfMonth), 1)
        XCTAssertEqual(calendar.component(.month, from: startOfMonth), 3)
        XCTAssertEqual(calendar.component(.year, from: startOfMonth), 2024)
    }

    func testEndOfMonth_returnsLastDay() {
        // Given
        var components = DateComponents()
        components.year = 2024
        components.month = 3
        components.day = 15
        let date = Calendar.current.date(from: components)!

        // When
        let endOfMonth = date.endOfMonth

        // Then
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.day, from: endOfMonth), 31) // March has 31 days
        XCTAssertEqual(calendar.component(.month, from: endOfMonth), 3)
    }

    func testEndOfMonth_february_leapYear() {
        // Given
        var components = DateComponents()
        components.year = 2024 // Leap year
        components.month = 2
        components.day = 10
        let date = Calendar.current.date(from: components)!

        // When
        let endOfMonth = date.endOfMonth

        // Then
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.day, from: endOfMonth), 29) // Feb 2024 has 29 days
    }

    // MARK: - Day Boundary Tests

    func testStartOfDay_returnsBeginningOfDay() {
        // Given
        var components = DateComponents()
        components.year = 2024
        components.month = 3
        components.day = 15
        components.hour = 14
        components.minute = 30
        let date = Calendar.current.date(from: components)!

        // When
        let startOfDay = date.startOfDay

        // Then
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.hour, from: startOfDay), 0)
        XCTAssertEqual(calendar.component(.minute, from: startOfDay), 0)
        XCTAssertEqual(calendar.component(.second, from: startOfDay), 0)
    }

    func testEndOfDay_returnsEndOfDay() {
        // Given
        var components = DateComponents()
        components.year = 2024
        components.month = 3
        components.day = 15
        components.hour = 14
        let date = Calendar.current.date(from: components)!

        // When
        let endOfDay = date.endOfDay

        // Then
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.hour, from: endOfDay), 23)
        XCTAssertEqual(calendar.component(.minute, from: endOfDay), 59)
        XCTAssertEqual(calendar.component(.second, from: endOfDay), 59)
    }

    // MARK: - String Extension Tests

    func testIso8601Date_parsesCorrectly() {
        // Given
        let dateString = "2024-03-15T10:30:00Z"

        // When
        let date = dateString.iso8601Date

        // Then
        XCTAssertNotNil(date)
    }

    func testIso8601Date_invalidString_returnsNil() {
        // Given
        let invalidString = "not a date"

        // When
        let date = invalidString.iso8601Date

        // Then
        XCTAssertNil(date)
    }

    func testDateValue_parsesCorrectly() {
        // Given
        let dateString = "2024-03-15"

        // When
        let date = dateString.dateValue

        // Then
        XCTAssertNotNil(date)

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.year, from: date!), 2024)
        XCTAssertEqual(calendar.component(.month, from: date!), 3)
        XCTAssertEqual(calendar.component(.day, from: date!), 15)
    }

    func testDateValue_invalidString_returnsNil() {
        // Given
        let invalidString = "15-03-2024" // Wrong format

        // When
        let date = invalidString.dateValue

        // Then
        XCTAssertNil(date)
    }
}
