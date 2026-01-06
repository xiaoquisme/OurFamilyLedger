import SwiftUI
import SwiftData

struct FamilyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Member.createdAt) private var members: [Member]

    @State private var showingAddMember = false
    @State private var showingShareSheet = false
    @State private var selectedMember: Member?

    var body: some View {
        NavigationStack {
            List {
                // 账本信息
                Section("账本") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("家庭账本")
                                .font(.headline)
                            Text("本地账本")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            showingShareSheet = true
                        } label: {
                            Label("共享", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }

                // 成员列表
                Section("成员 (\(members.count))") {
                    ForEach(members) { member in
                        MemberRow(member: member)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMember = member
                            }
                    }
                    .onDelete(perform: deleteMembers)

                    Button {
                        showingAddMember = true
                    } label: {
                        Label("添加成员", systemImage: "plus")
                    }
                }

                // 角色说明
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("管理员")
                                    .font(.subheadline)
                                Text("可修改设置、导出数据、管理分类")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.orange)
                        }

                        Divider()

                        Label {
                            VStack(alignment: .leading) {
                                Text("成员")
                                    .font(.subheadline)
                                Text("可记账、查看、编辑交易")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("角色说明")
                }
            }
            .navigationTitle("家庭")
            .sheet(isPresented: $showingAddMember) {
                AddMemberView()
            }
            .sheet(item: $selectedMember) { member in
                EditMemberView(member: member)
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareLedgerView()
            }
        }
    }

    private func deleteMembers(at offsets: IndexSet) {
        for index in offsets {
            let member = members[index]
            // 不允许删除当前用户
            if !member.isCurrentUser {
                modelContext.delete(member)
            }
        }
    }
}

// MARK: - Member Row

struct MemberRow: View {
    let member: Member

    var body: some View {
        HStack(spacing: 12) {
            // 头像
            Circle()
                .fill(avatarColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(member.initials)
                        .font(.headline)
                        .foregroundStyle(avatarColor)
                }

            // 信息
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(member.displayName)
                        .font(.body)

                    if member.isCurrentUser {
                        Text("我")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                Text(member.role.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if member.role == .admin {
                Image(systemName: "star.fill")
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private var avatarColor: Color {
        switch member.avatarColor {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "red": return .red
        case "yellow": return .yellow
        case "teal": return .teal
        default: return .blue
        }
    }
}

// MARK: - Add Member View

struct AddMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var nickname = ""
    @State private var role: MemberRole = .member
    @State private var avatarColor = "blue"

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("姓名", text: $name)
                    TextField("昵称（可选）", text: $nickname)
                }

                Section("角色") {
                    Picker("角色", selection: $role) {
                        ForEach(MemberRole.allCases, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                }

                Section("头像颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(AvatarColor.allCases, id: \.self) { color in
                            Circle()
                                .fill(colorFor(color).opacity(0.3))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if avatarColor == color.rawValue {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(colorFor(color))
                                    }
                                }
                                .onTapGesture {
                                    avatarColor = color.rawValue
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("添加成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        addMember()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func colorFor(_ avatarColor: AvatarColor) -> Color {
        switch avatarColor {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .yellow: return .yellow
        case .teal: return .teal
        }
    }

    private func addMember() {
        let member = Member(
            name: name,
            nickname: nickname,
            role: role,
            avatarColor: avatarColor
        )
        modelContext.insert(member)
        dismiss()
    }
}

// MARK: - Edit Member View

struct EditMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let member: Member

    @State private var name: String
    @State private var nickname: String
    @State private var role: MemberRole
    @State private var avatarColor: String

    init(member: Member) {
        self.member = member
        _name = State(initialValue: member.name)
        _nickname = State(initialValue: member.nickname)
        _role = State(initialValue: member.role)
        _avatarColor = State(initialValue: member.avatarColor)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("姓名", text: $name)
                    TextField("昵称", text: $nickname)
                }

                Section("角色") {
                    Picker("角色", selection: $role) {
                        ForEach(MemberRole.allCases, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                }

                Section("头像颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(AvatarColor.allCases, id: \.self) { color in
                            Circle()
                                .fill(colorFor(color).opacity(0.3))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if avatarColor == color.rawValue {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(colorFor(color))
                                    }
                                }
                                .onTapGesture {
                                    avatarColor = color.rawValue
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("编辑成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveMember()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func colorFor(_ avatarColor: AvatarColor) -> Color {
        switch avatarColor {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .yellow: return .yellow
        case .teal: return .teal
        }
    }

    private func saveMember() {
        member.name = name
        member.nickname = nickname
        member.role = role
        member.avatarColor = avatarColor
        member.updatedAt = Date()
        dismiss()
    }
}

// MARK: - Share Ledger View

struct ShareLedgerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "icloud")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("共享账本")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("通过 iCloud 文件夹共享账本给家人，让多人同时记账。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    Button {
                        // TODO: 创建共享文件夹
                    } label: {
                        Label("创建共享账本", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        // TODO: 加入共享账本
                    } label: {
                        Label("加入已有账本", systemImage: "folder.badge.person.crop")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    FamilyView()
}
