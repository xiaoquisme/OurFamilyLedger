import Foundation
import UserNotifications
@testable import OurFamilyLedger

/// Mock Notification Service for testing
final class MockNotificationService: NotificationServiceProtocol {
    var authorizationStatus: UNAuthorizationStatus = .authorized
    var requestAuthorizationResult = true
    var scheduledReminders: [AccountingReminder] = []
    var cancelledReminders: [AccountingReminder] = []

    var requestAuthorizationCallCount = 0
    var scheduleReminderCallCount = 0
    var cancelReminderCallCount = 0
    var syncAllRemindersCallCount = 0

    func requestAuthorization() async -> Bool {
        requestAuthorizationCallCount += 1
        return requestAuthorizationResult
    }

    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        return authorizationStatus
    }

    func scheduleReminder(_ reminder: AccountingReminder) async {
        scheduleReminderCallCount += 1
        scheduledReminders.append(reminder)
    }

    func updateSingleReminder(_ reminder: AccountingReminder) async {
        cancelReminder(reminder)
        await scheduleReminder(reminder)
    }

    func cancelReminder(_ reminder: AccountingReminder) {
        cancelReminderCallCount += 1
        cancelledReminders.append(reminder)
        scheduledReminders.removeAll { $0.id == reminder.id }
    }

    func syncAllReminders(_ reminders: [AccountingReminder]) async {
        syncAllRemindersCallCount += 1
        scheduledReminders.removeAll()
        for reminder in reminders where reminder.isEnabled {
            await scheduleReminder(reminder)
        }
    }

    func cancelAllReminders() {
        scheduledReminders.removeAll()
    }

    // MARK: - Test Helpers

    func reset() {
        authorizationStatus = .authorized
        requestAuthorizationResult = true
        scheduledReminders.removeAll()
        cancelledReminders.removeAll()
        requestAuthorizationCallCount = 0
        scheduleReminderCallCount = 0
        cancelReminderCallCount = 0
        syncAllRemindersCallCount = 0
    }
}
