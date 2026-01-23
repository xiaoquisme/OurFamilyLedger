import SwiftUI
import SwiftData

struct RemindersListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AccountingReminder.createdAt) private var reminders: [AccountingReminder]

    @State private var showingAddReminder = false
    @State private var editingReminder: AccountingReminder?

    var body: some View {
        List {
            ForEach(reminders) { reminder in
                ReminderRow(reminder: reminder) {
                    editingReminder = reminder
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteReminder(reminder)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }

            if reminders.isEmpty {
                ContentUnavailableView(
                    "暂无提醒",
                    systemImage: "bell.slash",
                    description: Text("点击右上角添加记账提醒")
                )
            }
        }
        .navigationTitle("记账提醒")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddReminder = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddReminder) {
            ReminderEditView(reminder: nil) { newReminder in
                addReminder(newReminder)
            }
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderEditView(reminder: reminder) { updatedReminder in
                updateReminder(reminder, with: updatedReminder)
            }
        }
    }

    private func addReminder(_ reminder: AccountingReminder) {
        modelContext.insert(reminder)
        try? modelContext.save()
        Task {
            await NotificationService.shared.scheduleReminder(reminder)
        }
    }

    private func updateReminder(_ existing: AccountingReminder, with updated: AccountingReminder) {
        existing.hour = updated.hour
        existing.minute = updated.minute
        existing.message = updated.message
        existing.frequency = updated.frequency
        existing.isEnabled = updated.isEnabled
        existing.updatedAt = Date()
        try? modelContext.save()
        Task {
            await NotificationService.shared.updateSingleReminder(existing)
        }
    }

    private func deleteReminder(_ reminder: AccountingReminder) {
        NotificationService.shared.cancelReminder(reminder)
        modelContext.delete(reminder)
        try? modelContext.save()
    }
}

// MARK: - Reminder Row

struct ReminderRow: View {
    @Bindable var reminder: AccountingReminder
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(reminder.timeString)
                            .font(.title2)
                            .fontWeight(.medium)

                        Text(reminder.frequency.description)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }

                    Text(reminder.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Toggle("", isOn: $reminder.isEnabled)
                    .labelsHidden()
                    .onChange(of: reminder.isEnabled) { _, isEnabled in
                        Task {
                            if isEnabled {
                                await NotificationService.shared.scheduleReminder(reminder)
                            } else {
                                NotificationService.shared.cancelReminder(reminder)
                            }
                        }
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reminder Edit View

struct ReminderEditView: View {
    @Environment(\.dismiss) private var dismiss

    let reminder: AccountingReminder?
    let onSave: (AccountingReminder) -> Void

    @State private var hour: Int
    @State private var minute: Int
    @State private var message: String
    @State private var frequency: ReminderFrequency
    @State private var isEnabled: Bool

    private var isEditing: Bool { reminder != nil }

    init(reminder: AccountingReminder?, onSave: @escaping (AccountingReminder) -> Void) {
        self.reminder = reminder
        self.onSave = onSave
        _hour = State(initialValue: reminder?.hour ?? 14)
        _minute = State(initialValue: reminder?.minute ?? 0)
        _message = State(initialValue: reminder?.message ?? "记账时间到了，赶紧记一笔吧！")
        _frequency = State(initialValue: reminder?.frequency ?? .daily)
        _isEnabled = State(initialValue: reminder?.isEnabled ?? true)
    }

    private var selectedTime: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = hour
                components.minute = minute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                hour = components.hour ?? 14
                minute = components.minute ?? 0
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("时间") {
                    DatePicker("提醒时间", selection: selectedTime, displayedComponents: .hourAndMinute)
                }

                Section("频率") {
                    Picker("提醒频率", selection: $frequency) {
                        ForEach(ReminderFrequency.allCases, id: \.self) { freq in
                            Text(freq.description).tag(freq)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("内容") {
                    TextField("提醒内容", text: $message)
                }

                Section {
                    Toggle("启用提醒", isOn: $isEnabled)
                }
            }
            .navigationTitle(isEditing ? "编辑提醒" : "添加提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveReminder()
                    }
                    .disabled(message.isEmpty)
                }
            }
        }
    }

    private func saveReminder() {
        let newReminder = AccountingReminder(
            id: reminder?.id ?? UUID(),
            hour: hour,
            minute: minute,
            message: message,
            frequency: frequency,
            isEnabled: isEnabled,
            createdAt: reminder?.createdAt ?? Date(),
            updatedAt: Date()
        )
        onSave(newReminder)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        RemindersListView()
    }
    .modelContainer(for: AccountingReminder.self, inMemory: true)
}
