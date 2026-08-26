import SwiftUI

struct ContentView: View {
    @StateObject private var recordViewModel = RecordListViewModel()
    @StateObject private var profileViewModel = UserProfileViewModel()

    @State private var sessionRole: OperationRole?
    @State private var selectedSeerTab: SeerTab = .chat
    @State private var selectedCustomerTab: CustomerTab = .home
    @State private var editorMode: RecordEditorMode?
    @State private var isDeleteConfirmationPresented = false
    @State private var recordPendingDeletion: TestRecord?

    var body: some View {
        Group {
            switch sessionRole {
            case .seer:
                SeerWorkspaceView(
                    selectedTab: $selectedSeerTab,
                    profileViewModel: profileViewModel,
                    recordViewModel: recordViewModel,
                    onCreateRecord: { editorMode = .create },
                    onEditRecord: { editorMode = .edit($0) },
                    onDeleteRecord: { prepareDelete($0) },
                    onLogout: logout
                )
            case .customer:
                CustomerWorkspaceView(
                    selectedTab: $selectedCustomerTab,
                    onLogout: logout
                )
            case nil:
                LoginView { role in
                    sessionRole = role
                }
            }
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

    private func logout() {
        sessionRole = nil
        selectedSeerTab = .chat
        selectedCustomerTab = .home
        editorMode = nil
        recordPendingDeletion = nil
    }
}

private struct SeerWorkspaceView: View {
    @Binding var selectedTab: SeerTab

    @ObservedObject var profileViewModel: UserProfileViewModel
    @ObservedObject var recordViewModel: RecordListViewModel

    let onCreateRecord: () -> Void
    let onEditRecord: (TestRecord) -> Void
    let onDeleteRecord: (TestRecord) -> Void
    let onLogout: () -> Void

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ChatHomeView(profile: profileViewModel.profile)
                    .navigationTitle("Chat")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        logoutToolbarItem
                    }
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
            }
            .tag(SeerTab.chat)

            NavigationStack {
                DashboardPageView(
                    profile: profileViewModel.profile,
                    records: recordViewModel.records,
                    totalCount: recordViewModel.totalCount,
                    activeCount: recordViewModel.activeCount,
                    completedCount: recordViewModel.completedCount,
                    onViewProfile: { selectedTab = .profile },
                    onOpenChat: { selectedTab = .chat },
                    onCreateRecord: onCreateRecord,
                    onEditRecord: onEditRecord,
                    onToggleRecord: { recordViewModel.toggleCompletion(for: $0) },
                    onDeleteRecord: onDeleteRecord
                )
                .navigationTitle("Dashboard")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    logoutToolbarItem

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onCreateRecord) {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add Record")
                    }
                }
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.bar.xaxis")
            }
            .tag(SeerTab.dashboard)

            NavigationStack {
                ProfilePageView(
                    profileViewModel: profileViewModel,
                    totalCount: recordViewModel.totalCount,
                    activeCount: recordViewModel.activeCount,
                    completedCount: recordViewModel.completedCount,
                    onCreateRecord: onCreateRecord,
                    onLogout: onLogout
                )
                .navigationTitle("Profile")
                .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle.fill")
            }
            .tag(SeerTab.profile)
        }
    }

    @ToolbarContentBuilder
    private var logoutToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onLogout) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
            }
            .accessibilityLabel("Log Out")
        }
    }
}

private struct CustomerWorkspaceView: View {
    @Binding var selectedTab: CustomerTab

    let onLogout: () -> Void

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CustomerHomeView(onOpenChat: { selectedTab = .chat })
                    .navigationTitle("Home")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Label("Home", systemImage: "sparkles")
            }
            .tag(CustomerTab.home)

            NavigationStack {
                CustomerChatSpaceView()
                    .navigationTitle("Chat")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
            }
            .tag(CustomerTab.chat)

            NavigationStack {
                CustomerProfileSpaceView(onLogout: onLogout)
                    .navigationTitle("Profile")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle.fill")
            }
            .tag(CustomerTab.profile)
        }
    }
}

private enum SeerTab {
    case chat
    case dashboard
    case profile
}

private enum CustomerTab {
    case home
    case chat
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
    case seer
    case customer

    var id: String { rawValue }

    var loginKeyword: String { rawValue }

    var title: String {
        switch self {
        case .seer:
            return "Seer"
        case .customer:
            return "Customer"
        }
    }

    var subtitle: String {
        switch self {
        case .seer:
            return "Handles readings, chat queue, and session notes"
        case .customer:
            return "Requests guidance, chats, and tracks readings"
        }
    }

    var icon: String {
        switch self {
        case .seer:
            return "person.badge.shield.checkmark"
        case .customer:
            return "person.crop.circle.badge.questionmark"
        }
    }

    var tint: Color {
        switch self {
        case .seer:
            return .teal
        case .customer:
            return .indigo
        }
    }
}

private struct LoginView: View {
    let onLogin: (OperationRole) -> Void

    @State private var loginText = ""
    @State private var password = ""
    @State private var validationMessage: String?

    private var requestedRole: OperationRole? {
        let value = loginText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return OperationRole.allCases.first { $0.loginKeyword == value }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    LoginHero()

                    VStack(spacing: 12) {
                        TextField("Type seer or customer", text: $loginText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(AppColors.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        SecureField("Password optional", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(AppColors.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        if let validationMessage {
                            Text(validationMessage)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: submit) {
                            Label(
                                requestedRole.map { "Login as \($0.title)" } ?? "Login",
                                systemImage: "arrow.right.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding(16)
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "Choose Role",
                            subtitle: "Tap a role or type its keyword"
                        )

                        ForEach(OperationRole.allCases) { role in
                            Button {
                                loginText = role.loginKeyword
                                validationMessage = nil
                            } label: {
                                LoginRoleCard(
                                    role: role,
                                    isSelected: requestedRole == role
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Horo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func submit() {
        guard let role = requestedRole else {
            validationMessage = "Use \"seer\" or \"customer\" to enter this mock app."
            return
        }

        validationMessage = nil
        onLogin(role)
    }
}

private struct LoginHero: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.teal, .indigo, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 86, height: 86)

                Image(systemName: "sparkles")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text("Horo")
                    .font(.largeTitle.bold())

                Text("Mock role login for seer and customer spaces")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

private struct LoginRoleCard: View {
    let role: OperationRole
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(role.tint.opacity(0.14))

                Image(systemName: role.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(role.tint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                Text(role.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(role.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(role.loginKeyword)
                .font(.caption.weight(.bold))
                .foregroundStyle(role.tint)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(role.tint.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(14)
        .cardStyle(borderColor: isSelected ? role.tint.opacity(0.55) : AppColors.border)
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
                subtitle: "Seer workspace is active"
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
                                seerName: profile.fullName,
                                seerInitials: profile.initials
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
                    Text("Seer Desk")
                        .font(.headline)

                    StatusBadge(title: "Online", color: .green)
                }

                Text(profile.fullName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Customer reading queue")
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

    let placeholder: String

    init(text: Binding<String>, placeholder: String = "Search customer or reading") {
        _text = text
        self.placeholder = placeholder
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
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
                        icon: "sparkles"
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
    let seerName: String
    let seerInitials: String

    @State private var messages: [ChatMessage]
    @State private var draft = ""

    init(conversation: ChatConversation, seerName: String, seerInitials: String) {
        self.conversation = conversation
        self.seerName = seerName
        self.seerInitials = seerInitials
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
                                seerInitials: seerInitials
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
                placeholder: "Message customer",
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
                sender: .seer,
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

                    Text("\(conversation.customerId) • \(conversation.accountTier) member")
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
    let seerInitials: String

    var body: some View {
        switch message.sender {
        case .system:
            SystemMessageBubble(message: message)
        case .customer, .seer:
            ChatPartyBubble(
                message: message,
                customerInitials: customerInitials,
                seerInitials: seerInitials
            )
        }
    }
}

private struct ChatPartyBubble: View {
    let message: ChatMessage
    let customerInitials: String
    let seerInitials: String

    private var isSeer: Bool {
        message.sender == .seer
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isSeer {
                Spacer(minLength: 52)
            } else {
                MiniAvatar(
                    initials: customerInitials,
                    color: .indigo
                )
            }

            VStack(alignment: isSeer ? .trailing : .leading, spacing: 5) {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(isSeer ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isSeer ? Color.teal : AppColors.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 4) {
                    if isSeer {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                    }

                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }

            if isSeer {
                MiniAvatar(
                    initials: seerInitials,
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

    let placeholder: String
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

                TextField(placeholder, text: $draft, axis: .vertical)
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
        case seer
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
            topic: "Relationship timing",
            status: .waiting,
            priority: .high,
            accountTier: "Gold",
            waitTime: "8m",
            unreadCount: 2,
            tint: .purple,
            messages: [
                ChatMessage(
                    sender: .system,
                    text: "Customer shared birth time and relationship focus.",
                    timestamp: Date().addingTimeInterval(-820)
                ),
                ChatMessage(
                    sender: .customer,
                    text: "I want to know if this is the right moment to reconnect.",
                    timestamp: Date().addingTimeInterval(-760)
                ),
                ChatMessage(
                    sender: .seer,
                    text: "I can help. I am checking the timing and emotional pattern now.",
                    timestamp: Date().addingTimeInterval(-700)
                ),
                ChatMessage(
                    sender: .customer,
                    text: "Thank you. I can add more context if needed.",
                    timestamp: Date().addingTimeInterval(-480)
                )
            ],
            quickReplies: [
                "I am reading that now.",
                "Please share one more detail.",
                "I will guide you step by step."
            ]
        ),
        ChatConversation(
            customerName: "Niran K.",
            customerId: "C-2217",
            topic: "Career direction",
            status: .active,
            priority: .vip,
            accountTier: "Premier",
            waitTime: "2m",
            unreadCount: 1,
            tint: .indigo,
            messages: [
                ChatMessage(
                    sender: .system,
                    text: "Customer selected career and decision timing as the reading focus.",
                    timestamp: Date().addingTimeInterval(-520)
                ),
                ChatMessage(
                    sender: .customer,
                    text: "I have two job options and need help reading the timing.",
                    timestamp: Date().addingTimeInterval(-460)
                ),
                ChatMessage(
                    sender: .seer,
                    text: "The second path feels slower but more stable. I am checking the near-term window.",
                    timestamp: Date().addingTimeInterval(-390)
                ),
                ChatMessage(
                    sender: .customer,
                    text: "That matches how it feels. What should I watch for this week?",
                    timestamp: Date().addingTimeInterval(-160)
                )
            ],
            quickReplies: [
                "This week favors patience.",
                "I see one important conversation.",
                "Let me compare both paths."
            ]
        ),
        ChatConversation(
            customerName: "Anya S.",
            customerId: "C-3098",
            topic: "Daily energy reading",
            status: .followUp,
            priority: .normal,
            accountTier: "Standard",
            waitTime: "1h",
            unreadCount: 0,
            tint: .teal,
            messages: [
                ChatMessage(
                    sender: .customer,
                    text: "Can you save today’s reading? I want to come back to it later.",
                    timestamp: Date().addingTimeInterval(-4100)
                ),
                ChatMessage(
                    sender: .seer,
                    text: "Saved. The main theme is slow action, clear boundaries, and a calm reply.",
                    timestamp: Date().addingTimeInterval(-3980)
                ),
                ChatMessage(
                    sender: .system,
                    text: "Follow-up reminder created for tomorrow morning.",
                    timestamp: Date().addingTimeInterval(-3840)
                )
            ],
            quickReplies: [
                "I saved this reading.",
                "Would you like a reminder?",
                "I can pull one more card."
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

private struct CustomerHomeView: View {
    let onOpenChat: () -> Void

    @State private var selectedMenu: CustomerHomeMenu = .overview
    @State private var seerSearchText = ""

    private let profile = CustomerMockProfile.default
    private let readings = CustomerReading.mockReadings
    private let seers = CustomerSeer.mockSeers

    private var filteredSeers: [CustomerSeer] {
        let query = seerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !query.isEmpty else {
            return seers
        }

        return seers.filter { seer in
            seer.searchableText.contains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                CustomerHeroCard(profile: profile, onOpenChat: onOpenChat)

                CustomerHomeMenuPicker(selection: $selectedMenu)

                switch selectedMenu {
                case .overview:
                    CustomerReadingStatusCard(reading: readings[0])

                    CustomerActionGrid(
                        onOpenChat: onOpenChat,
                        onFindSeer: { selectedMenu = .findSeer }
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "Upcoming Guidance",
                            subtitle: "Mock customer requests and reading history"
                        )

                        LazyVStack(spacing: 10) {
                            ForEach(readings) { reading in
                                CustomerReadingRow(reading: reading)
                            }
                        }
                    }

                    CustomerFeaturedSeersPreview(seers: Array(seers.prefix(2)))
                case .findSeer:
                    CustomerSeerDiscoveryView(
                        searchText: $seerSearchText,
                        seers: filteredSeers,
                        allSeerCount: seers.count
                    )
                }
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
    }
}

private struct CustomerHeroCard: View {
    let profile: CustomerMockProfile
    let onOpenChat: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ProfilePhotoView(profile: profile.userProfile, size: 64)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Customer Space")
                        .font(.headline)

                    StatusBadge(title: profile.memberTier, color: .indigo)
                }

                Text(profile.fullName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Next insight window: \(profile.nextInsightWindow)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.teal)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onOpenChat) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title2)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Open Chat")
        }
        .padding(16)
        .cardStyle()
    }
}

private struct CustomerReadingStatusCard: View {
    let reading: CustomerReading

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(reading.color.opacity(0.14))

                    Image(systemName: reading.icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(reading.color)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Active Reading")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(reading.color)

                    Text(reading.title)
                        .font(.headline)

                    Text(reading.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                ConversationMetaChip(title: reading.status, color: reading.color, icon: "sparkles")
                ConversationMetaChip(title: reading.timeframe, color: .blue, icon: "calendar")
            }
        }
        .padding(16)
        .cardStyle(borderColor: reading.color.opacity(0.35))
    }
}

private struct CustomerActionGrid: View {
    let onOpenChat: () -> Void
    let onFindSeer: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            CustomerActionTile(
                title: "Ask Seer",
                subtitle: "Start a chat",
                icon: "bubble.left.and.bubble.right.fill",
                color: .teal,
                action: onOpenChat
            )

            CustomerActionTile(
                title: "Find Seer",
                subtitle: "Search guides",
                icon: "person.2.fill",
                color: .purple,
                action: onFindSeer
            )

            CustomerActionTile(
                title: "Daily Card",
                subtitle: "Preview insight",
                icon: "rectangle.stack.fill",
                color: .orange,
                action: {}
            )

            CustomerActionTile(
                title: "Saved Notes",
                subtitle: "3 entries",
                icon: "bookmark.fill",
                color: .blue,
                action: {}
            )
        }
    }
}

private struct CustomerActionTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .padding(14)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

private struct CustomerReadingRow: View {
    let reading: CustomerReading

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(reading.color.opacity(0.14))

                Image(systemName: reading.icon)
                    .font(.headline)
                    .foregroundStyle(reading.color)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(reading.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(reading.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(reading.status)
                .font(.caption.weight(.bold))
                .foregroundStyle(reading.color)
        }
        .padding(12)
        .cardStyle()
    }
}

private enum CustomerHomeMenu: String, CaseIterable, Identifiable {
    case overview
    case findSeer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .findSeer:
            return "Find Seer"
        }
    }

    var icon: String {
        switch self {
        case .overview:
            return "house.fill"
        case .findSeer:
            return "person.2.fill"
        }
    }
}

private struct CustomerHomeMenuPicker: View {
    @Binding var selection: CustomerHomeMenu

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CustomerHomeMenu.allCases) { menu in
                Button {
                    withAnimation(.snappy) {
                        selection = menu
                    }
                } label: {
                    Label(menu.title, systemImage: menu.icon)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .foregroundStyle(selection == menu ? .white : .secondary)
                        .background(selection == menu ? Color.teal : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(menu.title)
            }
        }
        .padding(4)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.border)
        }
    }
}

private struct CustomerFeaturedSeersPreview: View {
    let seers: [CustomerSeer]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Suggested Seers",
                subtitle: "Popular guides based on your recent focus"
            )

            LazyVStack(spacing: 12) {
                ForEach(seers) { seer in
                    NavigationLink {
                        CustomerSeerProfileView(seer: seer)
                    } label: {
                        CustomerSeerCard(seer: seer)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct CustomerSeerDiscoveryView: View {
    @Binding var searchText: String

    let seers: [CustomerSeer]
    let allSeerCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Find Seer",
                subtitle: "\(seers.count) of \(allSeerCount) mock seers"
            )

            ConversationSearchField(
                text: $searchText,
                placeholder: "Search seer, skill, or style"
            )

            if seers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("No seers found")
                        .font(.headline)

                    Text("Try a skill like relationship, tarot, career, or astrology.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .padding(16)
                .cardStyle()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(seers) { seer in
                        NavigationLink {
                            CustomerSeerProfileView(seer: seer)
                        } label: {
                            CustomerSeerCard(seer: seer)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct CustomerSeerCard: View {
    let seer: CustomerSeer

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CustomerSeerAvatar(seer: seer, size: 54)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(seer.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Label(seer.rating, systemImage: "star.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.yellow)
                        .lineLimit(1)
                }

                Text(seer.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(seer.tint)
                    .lineLimit(1)

                Text(seer.specialty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(seer.skills.prefix(3)), id: \.self) { skill in
                            SeerTag(title: skill, color: seer.tint, icon: "sparkles")
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)

                HStack(spacing: 8) {
                    ConversationMetaChip(title: seer.rate, color: .blue, icon: "creditcard.fill")
                    ConversationMetaChip(title: seer.nextAvailable, color: .green, icon: "clock.fill")
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(14)
        .cardStyle(borderColor: seer.tint.opacity(0.32))
    }
}

private struct CustomerSeerAvatar: View {
    let seer: CustomerSeer
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(seer.tint.opacity(0.16))

            Circle()
                .stroke(seer.tint.opacity(0.28), lineWidth: 1)

            Text(seer.initials)
                .font(.system(size: size * 0.31, weight: .bold))
                .foregroundStyle(seer.tint)
        }
        .frame(width: size, height: size)
    }
}

private struct SeerTag: View {
    let title: String
    let color: Color
    let icon: String?

    init(title: String, color: Color, icon: String? = nil) {
        self.title = title
        self.color = color
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            }

            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct CustomerSeerProfileView: View {
    let seer: CustomerSeer

    private let skillColumns = [
        GridItem(.adaptive(minimum: 112), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CustomerSeerProfileHero(seer: seer)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "Skills",
                        subtitle: "What this seer can help with"
                    )

                    LazyVGrid(columns: skillColumns, alignment: .leading, spacing: 8) {
                        ForEach(seer.skills, id: \.self) { skill in
                            SeerTag(title: skill, color: seer.tint, icon: "sparkles")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "Styles",
                        subtitle: "How the reading usually feels"
                    )

                    LazyVStack(spacing: 10) {
                        ForEach(seer.styles, id: \.self) { style in
                            SeerStyleRow(title: style, tint: seer.tint)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(
                        title: "Profile",
                        subtitle: "Mock seer introduction"
                    )

                    Text(seer.bio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .cardStyle()
                }
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(seer.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CustomerSeerProfileHero: View {
    let seer: CustomerSeer

    var body: some View {
        VStack(spacing: 14) {
            CustomerSeerAvatar(seer: seer, size: 86)

            VStack(spacing: 5) {
                Text(seer.name)
                    .font(.title3.bold())

                Text(seer.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(seer.tint)

                Text(seer.specialty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                ConversationMetaChip(title: "\(seer.rating) rating", color: .yellow, icon: "star.fill")
                ConversationMetaChip(title: "\(seer.reviewCount) reviews", color: .blue, icon: "text.bubble.fill")
                ConversationMetaChip(title: seer.nextAvailable, color: .green, icon: "clock.fill")
            }

            Button {
            } label: {
                Label("Start Mock Reading", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
        .cardStyle(borderColor: seer.tint.opacity(0.34))
    }
}

private struct SeerStyleRow: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(12)
        .cardStyle()
    }
}

private struct CustomerChatSpaceView: View {
    private let conversations = CustomerConversation.mockConversations

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "My Seer Chats",
                        subtitle: "Mock messages from active and past readings"
                    )

                    LazyVStack(spacing: 12) {
                        ForEach(conversations) { conversation in
                            NavigationLink {
                                CustomerChatDetailView(conversation: conversation)
                            } label: {
                                CustomerConversationRow(conversation: conversation)
                            }
                            .buttonStyle(.plain)
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

private struct CustomerConversationRow: View {
    let conversation: CustomerConversation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MiniAvatar(
                initials: conversation.seerInitials,
                color: conversation.tint
            )
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.seerName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(conversation.lastMessage.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(conversation.topic)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(conversation.lastMessage.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                ConversationMetaChip(
                    title: conversation.status,
                    color: conversation.tint,
                    icon: "sparkles"
                )
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
        }
        .padding(14)
        .cardStyle()
    }
}

private struct CustomerChatDetailView: View {
    let conversation: CustomerConversation

    @State private var messages: [ChatMessage]
    @State private var draft = ""

    init(conversation: CustomerConversation) {
        self.conversation = conversation
        _messages = State(initialValue: conversation.messages)
    }

    var body: some View {
        VStack(spacing: 0) {
            CustomerChatHeader(conversation: conversation)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            CustomerChatBubble(
                                message: message,
                                seerInitials: conversation.seerInitials
                            )
                            .id(message.id)
                        }
                    }
                    .padding(16)
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
                placeholder: "Message seer",
                quickReplies: conversation.quickReplies,
                onSend: sendMessage
            )
        }
        .background(AppBackground())
        .navigationTitle(conversation.seerName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendMessage() {
        let cleanDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanDraft.isEmpty else {
            return
        }

        messages.append(
            ChatMessage(
                sender: .customer,
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

private struct CustomerChatHeader: View {
    let conversation: CustomerConversation

    var body: some View {
        HStack(spacing: 12) {
            MiniAvatar(
                initials: conversation.seerInitials,
                color: conversation.tint
            )
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                Text(conversation.seerName)
                    .font(.headline)

                Text(conversation.topic)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ConversationMetaChip(
                    title: conversation.status,
                    color: conversation.tint,
                    icon: "sparkles"
                )
            }

            Spacer()
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

private struct CustomerChatBubble: View {
    let message: ChatMessage
    let seerInitials: String

    private var isCustomer: Bool {
        message.sender == .customer
    }

    var body: some View {
        switch message.sender {
        case .system:
            SystemMessageBubble(message: message)
        case .customer, .seer:
            HStack(alignment: .bottom, spacing: 8) {
                if isCustomer {
                    Spacer(minLength: 52)
                } else {
                    MiniAvatar(initials: seerInitials, color: .teal)
                }

                VStack(alignment: isCustomer ? .trailing : .leading, spacing: 5) {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(isCustomer ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isCustomer ? Color.indigo : AppColors.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if isCustomer {
                    MiniAvatar(initials: "MC", color: .indigo)
                } else {
                    Spacer(minLength: 52)
                }
            }
        }
    }
}

private struct CustomerProfileSpaceView: View {
    let onLogout: () -> Void

    private let profile = CustomerMockProfile.default

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 14) {
                    ProfilePhotoView(
                        profile: profile.userProfile,
                        size: 110,
                        showsCameraBadge: true
                    )

                    VStack(spacing: 5) {
                        Text(profile.fullName)
                            .font(.title2.bold())

                        Text(profile.birthInfo)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            StatusBadge(title: "Customer", color: .indigo)
                            StatusBadge(title: profile.memberTier, color: .teal)
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(22)
                .cardStyle()

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Account", subtitle: "Mock customer information")

                    VStack(spacing: 0) {
                        ProfileDetailRow(icon: "envelope", title: "Email", value: profile.email)
                        Divider().padding(.leading, 40)
                        ProfileDetailRow(icon: "sparkles", title: "Focus", value: profile.focus)
                        Divider().padding(.leading, 40)
                        ProfileDetailRow(icon: "calendar", title: "Birth Info", value: profile.birthInfo)
                    }
                    .padding(.vertical, 4)
                    .cardStyle()
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Preferences", subtitle: "Customer space settings")

                    VStack(spacing: 0) {
                        ProfileDetailRow(icon: "bell.badge", title: "Reading Alerts", value: "Enabled")
                        Divider().padding(.leading, 40)
                        ProfileDetailRow(icon: "lock.shield", title: "Role Access", value: "Customer")
                        Divider().padding(.leading, 40)
                        ProfileDetailRow(icon: "moon.stars", title: "Appearance", value: "System")
                    }
                    .padding(.vertical, 4)
                    .cardStyle()
                }

                Button(role: .destructive, action: onLogout) {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
    }
}

private struct CustomerMockProfile {
    let fullName: String
    let email: String
    let birthInfo: String
    let focus: String
    let memberTier: String
    let nextInsightWindow: String

    var userProfile: UserProfile {
        UserProfile(
            fullName: fullName,
            role: "Customer",
            email: email,
            phone: "",
            location: birthInfo
        )
    }

    static let `default` = CustomerMockProfile(
        fullName: "Mali Chan",
        email: "mali@example.com",
        birthInfo: "Bangkok • 09:15",
        focus: "Relationships and timing",
        memberTier: "Gold",
        nextInsightWindow: "Today, 20:00"
    )
}

private struct CustomerSeer: Identifiable {
    let id = UUID()
    let name: String
    let title: String
    let specialty: String
    let rating: String
    let reviewCount: Int
    let rate: String
    let nextAvailable: String
    let skills: [String]
    let styles: [String]
    let bio: String
    let tint: Color

    var initials: String {
        let value = name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()

        return value.isEmpty ? "S" : value
    }

    var searchableText: String {
        ([name, title, specialty, bio] + skills + styles)
            .joined(separator: " ")
            .lowercased()
    }

    static let mockSeers = [
        CustomerSeer(
            name: "Aurora Veil",
            title: "Relationship Timing Seer",
            specialty: "Soft guidance for love, reconnecting, and emotional timing.",
            rating: "4.9",
            reviewCount: 218,
            rate: "$18",
            nextAvailable: "Now",
            skills: ["Relationship", "Timing", "Tarot", "Birth Chart"],
            styles: ["Gentle and reflective", "Clear next steps", "Good for emotional questions"],
            bio: "Aurora focuses on relationship cycles, communication windows, and the small timing signals customers often miss when emotions are loud.",
            tint: .purple
        ),
        CustomerSeer(
            name: "Kirin Moon",
            title: "Career Path Reader",
            specialty: "Practical readings for work decisions, interviews, and pivots.",
            rating: "4.8",
            reviewCount: 176,
            rate: "$15",
            nextAvailable: "5m",
            skills: ["Career", "Decision", "Astrology", "Strategy"],
            styles: ["Direct and practical", "Structured summary", "Best for planning"],
            bio: "Kirin blends symbolic reading with grounded planning, helping customers turn uncertain career energy into a clean next action.",
            tint: .teal
        ),
        CustomerSeer(
            name: "Sol Aranya",
            title: "Daily Energy Guide",
            specialty: "Fast daily check-ins for mood, focus, and personal energy.",
            rating: "4.7",
            reviewCount: 142,
            rate: "$9",
            nextAvailable: "12m",
            skills: ["Daily Card", "Energy", "Mindset", "Focus"],
            styles: ["Warm and concise", "Action-focused", "Good for quick readings"],
            bio: "Sol is designed for customers who want a short reading before a busy day, with one clear theme and one small action.",
            tint: .orange
        ),
        CustomerSeer(
            name: "Mira North",
            title: "Dream Symbol Interpreter",
            specialty: "Pattern reading for dreams, recurring symbols, and intuition.",
            rating: "4.9",
            reviewCount: 96,
            rate: "$21",
            nextAvailable: "30m",
            skills: ["Dreams", "Symbols", "Intuition", "Journaling"],
            styles: ["Curious and detailed", "Symbol-by-symbol", "Best with context"],
            bio: "Mira helps customers unpack dream symbols without making the reading feel heavy, turning strange details into useful self-reflection.",
            tint: .indigo
        ),
        CustomerSeer(
            name: "Nara Bloom",
            title: "Calm Clarity Seer",
            specialty: "Supportive readings for stressful choices and relationship boundaries.",
            rating: "4.6",
            reviewCount: 121,
            rate: "$12",
            nextAvailable: "1h",
            skills: ["Boundaries", "Stress", "Relationships", "Clarity"],
            styles: ["Reassuring tone", "Slow and careful", "Good for sensitive topics"],
            bio: "Nara is a calm reader for customers who need gentle structure, especially when a question feels too tangled to name clearly.",
            tint: .pink
        )
    ]
}

private struct CustomerReading: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let status: String
    let timeframe: String
    let icon: String
    let color: Color

    static let mockReadings = [
        CustomerReading(
            title: "Relationship Timing",
            subtitle: "Aurora is preparing your next reading.",
            status: "In Progress",
            timeframe: "Today",
            icon: "heart.text.square.fill",
            color: .purple
        ),
        CustomerReading(
            title: "Career Crossroads",
            subtitle: "Saved guidance from your last session.",
            status: "Saved",
            timeframe: "Yesterday",
            icon: "briefcase.fill",
            color: .blue
        ),
        CustomerReading(
            title: "Daily Energy",
            subtitle: "A short card preview for the morning.",
            status: "Ready",
            timeframe: "Daily",
            icon: "sun.max.fill",
            color: .orange
        )
    ]
}

private struct CustomerConversation: Identifiable {
    let id = UUID()
    let seerName: String
    let topic: String
    let status: String
    let tint: Color
    let messages: [ChatMessage]
    let quickReplies: [String]

    var seerInitials: String {
        let value = seerName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()

        return value.isEmpty ? "S" : value
    }

    var lastMessage: ChatMessage {
        messages.last ?? ChatMessage(
            sender: .system,
            text: "No messages yet.",
            timestamp: Date()
        )
    }

    static let mockConversations = [
        CustomerConversation(
            seerName: "Aurora Veil",
            topic: "Relationship Timing",
            status: "Reading active",
            tint: .purple,
            messages: [
                ChatMessage(
                    sender: .system,
                    text: "Reading request accepted by Aurora.",
                    timestamp: Date().addingTimeInterval(-1200)
                ),
                ChatMessage(
                    sender: .customer,
                    text: "I want to understand whether this is the right moment to reconnect.",
                    timestamp: Date().addingTimeInterval(-1120)
                ),
                ChatMessage(
                    sender: .seer,
                    text: "I am seeing a slower window. Give me one detail about the last conversation.",
                    timestamp: Date().addingTimeInterval(-980)
                ),
                ChatMessage(
                    sender: .customer,
                    text: "It ended kindly, but we have not spoken for three weeks.",
                    timestamp: Date().addingTimeInterval(-760)
                )
            ],
            quickReplies: [
                "That feels accurate.",
                "Can you explain the timing?",
                "What should I avoid?"
            ]
        ),
        CustomerConversation(
            seerName: "Kirin Moon",
            topic: "Career Direction",
            status: "Follow up",
            tint: .teal,
            messages: [
                ChatMessage(
                    sender: .customer,
                    text: "I saved your note about waiting until Friday.",
                    timestamp: Date().addingTimeInterval(-5600)
                ),
                ChatMessage(
                    sender: .seer,
                    text: "Good. Friday is better for asking directly. Keep the message simple.",
                    timestamp: Date().addingTimeInterval(-5480)
                )
            ],
            quickReplies: [
                "I will do that.",
                "Can you help me draft it?",
                "Please remind me Friday."
            ]
        )
    ]
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
                SeerDashboardHeader(
                    profile: profile,
                    activeCount: activeCount,
                    onViewProfile: onViewProfile
                )

                RoleOverviewSection(activeRole: .seer)

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

private struct SeerDashboardHeader: View {
    let profile: UserProfile
    let activeCount: Int
    let onViewProfile: () -> Void

    var body: some View {
        Button(action: onViewProfile) {
            HStack(spacing: 14) {
                ProfilePhotoView(profile: profile, size: 62)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Seer Operation")
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

                        Text("\(activeCount) active reading notes")
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
                    subtitle: "Customer readings needing seer action"
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
                title: "Reading Notes",
                subtitle: "Create, update, complete, or delete seer notes"
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

                Text("Add the first seer note for this mock reading flow.")
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
    let onLogout: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ProfileHeroCard(profile: profileViewModel.profile)

                RoleOverviewSection(activeRole: .seer)

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
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onLogout) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityLabel("Log Out")
            }

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
                    StatusBadge(title: "Seer", color: .teal)
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
            SectionHeader(title: "Contact", subtitle: "Seer profile detail")

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
                SectionHeader(title: "Activity", subtitle: "Local reading notes")

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
            SectionHeader(title: "Workspace", subtitle: "Mock seer preferences")

            VStack(spacing: 0) {
                ProfileDetailRow(icon: "bell.badge", title: "Queue Alerts", value: "Enabled")
                Divider().padding(.leading, 40)
                ProfileDetailRow(icon: "lock.shield", title: "Role Access", value: "Seer")
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
