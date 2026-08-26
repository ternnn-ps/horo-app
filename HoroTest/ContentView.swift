import SwiftUI

struct ContentView: View {
    @StateObject private var recordViewModel = RecordListViewModel()
    @StateObject private var profileViewModel = UserProfileViewModel()

    @State private var selectedTab: TellerTab = .chat
    @State private var editorMode: RecordEditorMode?
    @State private var isDeleteConfirmationPresented = false
    @State private var recordPendingDeletion: TestRecord?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ChatHomeView(profile: profileViewModel.profile)
                    .navigationTitle("Chat")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
            }
            .tag(TellerTab.chat)

            NavigationStack {
                DashboardPageView(
                    profile: profileViewModel.profile,
                    records: recordViewModel.records,
                    totalCount: recordViewModel.totalCount,
                    activeCount: recordViewModel.activeCount,
                    completedCount: recordViewModel.completedCount,
                    onViewProfile: { selectedTab = .profile },
                    onOpenChat: { selectedTab = .chat },
                    onCreateRecord: { editorMode = .create },
                    onEditRecord: { editorMode = .edit($0) },
                    onToggleRecord: { recordViewModel.toggleCompletion(for: $0) },
                    onDeleteRecord: { prepareDelete($0) }
                )
                .navigationTitle("Dashboard")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            editorMode = .create
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add Record")
                    }
                }
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.bar.xaxis")
            }
            .tag(TellerTab.dashboard)

            NavigationStack {
                ProfilePageView(
                    profileViewModel: profileViewModel,
                    totalCount: recordViewModel.totalCount,
                    activeCount: recordViewModel.activeCount,
                    completedCount: recordViewModel.completedCount,
                    onCreateRecord: { editorMode = .create }
                )
                .navigationTitle("Profile")
                .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle.fill")
            }
            .tag(TellerTab.profile)
        }
        .tint(.teal)
        .sheet(item: $editorMode) { mode in
            RecordEditorView(mode: mode) { title, notes in
                switch mode {
                case .create:
                    recordViewModel.create(title: title, notes: notes)
                case .edit(let record):
                    recordViewModel.update(record, title: title, notes: notes)
                }
            }
        }
        .confirmationDialog(
            "Delete Record",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible,
            presenting: recordPendingDeletion
        ) { record in
            Button("Delete Record", role: .destructive) {
                recordViewModel.delete(record)
                recordPendingDeletion = nil
            }

            Button("Cancel", role: .cancel) {
                recordPendingDeletion = nil
            }
        } message: { record in
            Text("Remove \"\(record.title)\" from this device?")
        }
    }

    private func prepareDelete(_ record: TestRecord) {
        recordPendingDeletion = record
        isDeleteConfirmationPresented = true
    }
}

private enum TellerTab {
    case chat
    case dashboard
    case profile
}

private enum AppColors {
    static var backgroundBase: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    static var surface: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    static var elevatedSurface: Color {
        Color(uiColor: .tertiarySystemGroupedBackground)
    }

    static var border: Color {
        Color(uiColor: .separator).opacity(0.26)
    }

    static var softFill: Color {
        Color(uiColor: .systemFill).opacity(0.42)
    }
}

private struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                AppColors.backgroundBase,
                Color.teal.opacity(0.08),
                Color.blue.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private enum OperationRole: String, CaseIterable, Identifiable {
    case teller
    case customer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .teller:
            return "Teller"
        case .customer:
            return "Customer"
        }
    }

    var subtitle: String {
        switch self {
        case .teller:
            return "Handles queue, chat, and service records"
        case .customer:
            return "Requests help and shares account context"
        }
    }

    var icon: String {
        switch self {
        case .teller:
            return "person.badge.shield.checkmark"
        case .customer:
            return "person.crop.circle.badge.questionmark"
        }
    }

    var tint: Color {
        switch self {
        case .teller:
            return .teal
        case .customer:
            return .indigo
        }
    }
}

private struct RoleOverviewSection: View {
    let activeRole: OperationRole

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Operation Roles",
                subtitle: "Teller workspace is active"
            )

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(OperationRole.allCases) { role in
                    OperationRoleCard(
                        role: role,
                        isActive: role == activeRole
                    )
                }
            }
        }
    }
}

private struct OperationRoleCard: View {
    let role: OperationRole
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: role.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(role.tint)

                Spacer()

                if isActive {
                    StatusBadge(title: "Active", color: .green)
                }
            }

            Text(role.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(role.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .padding(14)
        .cardStyle(borderColor: isActive ? role.tint.opacity(0.55) : AppColors.border)
    }
}

private struct ChatHomeView: View {
    let profile: UserProfile

    @State private var searchText = ""

    private let conversations = ChatConversation.mockConversations

    private var filteredConversations: [ChatConversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !query.isEmpty else {
            return conversations
        }

        return conversations.filter {
            $0.customerName.lowercased().contains(query)
                || $0.customerId.lowercased().contains(query)
                || $0.topic.lowercased().contains(query)
                || $0.lastMessage.text.lowercased().contains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ChatOperationsHeader(profile: profile)

                QueueMetricsRow(conversations: conversations)

                ConversationSearchField(text: $searchText)

                SectionHeader(
                    title: "Customer Queue",
                    subtitle: "\(filteredConversations.count) conversations"
                )

                LazyVStack(spacing: 12) {
                    ForEach(filteredConversations) { conversation in
                        NavigationLink {
                            MockChatDetailView(
                                conversation: conversation,
                                tellerName: profile.fullName,
                                tellerInitials: profile.initials
                            )
                        } label: {
                            InboxRow(conversation: conversation)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
    }
}

private struct ChatOperationsHeader: View {
    let profile: UserProfile

    var body: some View {
        HStack(spacing: 14) {
            ProfilePhotoView(profile: profile, size: 56)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Teller Desk")
                        .font(.headline)

                    StatusBadge(title: "Online", color: .green)
                }

                Text(profile.fullName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Customer support queue")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Image(systemName: "headphones.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.teal)
        }
        .padding(16)
        .cardStyle()
    }
}

private struct QueueMetricsRow: View {
    let conversations: [ChatConversation]

    private var waitingCount: Int {
        conversations.filter { $0.status == .waiting }.count
    }

    private var highPriorityCount: Int {
        conversations.filter { $0.priority != .normal }.count
    }

    var body: some View {
        HStack(spacing: 10) {
            QueueMetricTile(
                title: "Waiting",
                value: "\(waitingCount)",
                icon: "clock.badge.exclamationmark",
                color: .orange
            )

            QueueMetricTile(
                title: "Priority",
                value: "\(highPriorityCount)",
                icon: "exclamationmark.triangle.fill",
                color: .red
            )

            QueueMetricTile(
                title: "Open",
                value: "\(conversations.count)",
                icon: "bubble.left.and.bubble.right.fill",
                color: .blue
            )
        }
    }
}

private struct QueueMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)

            Text(value)
                .font(.title3.bold().monospacedDigit())

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(12)
        .cardStyle()
    }
}

private struct ConversationSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search customer or case", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.border)
        }
    }
}

private struct InboxRow: View {
    let conversation: ChatConversation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ConversationAvatar(conversation: conversation, size: 50)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(conversation.customerName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Circle().fill(Color.red))
                    }

                    Spacer(minLength: 8)

                    Text(conversation.waitTime)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(conversation.status.color)
                        .lineLimit(1)
                }

                Text("\(conversation.customerId) • \(conversation.topic)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(conversation.lastMessage.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    ConversationMetaChip(
                        title: conversation.status.title,
                        color: conversation.status.color,
                        icon: conversation.status.icon
                    )

                    ConversationMetaChip(
                        title: conversation.priority.title,
                        color: conversation.priority.color,
                        icon: conversation.priority.icon
                    )

                    ConversationMetaChip(
                        title: conversation.accountTier,
                        color: .blue,
                        icon: "creditcard"
                    )
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
        }
        .padding(14)
        .cardStyle(borderColor: conversation.priority == .normal ? AppColors.border : conversation.priority.color.opacity(0.35))
    }
}

private struct ConversationMetaChip: View {
    let title: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)

            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct MockChatDetailView: View {
    let conversation: ChatConversation
    let tellerName: String
    let tellerInitials: String

    @State private var messages: [ChatMessage]
    @State private var draft = ""

    init(conversation: ChatConversation, tellerName: String, tellerInitials: String) {
        self.conversation = conversation
        self.tellerName = tellerName
        self.tellerInitials = tellerInitials
        _messages = State(initialValue: conversation.messages)
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatCustomerHeader(conversation: conversation)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            ChatBubble(
                                message: message,
                                customerInitials: conversation.initials,
                                tellerInitials: tellerInitials
                            )
                            .id(message.id)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    scrollToLatestMessage(with: proxy)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToLatestMessage(with: proxy)
                }
            }

            ChatComposer(
                draft: $draft,
                quickReplies: conversation.quickReplies,
                onSend: sendMessage
            )
        }
        .background(AppBackground())
        .navigationTitle(conversation.customerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                } label: {
                    Image(systemName: "phone.fill")
                }
                .accessibilityLabel("Call Customer")

                Button {
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .accessibilityLabel("Resolve Conversation")
            }
        }
    }

    private func sendMessage() {
        let cleanDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanDraft.isEmpty else {
            return
        }

        messages.append(
            ChatMessage(
                sender: .teller,
                text: cleanDraft,
                timestamp: Date()
            )
        )

        draft = ""
    }

    private func scrollToLatestMessage(with proxy: ScrollViewProxy) {
        guard let id = messages.last?.id else {
            return
        }

        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }
}

private struct ChatCustomerHeader: View {
    let conversation: ChatConversation

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ConversationAvatar(conversation: conversation, size: 48)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(conversation.customerName)
                            .font(.headline)
                            .lineLimit(1)

                        ConversationMetaChip(
                            title: conversation.status.title,
                            color: conversation.status.color,
                            icon: conversation.status.icon
                        )
                    }

                    Text("\(conversation.customerId) • \(conversation.accountTier) customer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(conversation.topic)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                ConversationMetaChip(
                    title: conversation.priority.title,
                    color: conversation.priority.color,
                    icon: conversation.priority.icon
                )

                ConversationMetaChip(
                    title: conversation.waitTime,
                    color: .orange,
                    icon: "timer"
                )

                Spacer()

                Text(conversation.lastMessage.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 1)
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let customerInitials: String
    let tellerInitials: String

    var body: some View {
        switch message.sender {
        case .system:
            SystemMessageBubble(message: message)
        case .customer, .teller:
            ChatPartyBubble(
                message: message,
                customerInitials: customerInitials,
                tellerInitials: tellerInitials
            )
        }
    }
}

private struct ChatPartyBubble: View {
    let message: ChatMessage
    let customerInitials: String
    let tellerInitials: String

    private var isTeller: Bool {
        message.sender == .teller
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isTeller {
                Spacer(minLength: 52)
            } else {
                MiniAvatar(
                    initials: customerInitials,
                    color: .indigo
                )
            }

            VStack(alignment: isTeller ? .trailing : .leading, spacing: 5) {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(isTeller ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isTeller ? Color.teal : AppColors.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 4) {
                    if isTeller {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                    }

                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }

            if isTeller {
                MiniAvatar(
                    initials: tellerInitials,
                    color: .teal
                )
            } else {
                Spacer(minLength: 52)
            }
        }
    }
}

private struct SystemMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        Text(message.text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(AppColors.softFill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ChatComposer: View {
    @Binding var draft: String

    let quickReplies: [String]
    let onSend: () -> Void

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(quickReplies, id: \.self) { reply in
                        Button {
                            draft = reply
                        } label: {
                            Text(reply)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                } label: {
                    Image(systemName: "paperclip")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Attach File")

                TextField("Message customer", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColors.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onSubmit(onSend)

                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
                .accessibilityLabel("Send Message")
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 12)
        .background(AppColors.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 1)
        }
    }
}

private struct ChatMessage: Identifiable, Equatable {
    enum Sender {
        case customer
        case teller
        case system
    }

    let id: UUID
    let sender: Sender
    let text: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        sender: Sender,
        text: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
    }
}

private enum ConversationStatus {
    case waiting
    case active
    case followUp

    var title: String {
        switch self {
        case .waiting:
            return "Waiting"
        case .active:
            return "Active"
        case .followUp:
            return "Follow Up"
        }
    }

    var icon: String {
        switch self {
        case .waiting:
            return "clock"
        case .active:
            return "bolt.fill"
        case .followUp:
            return "arrow.triangle.2.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .waiting:
            return .orange
        case .active:
            return .green
        case .followUp:
            return .purple
        }
    }
}

private enum ConversationPriority: Equatable {
    case normal
    case high
    case vip

    var title: String {
        switch self {
        case .normal:
            return "Normal"
        case .high:
            return "High"
        case .vip:
            return "VIP"
        }
    }

    var icon: String {
        switch self {
        case .normal:
            return "flag"
        case .high:
            return "exclamationmark.triangle.fill"
        case .vip:
            return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .normal:
            return .secondary
        case .high:
            return .red
        case .vip:
            return .yellow
        }
    }
}

private struct ChatConversation: Identifiable {
    let id = UUID()
    let customerName: String
    let customerId: String
    let topic: String
    let status: ConversationStatus
    let priority: ConversationPriority
    let accountTier: String
    let waitTime: String
    let unreadCount: Int
    let tint: Color
    let messages: [ChatMessage]
    let quickReplies: [String]

    var initials: String {
        let value = customerName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()

        return value.isEmpty ? "C" : value
    }

    var lastMessage: ChatMessage {
        messages.last ?? ChatMessage(
            sender: .system,
            text: "No messages yet.",
            timestamp: Date()
        )
    }

    static let mockConversations = [
        ChatConversation(
            customerName: "Mali Chan",
            customerId: "C-1042",
            topic: "Transfer verification",
            status: .waiting,
            priority: .high,
            accountTier: "Gold",
            waitTime: "8m",
            unreadCount: 2,
            tint: .red,
            messages: [
                ChatMessage(
                    sender: .system,
                    text: "Customer verified by phone number and device check.",
                    timestamp: Date().addingTimeInterval(-820)
                ),
                ChatMessage(
                    sender: .customer,
                    text: "I cannot confirm the OTP for my transfer.",
                    timestamp: Date().addingTimeInterval(-760)
                ),
                ChatMessage(
                    sender: .teller,
                    text: "I can help. Please keep the app open while I review the request.",
                    timestamp: Date().addingTimeInterval(-700)
                ),
                ChatMessage(
                    sender: .customer,
                    text: "Thank you. The transfer is time sensitive.",
                    timestamp: Date().addingTimeInterval(-480)
                )
            ],
            quickReplies: [
                "I am checking that now.",
                "Please confirm the last 4 digits.",
                "I will stay with you until it is resolved."
            ]
        ),
        ChatConversation(
            customerName: "Niran K.",
            customerId: "C-2217",
            topic: "Card limit request",
            status: .active,
            priority: .vip,
            accountTier: "Premier",
            waitTime: "2m",
            unreadCount: 1,
            tint: .indigo,
            messages: [
                ChatMessage(
                    sender: .system,
                    text: "Customer has a verified Premier account.",
                    timestamp: Date().addingTimeInterval(-520)
                ),
                ChatMessage(
                    sender: .customer,
                    text: "Can you raise my card limit for travel today?",
                    timestamp: Date().addingTimeInterval(-460)
                ),
                ChatMessage(
                    sender: .teller,
                    text: "Yes, I am reviewing the available limit options.",
                    timestamp: Date().addingTimeInterval(-390)
                ),
                ChatMessage(
                    sender: .customer,
                    text: "Great. I need it before my flight.",
                    timestamp: Date().addingTimeInterval(-160)
                )
            ],
            quickReplies: [
                "I found the available options.",
                "This will take about 2 minutes.",
                "Please review the confirmation screen."
            ]
        ),
        ChatConversation(
            customerName: "Anya S.",
            customerId: "C-3098",
            topic: "New account onboarding",
            status: .followUp,
            priority: .normal,
            accountTier: "Standard",
            waitTime: "1h",
            unreadCount: 0,
            tint: .teal,
            messages: [
                ChatMessage(
                    sender: .customer,
                    text: "I uploaded my documents but still see pending.",
                    timestamp: Date().addingTimeInterval(-4100)
                ),
                ChatMessage(
                    sender: .teller,
                    text: "Your identity document is approved. The address document still needs review.",
                    timestamp: Date().addingTimeInterval(-3980)
                ),
                ChatMessage(
                    sender: .system,
                    text: "Follow-up reminder created for the address review.",
                    timestamp: Date().addingTimeInterval(-3840)
                )
            ],
            quickReplies: [
                "I checked the document status.",
                "Please upload one more address document.",
                "I will send a reminder."
            ]
        )
    ]
}

private struct ConversationAvatar: View {
    let conversation: ChatConversation
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(conversation.tint.opacity(0.18))

            Text(conversation.initials)
                .font(.system(size: size * 0.33, weight: .bold))
                .foregroundStyle(conversation.tint)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(conversation.status.color)
                .frame(width: size * 0.22, height: size * 0.22)
                .overlay {
                    Circle()
                        .stroke(Color(uiColor: .systemBackground), lineWidth: 2)
                }
        }
    }
}

private struct MiniAvatar: View {
    let initials: String
    let color: Color

    var body: some View {
        Text(initials)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(color.opacity(0.14))
            .clipShape(Circle())
    }
}

private struct DashboardPageView: View {
    let profile: UserProfile
    let records: [TestRecord]
    let totalCount: Int
    let activeCount: Int
    let completedCount: Int
    let onViewProfile: () -> Void
    let onOpenChat: () -> Void
    let onCreateRecord: () -> Void
    let onEditRecord: (TestRecord) -> Void
    let onToggleRecord: (TestRecord) -> Void
    let onDeleteRecord: (TestRecord) -> Void

    private let conversations = ChatConversation.mockConversations

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                TellerDashboardHeader(
                    profile: profile,
                    activeCount: activeCount,
                    onViewProfile: onViewProfile
                )

                RoleOverviewSection(activeRole: .teller)

                OperationsMetricsGrid(
                    queueCount: conversations.count,
                    activeCount: activeCount,
                    completedCount: completedCount
                )

                WorkQueuePreview(
                    conversations: Array(conversations.prefix(2)),
                    onOpenChat: onOpenChat
                )

                RecordsSectionHeader(onCreate: onCreateRecord)

                if records.isEmpty {
                    EmptyRecordsView(onCreate: onCreateRecord)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(records) { record in
                            RecordCard(
                                record: record,
                                onEdit: { onEditRecord(record) },
                                onToggle: { onToggleRecord(record) },
                                onDelete: { onDeleteRecord(record) }
                            )
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
    }
}

private struct TellerDashboardHeader: View {
    let profile: UserProfile
    let activeCount: Int
    let onViewProfile: () -> Void

    var body: some View {
        Button(action: onViewProfile) {
            HStack(spacing: 14) {
                ProfilePhotoView(profile: profile, size: 62)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Teller Operation")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        StatusBadge(title: "On Duty", color: .green)
                    }

                    Text(profile.fullName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.caption2)

                        Text("\(activeCount) active service records")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.teal)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

private struct OperationsMetricsGrid: View {
    let queueCount: Int
    let activeCount: Int
    let completedCount: Int

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            MetricTile(title: "Queue", value: queueCount, color: .blue, icon: "person.2.wave.2.fill")
            MetricTile(title: "Active", value: activeCount, color: .teal, icon: "timer")
            MetricTile(title: "Done", value: completedCount, color: .green, icon: "checkmark.seal")
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: Int
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)

            Text("\(value)")
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(.primary)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(12)
        .cardStyle()
    }
}

private struct WorkQueuePreview: View {
    let conversations: [ChatConversation]
    let onOpenChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(
                    title: "Priority Queue",
                    subtitle: "Customer cases needing teller action"
                )

                Spacer()

                Button(action: onOpenChat) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Open Chat")
            }

            LazyVStack(spacing: 10) {
                ForEach(conversations) { conversation in
                    QueuePreviewRow(conversation: conversation)
                }
            }
        }
    }
}

private struct QueuePreviewRow: View {
    let conversation: ChatConversation

    var body: some View {
        HStack(spacing: 12) {
            ConversationAvatar(conversation: conversation, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.customerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(conversation.topic)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            ConversationMetaChip(
                title: conversation.priority.title,
                color: conversation.priority.color,
                icon: conversation.priority.icon
            )
        }
        .padding(12)
        .cardStyle()
    }
}

private struct RecordsSectionHeader: View {
    let onCreate: () -> Void

    var body: some View {
        HStack {
            SectionHeader(
                title: "Service Records",
                subtitle: "Create, update, complete, or delete teller notes"
            )

            Spacer()

            Button(action: onCreate) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .accessibilityLabel("Add Record")
        }
        .padding(.top, 2)
    }
}

private struct EmptyRecordsView: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.blue)

            VStack(spacing: 6) {
                Text("No Records Yet")
                    .font(.title3.bold())

                Text("Add the first teller note for this mock operation.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onCreate) {
                Label("Add Record", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

private struct RecordCard: View {
    let record: TestRecord
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: record.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(record.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(record.isCompleted ? "Reopen Record" : "Complete Record")

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(record.title)
                            .font(.headline)
                            .foregroundStyle(record.isCompleted ? .secondary : .primary)
                            .strikethrough(record.isCompleted)
                            .lineLimit(2)

                        if record.isCompleted {
                            StatusBadge(title: "Done", color: .green)
                        }
                    }

                    if !record.notes.isEmpty {
                        Text(record.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption2)

                        Text(record.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                    }
                    .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }

                Button(action: onToggle) {
                    Label(
                        record.isCompleted ? "Reopen" : "Mark Done",
                        systemImage: record.isCompleted ? "arrow.uturn.left.circle" : "checkmark.circle"
                    )
                }

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("Record Actions")
        }
        .padding(14)
        .cardStyle(borderColor: record.isCompleted ? Color.green.opacity(0.35) : AppColors.border)
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }

            Button(action: onToggle) {
                Label(
                    record.isCompleted ? "Reopen" : "Mark Done",
                    systemImage: record.isCompleted ? "arrow.uturn.left.circle" : "checkmark.circle"
                )
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct ProfilePageView: View {
    @ObservedObject var profileViewModel: UserProfileViewModel

    let totalCount: Int
    let activeCount: Int
    let completedCount: Int
    let onCreateRecord: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ProfileHeroCard(profile: profileViewModel.profile)

                RoleOverviewSection(activeRole: .teller)

                ProfileContactSection(profile: profileViewModel.profile)

                ProfileActivitySection(
                    totalCount: totalCount,
                    activeCount: activeCount,
                    completedCount: completedCount,
                    onCreateRecord: onCreateRecord
                )

                ProfileSettingsSection()
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ProfileEditorView(
                        profile: profileViewModel.profile,
                        onSave: { profileViewModel.update(profile: $0) }
                    )
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit Profile")
            }
        }
    }
}

private struct ProfileHeroCard: View {
    let profile: UserProfile

    var body: some View {
        VStack(spacing: 14) {
            ProfilePhotoView(
                profile: profile,
                size: 110,
                showsCameraBadge: true
            )

            VStack(spacing: 5) {
                Text(profile.fullName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(profile.role)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    StatusBadge(title: "Teller", color: .teal)
                    StatusBadge(title: "On Duty", color: .green)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .cardStyle()
    }
}

private struct ProfileContactSection: View {
    let profile: UserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Contact", subtitle: "Teller profile detail")

            VStack(spacing: 0) {
                ProfileDetailRow(icon: "envelope", title: "Email", value: profile.email)
                Divider().padding(.leading, 40)
                ProfileDetailRow(icon: "phone", title: "Phone", value: profile.phone)
                Divider().padding(.leading, 40)
                ProfileDetailRow(icon: "location", title: "Location", value: profile.location)
            }
            .padding(.vertical, 4)
            .cardStyle()
        }
    }
}

private struct ProfileActivitySection: View {
    let totalCount: Int
    let activeCount: Int
    let completedCount: Int
    let onCreateRecord: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Activity", subtitle: "Local operation records")

                Spacer()

                Button(action: onCreateRecord) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Add Record")
            }

            VStack(spacing: 0) {
                ProfileDetailRow(icon: "square.stack.3d.up", title: "Total Records", value: "\(totalCount)")
                Divider().padding(.leading, 40)
                ProfileDetailRow(icon: "timer", title: "Active Records", value: "\(activeCount)")
                Divider().padding(.leading, 40)
                ProfileDetailRow(icon: "checkmark.seal", title: "Completed", value: "\(completedCount)")
            }
            .padding(.vertical, 4)
            .cardStyle()
        }
    }
}

private struct ProfileSettingsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Workspace", subtitle: "Mock teller preferences")

            VStack(spacing: 0) {
                ProfileDetailRow(icon: "bell.badge", title: "Queue Alerts", value: "Enabled")
                Divider().padding(.leading, 40)
                ProfileDetailRow(icon: "lock.shield", title: "Role Access", value: "Teller")
                Divider().padding(.leading, 40)
                ProfileDetailRow(icon: "moon.stars", title: "Appearance", value: "System")
            }
            .padding(.vertical, 4)
            .cardStyle()
        }
    }
}

private struct ProfileEditorView: View {
    let onSave: (UserProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fullName: String
    @State private var role: String
    @State private var email: String
    @State private var phone: String
    @State private var location: String

    private var canSave: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var draftProfile: UserProfile {
        UserProfile(
            fullName: fullName,
            role: role,
            email: email,
            phone: phone,
            location: location
        )
    }

    init(profile: UserProfile, onSave: @escaping (UserProfile) -> Void) {
        self.onSave = onSave
        _fullName = State(initialValue: profile.fullName)
        _role = State(initialValue: profile.role)
        _email = State(initialValue: profile.email)
        _phone = State(initialValue: profile.phone)
        _location = State(initialValue: profile.location)
    }

    var body: some View {
        Form {
            Section("Profile Picture") {
                HStack {
                    Spacer()
                    ProfilePhotoView(
                        profile: draftProfile,
                        size: 100,
                        showsCameraBadge: true
                    )
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            Section("Personal") {
                TextField("Full Name", text: $fullName)
                    .textInputAutocapitalization(.words)

                TextField("Role", text: $role)
                    .textInputAutocapitalization(.words)
            }

            Section("Contact") {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)

                TextField("Location", text: $location)
                    .textInputAutocapitalization(.words)
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(draftProfile)
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }
}

private struct ProfileDetailRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.teal)
                .frame(width: 24)

            Text(title)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value.isEmpty ? "Not set" : value)
                .fontWeight(.medium)
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct ProfilePhotoView: View {
    let profile: UserProfile
    let size: CGFloat
    var showsCameraBadge = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.teal, .blue, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Text(profile.initials)
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, size * 0.11)
                    .frame(height: size * 0.24)
                    .background(Color.black.opacity(0.22))
                    .clipShape(Capsule())
                    .offset(y: size * 0.28)
            }
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .stroke(Color(uiColor: .systemBackground).opacity(0.8), lineWidth: 2)
            }

            if showsCameraBadge {
                Image(systemName: "camera.fill")
                    .font(.system(size: size * 0.14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .background(Circle().fill(Color.teal))
                    .overlay {
                        Circle()
                            .stroke(Color(uiColor: .systemBackground), lineWidth: 2)
                    }
            }
        }
        .accessibilityLabel("Profile Picture")
    }
}

private struct StatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.bold())

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private enum RecordEditorMode: Identifiable {
    case create
    case edit(TestRecord)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let record):
            return record.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .create:
            return "New Record"
        case .edit:
            return "Edit Record"
        }
    }

    var record: TestRecord? {
        switch self {
        case .create:
            return nil
        case .edit(let record):
            return record
        }
    }
}

private struct RecordEditorView: View {
    let mode: RecordEditorMode
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(mode: RecordEditorMode, onSave: @escaping (String, String) -> Void) {
        self.mode = mode
        self.onSave = onSave
        _title = State(initialValue: mode.record?.title ?? "")
        _notes = State(initialValue: mode.record?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.sentences)

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title, notes)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

private extension View {
    func cardStyle(borderColor: Color = AppColors.border) -> some View {
        background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

#Preview("Light") {
    ContentView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView()
        .preferredColorScheme(.dark)
}
