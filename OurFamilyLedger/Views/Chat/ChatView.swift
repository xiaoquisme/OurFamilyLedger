import SwiftUI
import PhotosUI

struct ChatView: View {
    @State private var messageText = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var isProcessing = false
    @State private var pendingDrafts: [TransactionDraft] = []
    @State private var messages: [ChatMessage] = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 消息列表
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { message in
                                ChatMessageView(message: message)
                            }

                            // 待确认的交易卡片
                            ForEach(pendingDrafts) { draft in
                                TransactionDraftCard(
                                    draft: draft,
                                    onConfirm: { confirmDraft(draft) },
                                    onEdit: { editDraft(draft) },
                                    onDelete: { deleteDraft(draft) }
                                )
                            }

                            if isProcessing {
                                ProcessingIndicator()
                            }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        isInputFocused = false
                    }
                }

                Divider()

                // 输入区域
                ChatInputView(
                    text: $messageText,
                    selectedPhotos: $selectedPhotos,
                    selectedImages: $selectedImages,
                    isProcessing: isProcessing,
                    isInputFocused: $isInputFocused,
                    onSend: sendMessage
                )
            }
            .navigationTitle("记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !pendingDrafts.isEmpty {
                        Button("全部确认") {
                            confirmAllDrafts()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !messageText.isEmpty || !selectedImages.isEmpty else { return }

        let userMessage = ChatMessage(
            type: .user,
            text: messageText,
            images: selectedImages
        )
        messages.append(userMessage)

        let inputText = messageText
        let inputImages = selectedImages

        messageText = ""
        selectedPhotos = []
        selectedImages = []
        isProcessing = true

        // TODO: 调用 AI 服务解析
        Task {
            await processInput(text: inputText, images: inputImages)
        }
    }

    private func processInput(text: String, images: [UIImage]) async {
        // 模拟处理延迟
        try? await Task.sleep(for: .seconds(1))

        // TODO: 实际调用 OCR 和 AI 服务
        // 临时模拟：创建一个示例草稿
        if !text.isEmpty {
            let mockDraft = TransactionDraft(
                amount: 128.00,
                categoryName: "餐饮",
                payerName: "我",
                participantNames: ["我", "家人"],
                note: text,
                merchant: "",
                source: .text
            )

            await MainActor.run {
                pendingDrafts.append(mockDraft)
                isProcessing = false

                let assistantMessage = ChatMessage(
                    type: .assistant,
                    text: "已识别到一笔交易，请确认信息"
                )
                messages.append(assistantMessage)
            }
        } else {
            await MainActor.run {
                isProcessing = false
            }
        }
    }

    private func confirmDraft(_ draft: TransactionDraft) {
        // TODO: 保存到数据库
        pendingDrafts.removeAll { $0.id == draft.id }

        let message = ChatMessage(
            type: .system,
            text: "已入账: \(draft.categoryName) ¥\(draft.amount)"
        )
        messages.append(message)
    }

    private func confirmAllDrafts() {
        for draft in pendingDrafts {
            confirmDraft(draft)
        }
    }

    private func editDraft(_ draft: TransactionDraft) {
        // TODO: 打开编辑页面
    }

    private func deleteDraft(_ draft: TransactionDraft) {
        pendingDrafts.removeAll { $0.id == draft.id }
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id = UUID()
    let type: MessageType
    let text: String
    var images: [UIImage] = []
    let timestamp = Date()

    enum MessageType {
        case user
        case assistant
        case system
    }
}

// MARK: - Chat Message View

struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.type == .user {
                Spacer()
            }

            VStack(alignment: message.type == .user ? .trailing : .leading, spacing: 8) {
                // 图片
                if !message.images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(0..<message.images.count, id: \.self) { index in
                                Image(uiImage: message.images[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }

                // 文字
                if !message.text.isEmpty {
                    Text(message.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(backgroundColor)
                        .foregroundStyle(foregroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }

            if message.type != .user {
                Spacer()
            }
        }
    }

    private var backgroundColor: Color {
        switch message.type {
        case .user: return .blue
        case .assistant: return Color(.systemGray5)
        case .system: return Color(.systemGray6)
        }
    }

    private var foregroundColor: Color {
        switch message.type {
        case .user: return .white
        default: return .primary
        }
    }
}

// MARK: - Transaction Draft Card

struct TransactionDraftCard: View {
    let draft: TransactionDraft
    let onConfirm: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 头部
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.blue)
                Text("待确认交易")
                    .font(.headline)
                Spacer()

                if let confidence = draft.confidenceAmount, confidence < 0.8 {
                    Label("低置信度", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            // 交易信息
            VStack(spacing: 8) {
                InfoRow(label: "金额", value: "¥\(draft.amount)")
                InfoRow(label: "分类", value: draft.categoryName)
                InfoRow(label: "付款人", value: draft.payerName)
                InfoRow(label: "参与人", value: draft.participantNames.joined(separator: "、"))

                if !draft.note.isEmpty {
                    InfoRow(label: "备注", value: draft.note)
                }
                if !draft.merchant.isEmpty {
                    InfoRow(label: "商户", value: draft.merchant)
                }

                // 分摊金额
                Text("每人: ¥\(draft.splitAmount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Divider()

            // 操作按钮
            HStack(spacing: 12) {
                Button(action: onDelete) {
                    Label("删除", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button(action: onEdit) {
                    Label("编辑", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onConfirm) {
                    Label("确认", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
            Spacer()
        }
        .font(.subheadline)
    }
}

// MARK: - Chat Input View

struct ChatInputView: View {
    @Binding var text: String
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var selectedImages: [UIImage]
    let isProcessing: Bool
    var isInputFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // 已选图片预览
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<selectedImages.count, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: selectedImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                Button {
                                    selectedImages.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .gray)
                                }
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // 输入栏
            HStack(spacing: 12) {
                // 图片选择
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 9,
                    matching: .images
                ) {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .onChange(of: selectedPhotos) { _, newValue in
                    Task {
                        await loadImages(from: newValue)
                    }
                }

                // 文本输入
                TextField("输入记账内容或发送截图...", text: $text)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                    .focused(isInputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        if canSend && !isProcessing {
                            onSend()
                        }
                    }

                // 发送按钮
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(canSend ? .blue : .gray)
                }
                .disabled(!canSend || isProcessing)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    private var canSend: Bool {
        !text.isEmpty || !selectedImages.isEmpty
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        var images: [UIImage] = []

        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }

        await MainActor.run {
            selectedImages = images
        }
    }
}

// MARK: - Processing Indicator

struct ProcessingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("正在识别...")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ChatView()
}
