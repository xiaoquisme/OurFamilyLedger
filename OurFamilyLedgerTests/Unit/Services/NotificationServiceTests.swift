import XCTest
import UserNotifications
@testable import OurFamilyLedger

/// Tests for NotificationService using MockNotificationService
final class NotificationServiceTests: XCTestCase {

    var sut: MockNotificationService!

    override func setUp() {
        super.setUp()
        sut = MockNotificationService()
    }

    override func tearDown() {
        sut.reset()
        sut = nil
        super.tearDown()
    }

    // MARK: - Request Authorization Tests

    func testRequestAuthorization_returnsTrue_whenGranted() async {
        // Given
        sut.requestAuthorizationResult = true

        // When
        let result = await sut.requestAuthorization()

        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(sut.requestAuthorizationCallCount, 1)
    }

    func testRequestAuthorization_returnsFalse_whenDenied() async {
        // Given
        sut.requestAuthorizationResult = false

        // When
        let result = await sut.requestAuthorization()

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - Check Authorization Status Tests

    func testCheckAuthorizationStatus_returnsAuthorized() async {
        // Given
        sut.authorizationStatus = .authorized

        // When
        let result = await sut.checkAuthorizationStatus()

        // Then
        XCTAssertEqual(result, .authorized)
    }

    func testCheckAuthorizationStatus_returnsDenied() async {
        // Given
        sut.authorizationStatus = .denied

        // When
        let result = await sut.checkAuthorizationStatus()

        // Then
        XCTAssertEqual(result, .denied)
    }

    func testCheckAuthorizationStatus_returnsNotDetermined() async {
        // Given
        sut.authorizationStatus = .notDetermined

        // When
        let result = await sut.checkAuthorizationStatus()

        // Then
        XCTAssertEqual(result, .notDetermined)
    }

    // MARK: - Schedule Reminder Tests

    func testScheduleReminder_addsToScheduledReminders() async {
        // Given
        let reminder = createTestReminder()

        // When
        await sut.scheduleReminder(reminder)

        // Then
        XCTAssertEqual(sut.scheduledReminders.count, 1)
        XCTAssertEqual(sut.scheduledReminders.first?.id, reminder.id)
        XCTAssertEqual(sut.scheduleReminderCallCount, 1)
    }

    func testScheduleReminder_addsMultipleReminders() async {
        // Given
        let reminder1 = createTestReminder(hour: 8)
        let reminder2 = createTestReminder(hour: 12)
        let reminder3 = createTestReminder(hour: 20)

        // When
        await sut.scheduleReminder(reminder1)
        await sut.scheduleReminder(reminder2)
        await sut.scheduleReminder(reminder3)

        // Then
        XCTAssertEqual(sut.scheduledReminders.count, 3)
        XCTAssertEqual(sut.scheduleReminderCallCount, 3)
    }

    // MARK: - Cancel Reminder Tests

    func testCancelReminder_removesFromScheduled() async {
        // Given
        let reminder = createTestReminder()
        await sut.scheduleReminder(reminder)

        // When
        sut.cancelReminder(reminder)

        // Then
        XCTAssertTrue(sut.scheduledReminders.isEmpty)
        XCTAssertEqual(sut.cancelledReminders.count, 1)
        XCTAssertEqual(sut.cancelReminderCallCount, 1)
    }

    func testCancelReminder_onlyRemovesSpecificReminder() async {
        // Given
        let reminder1 = createTestReminder(hour: 8)
        let reminder2 = createTestReminder(hour: 12)
        await sut.scheduleReminder(reminder1)
        await sut.scheduleReminder(reminder2)

        // When
        sut.cancelReminder(reminder1)

        // Then
        XCTAssertEqual(sut.scheduledReminders.count, 1)
        XCTAssertEqual(sut.scheduledReminders.first?.hour, 12)
    }

    // MARK: - Update Single Reminder Tests

    func testUpdateSingleReminder_cancelsAndReschedules() async {
        // Given
        let reminder = createTestReminder(hour: 8)
        await sut.scheduleReminder(reminder)

        // When
        let updatedReminder = AccountingReminder(
            id: reminder.id,
            hour: 10,
            minute: 30,
            message: "Updated message",
            frequency: .daily,
            isEnabled: true
        )
        await sut.updateSingleReminder(updatedReminder)

        // Then
        XCTAssertEqual(sut.scheduledReminders.count, 1)
        XCTAssertEqual(sut.scheduledReminders.first?.hour, 10)
        XCTAssertEqual(sut.cancelReminderCallCount, 1)
    }

    // MARK: - Sync All Reminders Tests

    func testSyncAllReminders_replacesAllReminders() async {
        // Given
        let oldReminder = createTestReminder(hour: 8)
        await sut.scheduleReminder(oldReminder)

        let newReminders = [
            createTestReminder(hour: 9),
            createTestReminder(hour: 18)
        ]

        // When
        await sut.syncAllReminders(newReminders)

        // Then
        XCTAssertEqual(sut.scheduledReminders.count, 2)
        XCTAssertEqual(sut.syncAllRemindersCallCount, 1)
    }

    func testSyncAllReminders_onlySchedulesEnabledReminders() async {
        // Given
        let enabledReminder = createTestReminder(hour: 9, isEnabled: true)
        let disabledReminder = AccountingReminder(
            hour: 18,
            minute: 0,
            message: "Disabled",
            frequency: .daily,
            isEnabled: false
        )

        // When
        await sut.syncAllReminders([enabledReminder, disabledReminder])

        // Then
        XCTAssertEqual(sut.scheduledReminders.count, 1)
        XCTAssertEqual(sut.scheduledReminders.first?.hour, 9)
    }

    func testSyncAllReminders_clearsExistingBeforeSync() async {
        // Given
        await sut.scheduleReminder(createTestReminder(hour: 6))
        await sut.scheduleReminder(createTestReminder(hour: 7))
        XCTAssertEqual(sut.scheduledReminders.count, 2)

        // When
        await sut.syncAllReminders([createTestReminder(hour: 12)])

        // Then
        XCTAssertEqual(sut.scheduledReminders.count, 1)
        XCTAssertEqual(sut.scheduledReminders.first?.hour, 12)
    }

    // MARK: - Cancel All Reminders Tests

    func testCancelAllReminders_removesAllScheduled() async {
        // Given
        await sut.scheduleReminder(createTestReminder(hour: 8))
        await sut.scheduleReminder(createTestReminder(hour: 12))
        await sut.scheduleReminder(createTestReminder(hour: 20))

        // When
        sut.cancelAllReminders()

        // Then
        XCTAssertTrue(sut.scheduledReminders.isEmpty)
    }

    // MARK: - Reset Tests

    func testReset_clearsAllState() async {
        // Given
        sut.authorizationStatus = .denied
        sut.requestAuthorizationResult = false
        await sut.scheduleReminder(createTestReminder())
        sut.cancelReminder(createTestReminder())
        _ = await sut.requestAuthorization()
        await sut.syncAllReminders([])

        // When
        sut.reset()

        // Then
        XCTAssertEqual(sut.authorizationStatus, .authorized)
        XCTAssertTrue(sut.requestAuthorizationResult)
        XCTAssertTrue(sut.scheduledReminders.isEmpty)
        XCTAssertTrue(sut.cancelledReminders.isEmpty)
        XCTAssertEqual(sut.requestAuthorizationCallCount, 0)
        XCTAssertEqual(sut.scheduleReminderCallCount, 0)
        XCTAssertEqual(sut.cancelReminderCallCount, 0)
        XCTAssertEqual(sut.syncAllRemindersCallCount, 0)
    }

    // MARK: - Helper Methods

    private func createTestReminder(
        hour: Int = 14,
        minute: Int = 0,
        isEnabled: Bool = true
    ) -> AccountingReminder {
        AccountingReminder(
            hour: hour,
            minute: minute,
            message: "Test reminder",
            frequency: .daily,
            isEnabled: isEnabled
        )
    }
}

// MARK: - AccountingReminder Tests

final class AccountingReminderTests: XCTestCase {

    func testInit_setsDefaultValues() {
        // When
        let reminder = AccountingReminder(
            hour: 14,
            minute: 30,
            message: "Test",
            frequency: .daily,
            isEnabled: true
        )

        // Then
        XCTAssertEqual(reminder.hour, 14)
        XCTAssertEqual(reminder.minute, 30)
        XCTAssertEqual(reminder.message, "Test")
        XCTAssertEqual(reminder.frequency, .daily)
        XCTAssertTrue(reminder.isEnabled)
    }

    func testTimeString_formatsCorrectly() {
        // Given
        let reminder = AccountingReminder(
            hour: 8,
            minute: 5,
            message: "Morning",
            frequency: .daily,
            isEnabled: true
        )

        // Then
        XCTAssertEqual(reminder.timeString, "08:05")
    }

    func testTimeString_handlesAfternoon() {
        // Given
        let reminder = AccountingReminder(
            hour: 14,
            minute: 30,
            message: "Afternoon",
            frequency: .daily,
            isEnabled: true
        )

        // Then
        XCTAssertEqual(reminder.timeString, "14:30")
    }

    func testNotificationIdentifier_isConsistent() {
        // Given
        let id = UUID()
        let reminder = AccountingReminder(
            id: id,
            hour: 10,
            minute: 0,
            message: "Test",
            frequency: .daily,
            isEnabled: true
        )

        // Then
        XCTAssertEqual(reminder.notificationIdentifier, "accounting_reminder_\(id.uuidString)")
    }

    func testFrequency_daily() {
        // Given
        let reminder = AccountingReminder(
            hour: 10,
            minute: 0,
            message: "Test",
            frequency: .daily,
            isEnabled: true
        )

        // Then
        XCTAssertEqual(reminder.frequency, .daily)
    }

    func testFrequency_monthly() {
        // Given
        let reminder = AccountingReminder(
            hour: 10,
            minute: 0,
            message: "Test",
            frequency: .monthly,
            isEnabled: true
        )

        // Then
        XCTAssertEqual(reminder.frequency, .monthly)
    }
}
