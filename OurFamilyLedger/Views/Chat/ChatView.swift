import SwiftUI
import SwiftData
import PhotosUI
import Photos

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = ChatViewModel()

    @State private var messageText = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var editingDraft: TransactionDraft?
    @FocusState private var isInputFocused: Bool

    // 最近截图提示
    @State private var recentScreenshot: UIImage?
    @State private var recentScreenshotAsset: PHAsset?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 消息列表
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                ChatMessageView(message: message)
                            }

                            // 待确认的交易卡片
                            ForEach(viewModel.pendingDrafts) { draft in
                                TransactionDraftCard(
                                    draft: draft,
                                    onConfirm: { confirmDraft(draft) },
                                    onEdit: { editingDraft = draft },
                                    onDelete: { viewModel.deleteDraft(draft) }
                                )
                            }

                            if viewModel.isProcessing {
                                ProcessingIndicator()
                            }

                            // 重试按钮
                            if viewModel.canRetry && !viewModel.isProcessing {
                                RetryButton {
                                    Task {
                                        await viewModel.retry()
                                    }
                                }
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
                    isProcessing: viewModel.isProcessing,
                    isInputFocused: $isInputFocused,
                    recentScreenshot: $recentScreenshot,
                    onSend: sendMessage,
                    onUseScreenshot: useRecentScreenshot
                )
            }
            .navigationTitle("记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.pendingDrafts.isEmpty {
                        Button("全部确认") {
                            Task {
                                await viewModel.confirmAllDrafts()
                            }
                        }
                    }
                }
            }
            .onAppear {
                viewModel.configure(modelContext: modelContext)
                checkForRecentScreenshot()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    checkForRecentScreenshot()
                }
            }
            .sheet(item: $editingDraft) { draft in
                EditDraftView(draft: draft) { updatedDraft in
                    viewModel.updateDraft(draft, with: updatedDraft)
                }
            }
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !messageText.isEmpty || !selectedImages.isEmpty else { return }

        let inputText = messageText
        let inputImages = selectedImages

        messageText = ""
        selectedPhotos = []
        selectedImages = []

        Task {
            await viewModel.processInput(text: inputText, images: inputImages)
        }
    }

    private func confirmDraft(_ draft: TransactionDraft) {
        Task {
            await viewModel.confirmDraft(draft)
        }
    }

    // MARK: - Screenshot Detection

    private func checkForRecentScreenshot() {
        // 请求相册权限
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            guard status == .authorized || status == .limited else { return }

            DispatchQueue.main.async {
                fetchRecentScreenshot()
            }
        }
    }

    private func fetchRecentScreenshot() {
        let fetchOptions = PHFetchOptions()
        // 只获取截图，按创建时间倒序
        fetchOptions.predicate = NSPredicate(
            format: "(mediaSubtype & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        guard let asset = assets.firstObject,
              let creationDate = asset.creationDate else {
            recentScreenshot = nil
            recentScreenshotAsset = nil
            return
        }

        // 只显示最近 2 分钟内的截图
        let twoMinutesAgo = Date().addingTimeInterval(-120)
        guard creationDate > twoMinutesAgo else {
            recentScreenshot = nil
            recentScreenshotAsset = nil
            return
        }

        // 获取缩略图
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isSynchronous = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 100, height: 100),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                self.recentScreenshot = image
                self.recentScreenshotAsset = asset
            }
        }
    }

    private func useRecentScreenshot() {
        guard let asset = recentScreenshotAsset else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .default,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                if let image = image {
                    self.selectedImages.append(image)
                }
                self.recentScreenshot = nil
                self.recentScreenshotAsset = nil
            }
        }
    }
}

// MARK: - Edit Draft View

struct EditDraftView: View {
    @Environment(\.dismiss) private var dismiss
    let draft: TransactionDraft
    let onSave: (TransactionDraft) -> Void

    @State private var amount: String
    @State private var categoryName: String
    @State private var payerName: String
    @State private var participantsText: String
    @State private var note: String
    @State private var merchant: String
    @State private var transactionType: TransactionType
    @State private var date: Date

    init(draft: TransactionDraft, onSave: @escaping (TransactionDraft) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _amount = State(initialValue: "\(draft.amount)")
        _categoryName = State(initialValue: draft.categoryName)
        _payerName = State(initialValue: draft.payerName)
        _participantsText = State(initialValue: draft.participantNames.joined(separator: "、"))
        _note = State(initialValue: draft.note)
        _merchant = State(initialValue: draft.merchant)
        _transactionType = State(initialValue: draft.type)
        _date = State(initialValue: draft.date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    HStack {
                        Text("金额")
                        Spacer()
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    Picker("类型", selection: $transactionType) {
                        Text("支出").tag(TransactionType.expense)
                        Text("收入").tag(TransactionType.income)
                    }

                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }

                Section("分类") {
                    TextField("分类名称", text: $categoryName)
                }

                Section("人员") {
                    TextField("付款人", text: $payerName)
                    TextField("参与人（用顿号分隔）", text: $participantsText)
                }

                Section("其他") {
                    TextField("商户", text: $merchant)
                    TextField("备注", text: $note)
                }
            }
            .navigationTitle("编辑交易")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveDraft()
                    }
                }
            }
        }
    }

    private func saveDraft() {
        let participants = participantsText
            .components(separatedBy: CharacterSet(charactersIn: "、,，"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let updatedDraft = TransactionDraft(
            id: draft.id,
            date: date,
            amount: Decimal(string: amount) ?? draft.amount,
            type: transactionType,
            categoryName: categoryName,
            payerName: payerName,
            participantNames: participants,
            note: note,
            merchant: merchant,
            source: draft.source,
            ocrText: draft.ocrText,
            confidenceAmount: 1.0,
            confidenceDate: 1.0
        )

        onSave(updatedDraft)
        dismiss()
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
    @State private var showImagePreview = false
    @State private var selectedImageIndex = 0

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
                                    .onTapGesture {
                                        selectedImageIndex = index
                                        showImagePreview = true
                                    }
                            }
                        }
                    }
                    .fullScreenCover(isPresented: $showImagePreview) {
                        ImagePreviewView(
                            images: message.images,
                            currentIndex: $selectedImageIndex
                        )
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
                InfoRow(label: "日期", value: draft.date.formatted(date: .numeric, time: .omitted))
                InfoRow(label: "金额", value: "¥\(NSDecimalNumber(decimal: draft.amount).doubleValue)")
                InfoRow(label: "类型", value: draft.type.rawValue)
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
    @Binding var recentScreenshot: UIImage?
    let onSend: () -> Void
    let onUseScreenshot: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // 最近截图提示
            if let screenshot = recentScreenshot {
                HStack(spacing: 8) {
                    Image(uiImage: screenshot)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.blue, lineWidth: 2)
                        )

                    Text("发送刚刚截的图？")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        onUseScreenshot()
                    } label: {
                        Text("使用")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    Button {
                        recentScreenshot = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.gray)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

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

// MARK: - Retry Button

struct RetryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                Text("重试")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.orange)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Image Preview View

struct ImagePreviewView: View {
    let images: [UIImage]
    @Binding var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(0..<images.count, id: \.self) { index in
                    Image(uiImage: images[index])
                        .resizable()
                        .scaledToFit()
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))

            // 顶部关闭按钮
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .white.opacity(0.3))
                }
                .padding()
            }

            // 底部页码
            if images.count > 1 {
                VStack {
                    Spacer()
                    Text("\(currentIndex + 1) / \(images.count)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.bottom, 40)
                }
            }
        }
    }
}

#Preview {
    ChatView()
}
