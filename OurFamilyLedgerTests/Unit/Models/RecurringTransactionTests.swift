import XCTest
@testable import OurFamilyLedger

final class RecurringTransactionTests: XCTestCase {
    
    // MARK: - Daily Recurrence Tests
    
    func testDailyRecurrence_ShouldExecuteOnFirstDay() {
        let recurring = RecurringTransaction(
            name: "每日通勤",
            amount: 10,
            frequency: .daily,
            interval: 1
        )
        
        XCTAssertTrue(recurring.shouldExecuteToday(), "Daily recurring should execute on first day")
    }
    
    func testDailyRecurrence_WithInterval() {
        var recurring = RecurringTransaction(
            name: "每两天一次",
            amount: 10,
            frequency: .daily,
            interval: 2
        )
        
        // 模拟昨天执行过
        recurring.lastExecutedDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        XCTAssertFalse(recurring.shouldExecuteToday(), "Should not execute when only 1 day passed for 2-day interval")
        
        // 模拟两天前执行过
        recurring.lastExecutedDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())
        XCTAssertTrue(recurring.shouldExecuteToday(), "Should execute when 2 days have passed")
    }
    
    // MARK: - Weekly Recurrence Tests
    
    func testWeeklyRecurrence_SingleWeekday() {
        let calendar = Calendar.current
        let today = Date()
        let currentWeekday = calendar.component(.weekday, from: today)
        let currentWeekdayIndex = (currentWeekday + 6) % 7  // Convert to 0-6 format
        
        let recurring = RecurringTransaction(
            name: "每周任务",
            amount: 10,
            frequency: .weekly,
            interval: 1,
            weekday: currentWeekdayIndex,
            weekdays: [currentWeekdayIndex]
        )
        
        XCTAssertTrue(recurring.shouldExecuteToday(), "Should execute on the correct weekday")
    }
    
    func testWeeklyRecurrence_MultipleWeekdays() {
        let calendar = Calendar.current
        let today = Date()
        let currentWeekday = calendar.component(.weekday, from: today)
        let currentWeekdayIndex = (currentWeekday + 6) % 7
        
        // 包含今天的星期
        let recurring = RecurringTransaction(
            name: "周一和周三任务",
            amount: 10,
            frequency: .weekly,
            interval: 1,
            weekdays: [currentWeekdayIndex, (currentWeekdayIndex + 1) % 7]
        )
        
        XCTAssertTrue(recurring.shouldExecuteToday(), "Should execute when today is in weekdays list")
    }
    
    // MARK: - Monthly Recurrence Tests
    
    func testMonthlyRecurrence() {
        let calendar = Calendar.current
        let today = Date()
        let currentDay = calendar.component(.day, from: today)
        
        let recurring = RecurringTransaction(
            name: "每月账单",
            amount: 100,
            frequency: .monthly,
            interval: 1,
            dayOfMonth: currentDay
        )
        
        XCTAssertTrue(recurring.shouldExecuteToday(), "Should execute on the correct day of month")
    }
    
    // MARK: - Yearly Recurrence Tests
    
    func testYearlyRecurrence() {
        let calendar = Calendar.current
        let today = Date()
        let currentMonth = calendar.component(.month, from: today)
        let currentDay = calendar.component(.day, from: today)
        
        let recurring = RecurringTransaction(
            name: "年度订阅",
            amount: 1000,
            frequency: .yearly,
            interval: 1,
            dayOfMonth: currentDay,
            monthOfYear: currentMonth
        )
        
        XCTAssertTrue(recurring.shouldExecuteToday(), "Should execute on the correct date each year")
    }
    
    // MARK: - Auto Add Tests
    
    func testAutoAddProperty() {
        let autoRecurring = RecurringTransaction(
            name: "自动记账",
            amount: 10,
            autoAdd: true
        )
        
        XCTAssertTrue(autoRecurring.autoAdd, "AutoAdd should be set to true")
        
        let manualRecurring = RecurringTransaction(
            name: "手动确认",
            amount: 10,
            autoAdd: false
        )
        
        XCTAssertFalse(manualRecurring.autoAdd, "AutoAdd should be set to false")
    }
    
    // MARK: - End Date Tests
    
    func testEndDate_BeforeEndDate() {
        var recurring = RecurringTransaction(
            name: "限期任务",
            amount: 10,
            frequency: .daily,
            endDate: Calendar.current.date(byAdding: .day, value: 7, to: Date())
        )
        recurring.lastExecutedDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        
        XCTAssertTrue(recurring.shouldExecuteToday(), "Should execute before end date")
    }
    
    func testEndDate_AfterEndDate() {
        let recurring = RecurringTransaction(
            name: "已过期任务",
            amount: 10,
            frequency: .daily,
            endDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())
        )
        
        XCTAssertFalse(recurring.shouldExecuteToday(), "Should not execute after end date")
    }
    
    // MARK: - Occurrence Count Tests
    
    func testOccurrenceCount_BelowLimit() {
        var recurring = RecurringTransaction(
            name: "限次任务",
            amount: 10,
            frequency: .daily,
            occurrenceCount: 5
        )
        recurring.executedCount = 3
        
        XCTAssertTrue(recurring.shouldExecuteToday(), "Should execute when below occurrence limit")
    }
    
    func testOccurrenceCount_AtLimit() {
        var recurring = RecurringTransaction(
            name: "已达限次",
            amount: 10,
            frequency: .daily,
            occurrenceCount: 5
        )
        recurring.executedCount = 5
        
        XCTAssertFalse(recurring.shouldExecuteToday(), "Should not execute when at occurrence limit")
    }
    
    // MARK: - Recurrence Description Tests
    
    func testRecurrenceDescription_Daily() {
        let recurring = RecurringTransaction(
            name: "Test",
            amount: 10,
            frequency: .daily,
            interval: 1
        )
        
        XCTAssertEqual(recurring.recurrenceDescription, "每天")
    }
    
    func testRecurrenceDescription_DailyWithInterval() {
        let recurring = RecurringTransaction(
            name: "Test",
            amount: 10,
            frequency: .daily,
            interval: 3
        )
        
        XCTAssertEqual(recurring.recurrenceDescription, "每3天")
    }
    
    func testRecurrenceDescription_Weekly() {
        let recurring = RecurringTransaction(
            name: "Test",
            amount: 10,
            frequency: .weekly,
            interval: 1,
            weekdays: [1, 3, 5]
        )
        
        XCTAssertTrue(recurring.recurrenceDescription.contains("周一"))
        XCTAssertTrue(recurring.recurrenceDescription.contains("周三"))
        XCTAssertTrue(recurring.recurrenceDescription.contains("周五"))
    }
    
    func testRecurrenceDescription_Monthly() {
        let recurring = RecurringTransaction(
            name: "Test",
            amount: 10,
            frequency: .monthly,
            interval: 1,
            dayOfMonth: 15
        )
        
        XCTAssertEqual(recurring.recurrenceDescription, "每月（15号）")
    }
    
    func testRecurrenceDescription_Yearly() {
        let recurring = RecurringTransaction(
            name: "Test",
            amount: 10,
            frequency: .yearly,
            interval: 1,
            dayOfMonth: 25,
            monthOfYear: 12
        )
        
        XCTAssertEqual(recurring.recurrenceDescription, "每年（12月25日）")
    }
    
    // MARK: - Disabled Tests
    
    func testDisabled_ShouldNotExecute() {
        var recurring = RecurringTransaction(
            name: "已禁用",
            amount: 10,
            frequency: .daily
        )
        recurring.isEnabled = false
        
        XCTAssertFalse(recurring.shouldExecuteToday(), "Disabled recurring should not execute")
    }
}
