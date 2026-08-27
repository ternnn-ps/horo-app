import SwiftUI

struct ContentView: View {
    @StateObject private var recordViewModel = RecordListViewModel()
    @StateObject private var profileViewModel = UserProfileViewModel()
    @StateObject private var chatStore = TestChatViewModel()
    @StateObject private var supabaseApp = SupabaseAppViewModel()

    @AppStorage("horo.appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("horo.language") private var languageRawValue = AppLanguage.english.rawValue
    @State private var sessionAccount: TestAccount?
    @State private var selectedSeerTab: SeerTab = .chat
    @State private var selectedCustomerTab: CustomerTab = .home
    @State private var customerCoinBalance = 420
    @State private var editorMode: RecordEditorMode?
    @State private var isDeleteConfirmationPresented = false
    @State private var recordPendingDeletion: TestRecord?

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private var appearance: Binding<AppAppearance> {
        Binding(
            get: { selectedAppearance },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .english
    }

    private var language: Binding<AppLanguage> {
        Binding(
            get: { selectedLanguage },
            set: { languageRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Group {
            if let sessionAccount {
                switch sessionAccount.role {
                case .seer:
                    SeerWorkspaceView(
                        selectedTab: $selectedSeerTab,
                        appAppearance: appearance,
                        appLanguage: language,
                        testAccount: sessionAccount,
                        profileViewModel: profileViewModel,
                        recordViewModel: recordViewModel,
                        chatStore: chatStore,
                        supabaseApp: supabaseApp,
                        onCreateRecord: { editorMode = .create },
                        onEditRecord: { editorMode = .edit($0) },
                        onDeleteRecord: { prepareDelete($0) },
                        onLogout: logout
                    )
                case .customer:
                    CustomerWorkspaceView(
                        selectedTab: $selectedCustomerTab,
                        appAppearance: appearance,
                        appLanguage: language,
                        testAccount: sessionAccount,
                        chatStore: chatStore,
                        supabaseApp: supabaseApp,
                        coinBalance: $customerCoinBalance,
                        onLogout: logout
                    )
                }
            } else {
                LoginView(appLanguage: selectedLanguage) { account, password in
                    sessionAccount = account
                    Task {
                        if let liveCoinBalance = await supabaseApp.signIn(
                            testAccount: account,
                            password: password,
                            chatStore: chatStore
                        ) {
                            customerCoinBalance = liveCoinBalance
                        }
                    }
                }
            }
        }
        .tint(.teal)
        .preferredColorScheme(selectedAppearance.colorScheme)
        .environment(\.locale, Locale(identifier: selectedLanguage.localeIdentifier))
        .sheet(item: $editorMode) { mode in
            RecordEditorView(mode: mode, appLanguage: selectedLanguage) { title, notes in
                switch mode {
                case .create:
                    recordViewModel.create(title: title, notes: notes)
                case .edit(let record):
                    recordViewModel.update(record, title: title, notes: notes)
                }
            }
        }
        .confirmationDialog(
            selectedLanguage.text("Delete Record", "ลบบันทึก"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible,
            presenting: recordPendingDeletion
        ) { record in
            Button(selectedLanguage.text("Delete Record", "ลบบันทึก"), role: .destructive) {
                recordViewModel.delete(record)
                recordPendingDeletion = nil
            }

            Button(selectedLanguage.text("Cancel", "ยกเลิก"), role: .cancel) {
                recordPendingDeletion = nil
            }
        } message: { record in
            Text(selectedLanguage.text("Remove \"\(record.title)\" from this device?", "ต้องการลบ \"\(record.title)\" ออกจากเครื่องนี้หรือไม่?"))
        }
    }

    private func prepareDelete(_ record: TestRecord) {
        recordPendingDeletion = record
        isDeleteConfirmationPresented = true
    }

    private func logout() {
        sessionAccount = nil
        selectedSeerTab = .chat
        selectedCustomerTab = .home
        editorMode = nil
        recordPendingDeletion = nil
    }
}

private struct SeerWorkspaceView: View {
    @Binding var selectedTab: SeerTab
    @Binding var appAppearance: AppAppearance
    @Binding var appLanguage: AppLanguage

    let testAccount: TestAccount

    @ObservedObject var profileViewModel: UserProfileViewModel
    @ObservedObject var recordViewModel: RecordListViewModel
    @ObservedObject var chatStore: TestChatViewModel
    @ObservedObject var supabaseApp: SupabaseAppViewModel

    let onCreateRecord: () -> Void
    let onEditRecord: (TestRecord) -> Void
    let onDeleteRecord: (TestRecord) -> Void
    let onLogout: () -> Void

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ChatHomeView(
                    profile: profileViewModel.profile,
                    chatStore: chatStore,
                    supabaseApp: supabaseApp,
                    appLanguage: appLanguage
                )
                    .navigationTitle(appLanguage.chatTitle)
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Label(appLanguage.chatTitle, systemImage: "bubble.left.and.bubble.right.fill")
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
                    onDeleteRecord: onDeleteRecord,
                    appLanguage: appLanguage
                )
                .navigationTitle(appLanguage.dashboardTitle)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onCreateRecord) {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(appLanguage.addRecordTitle)
                    }
                }
            }
            .tabItem {
                Label(appLanguage.dashboardTitle, systemImage: "chart.bar.xaxis")
            }
            .tag(SeerTab.dashboard)

            NavigationStack {
                ProfilePageView(
                    profileViewModel: profileViewModel,
                    totalCount: recordViewModel.totalCount,
                    activeCount: recordViewModel.activeCount,
                    completedCount: recordViewModel.completedCount,
                    onCreateRecord: onCreateRecord,
                    appAppearance: $appAppearance,
                    appLanguage: $appLanguage,
                    testAccount: testAccount,
                    onLogout: onLogout
                )
                .navigationTitle(appLanguage.profileTitle)
                .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Label(appLanguage.profileTitle, systemImage: "person.crop.circle.fill")
            }
            .tag(SeerTab.profile)
        }
    }
}

private struct CustomerWorkspaceView: View {
    @Binding var selectedTab: CustomerTab
    @Binding var appAppearance: AppAppearance
    @Binding var appLanguage: AppLanguage

    let testAccount: TestAccount
    @ObservedObject var chatStore: TestChatViewModel
    @ObservedObject var supabaseApp: SupabaseAppViewModel

    @Binding var coinBalance: Int

    let onLogout: () -> Void

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CustomerHomeView(
                    supabaseApp: supabaseApp,
                    chatStore: chatStore,
                    coinBalance: $coinBalance,
                    appLanguage: appLanguage,
                    onOpenChat: { selectedTab = .chat }
                )
                    .navigationTitle(appLanguage.homeTitle)
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Label(appLanguage.homeTitle, systemImage: "sparkles")
            }
            .tag(CustomerTab.home)

            NavigationStack {
                CustomerChatSpaceView(
                    chatStore: chatStore,
                    supabaseApp: supabaseApp,
                    appLanguage: appLanguage
                )
                    .navigationTitle(appLanguage.chatTitle)
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Label(appLanguage.chatTitle, systemImage: "bubble.left.and.bubble.right.fill")
            }
            .tag(CustomerTab.chat)

            NavigationStack {
                CustomerProfileSpaceView(
                    appAppearance: $appAppearance,
                    appLanguage: $appLanguage,
                    testAccount: testAccount,
                    coinBalance: $coinBalance,
                    onLogout: onLogout
                )
                    .navigationTitle(appLanguage.profileTitle)
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Label(appLanguage.profileTitle, systemImage: "person.crop.circle.fill")
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

private enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .system:
            return language.text("System", "ตามระบบ")
        case .light:
            return language.text("Light", "โหมดสว่าง")
        case .dark:
            return language.text("Dark", "โหมดมืด")
        }
    }

    var icon: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

private enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case thai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english:
            return "English"
        case .thai:
            return "ไทย"
        }
    }

    var subtitle: String {
        switch self {
        case .english:
            return "Use English app copy"
        case .thai:
            return "ใช้ภาษาไทยในแอป"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english:
            return "en_US"
        case .thai:
            return "th_TH"
        }
    }

    var languageRowTitle: String {
        switch self {
        case .english:
            return "Language"
        case .thai:
            return "ภาษา"
        }
    }

    var profilePreferenceSubtitle: String {
        switch self {
        case .english:
            return "App display and account settings"
        case .thai:
            return "การแสดงผลและตั้งค่าบัญชี"
        }
    }

    var passwordOptionalHint: String {
        switch self {
        case .english:
            return "Password optional for test accounts"
        case .thai:
            return "บัญชีทดสอบยังไม่ต้องใช้รหัสผ่าน"
        }
    }

    var homeTitle: String {
        text("Home", "หน้าแรก")
    }

    var chatTitle: String {
        text("Chat", "แชท")
    }

    var dashboardTitle: String {
        text("Dashboard", "แดชบอร์ด")
    }

    var profileTitle: String {
        text("Profile", "โปรไฟล์")
    }

    var addRecordTitle: String {
        text("Add Record", "เพิ่มบันทึก")
    }

    var editProfileTitle: String {
        text("Edit Profile", "แก้ไขโปรไฟล์")
    }

    var saveTitle: String {
        text("Save", "บันทึก")
    }

    var cancelTitle: String {
        text("Cancel", "ยกเลิก")
    }

    func text(_ english: String, _ thai: String) -> String {
        switch self {
        case .english:
            return english
        case .thai:
            return thai
        }
    }
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

private extension ProfileAvatarStyle {
    var colors: [Color] {
        switch self {
        case .ocean:
            return [.teal, .blue, .indigo]
        case .sunrise:
            return [.orange, .pink, .purple]
        case .violet:
            return [.purple, .indigo, .blue]
        case .forest:
            return [.green, .teal, .mint]
        }
    }

    var icon: String {
        switch self {
        case .ocean:
            return "water.waves"
        case .sunrise:
            return "sun.max.fill"
        case .violet:
            return "sparkles"
        case .forest:
            return "leaf.fill"
        }
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .ocean:
            return language.text(title, "มหาสมุทร")
        case .sunrise:
            return language.text(title, "พระอาทิตย์ขึ้น")
        case .violet:
            return language.text(title, "ไวโอเล็ต")
        case .forest:
            return language.text(title, "ป่าไม้")
        }
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

private struct DataConnectionBanner: View {
    let message: String
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isConnected ? "checkmark.seal.fill" : "wifi.slash")
                .font(.headline)
                .foregroundStyle(isConnected ? .green : .orange)

            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(AppColors.softFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isConnected ? Color.green.opacity(0.30) : Color.orange.opacity(0.30))
        }
    }
}

private enum OperationRole: String, CaseIterable, Identifiable {
    case seer
    case customer

    var id: String { rawValue }

    var loginKeyword: String { rawValue }

    var title: String {
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .seer:
            return language.text("Seer", "หมอดู")
        case .customer:
            return language.text("Customer", "ลูกค้า")
        }
    }

    var subtitle: String {
        subtitle(in: .english)
    }

    func subtitle(in language: AppLanguage) -> String {
        switch self {
        case .seer:
            return language.text("Handles readings, chat queue, and session notes", "จัดการคำทำนาย คิวแชท และบันทึกงาน")
        case .customer:
            return language.text("Requests guidance, chats, and tracks readings", "ขอคำแนะนำ แชท และติดตามคำทำนาย")
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

private struct TestAccount: Identifiable, Equatable {
    let id: String
    let role: OperationRole
    let login: String
    let displayName: String
    let email: String
    let subtitle: String

    static let customer = TestAccount(
        id: "test-customer",
        role: .customer,
        login: "customer",
        displayName: "Mali Chan",
        email: "customer@horo.test",
        subtitle: "Customer test account for buying coins and chatting"
    )

    static let seer = TestAccount(
        id: "test-seer",
        role: .seer,
        login: "seer",
        displayName: "Aurora Veil",
        email: "seer@horo.test",
        subtitle: "Seer test account for receiving customer messages"
    )

    static let all = [customer, seer]

    static func matching(_ value: String) -> TestAccount? {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return all.first {
            $0.login == normalizedValue
                || $0.email.lowercased() == normalizedValue
                || $0.role.loginKeyword == normalizedValue
        }
    }
}

private struct LoginView: View {
    let appLanguage: AppLanguage
    let onLogin: (TestAccount, String) -> Void

    @State private var loginText = ""
    @State private var password = ""
    @State private var validationMessage: String?

    private var requestedAccount: TestAccount? {
        TestAccount.matching(loginText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    LoginHero(appLanguage: appLanguage)

                    VStack(spacing: 12) {
                        TextField(
                            appLanguage == .thai ? "พิมพ์ seer หรือ customer" : "Type seer or customer",
                            text: $loginText
                        )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(AppColors.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        SecureField(appLanguage.passwordOptionalHint, text: $password)
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
                                requestedAccount.map {
                                    appLanguage == .thai ? "เข้าสู่ระบบเป็น \($0.role.title(in: appLanguage))" : "Login as \($0.role.title(in: appLanguage))"
                                } ?? (appLanguage == .thai ? "เข้าสู่ระบบ" : "Login"),
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
                            title: appLanguage == .thai ? "บัญชีทดสอบ" : "Test Accounts",
                            subtitle: appLanguage.passwordOptionalHint
                        )

                        ForEach(TestAccount.all) { account in
                            Button {
                                loginText = account.login
                                validationMessage = nil
                            } label: {
                                LoginRoleCard(
                                    account: account,
                                    isSelected: requestedAccount == account,
                                    appLanguage: appLanguage
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
        guard let account = requestedAccount else {
            validationMessage = appLanguage.text("Use \"seer\" or \"customer\" to enter this mock app.", "พิมพ์ \"seer\" หรือ \"customer\" เพื่อเข้าสู่แอปทดสอบ")
            return
        }

        validationMessage = nil
        onLogin(account, password)
    }
}

private struct LoginHero: View {
    let appLanguage: AppLanguage

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

                Text(appLanguage.text("Mock role login for seer and customer spaces", "หน้าล็อกอินทดสอบสำหรับหมอดูและลูกค้า"))
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
    let account: TestAccount
    let isSelected: Bool
    let appLanguage: AppLanguage

    private var role: OperationRole {
        account.role
    }

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
                Text(account.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(account.role.subtitle(in: appLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(account.email)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text(account.login)
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
    let appLanguage: AppLanguage

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: appLanguage.text("Operation Roles", "บทบาทการใช้งาน"),
                subtitle: appLanguage.text("Seer workspace is active", "พื้นที่ทำงานของหมอดูกำลังใช้งาน")
            )

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(OperationRole.allCases) { role in
                    OperationRoleCard(
                        role: role,
                        isActive: role == activeRole,
                        appLanguage: appLanguage
                    )
                }
            }
        }
    }
}

private struct OperationRoleCard: View {
    let role: OperationRole
    let isActive: Bool
    let appLanguage: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: role.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(role.tint)

                Spacer()

                if isActive {
                    StatusBadge(title: appLanguage.text("Active", "ใช้งานอยู่"), color: .green)
                }
            }

            Text(role.title(in: appLanguage))
                .font(.headline)
                .foregroundStyle(.primary)

            Text(role.subtitle(in: appLanguage))
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
    @ObservedObject var chatStore: TestChatViewModel
    @ObservedObject var supabaseApp: SupabaseAppViewModel
    let appLanguage: AppLanguage

    @State private var searchText = ""

    private var conversations: [ChatConversation] {
        chatStore.conversations
    }

    private var queueTitle: String {
        appLanguage == .thai ? "คิวลูกค้า" : "Customer Queue"
    }

    private var conversationCountLabel: String {
        appLanguage == .thai ? "รายการสนทนา" : "conversations"
    }

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
                ChatOperationsHeader(profile: profile, appLanguage: appLanguage)

                DataConnectionBanner(
                    message: supabaseApp.statusMessage,
                    isConnected: supabaseApp.isConnected
                )

                QueueMetricsRow(conversations: conversations, appLanguage: appLanguage)

                ConversationSearchField(
                    text: $searchText,
                    placeholder: appLanguage.text("Search customer or reading", "ค้นหาลูกค้าหรือคำทำนาย"),
                    clearLabel: appLanguage.text("Clear Search", "ล้างการค้นหา")
                )

                SectionHeader(
                    title: queueTitle,
                    subtitle: "\(filteredConversations.count) \(conversationCountLabel)"
                )

                LazyVStack(spacing: 12) {
                    ForEach(filteredConversations) { conversation in
                        NavigationLink {
                            MockChatDetailView(
                                conversationID: conversation.id,
                                chatStore: chatStore,
                                supabaseApp: supabaseApp,
                                seerName: profile.fullName,
                                seerInitials: profile.initials,
                                appLanguage: appLanguage
                            )
                        } label: {
                            InboxRow(conversation: conversation, appLanguage: appLanguage)
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
    let appLanguage: AppLanguage

    var body: some View {
        HStack(spacing: 14) {
            ProfilePhotoView(profile: profile, size: 56)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(appLanguage.text("Seer Desk", "โต๊ะหมอดู"))
                        .font(.headline)

                    StatusBadge(title: appLanguage.text("Online", "ออนไลน์"), color: .green)
                }

                Text(profile.fullName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(appLanguage.text("Customer reading queue", "คิวคำทำนายของลูกค้า"))
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
    let appLanguage: AppLanguage

    private var waitingCount: Int {
        conversations.filter { $0.status == .waiting }.count
    }

    private var highPriorityCount: Int {
        conversations.filter { $0.priority != .normal }.count
    }

    var body: some View {
        HStack(spacing: 10) {
            QueueMetricTile(
                title: appLanguage.text("Waiting", "รอคิว"),
                value: "\(waitingCount)",
                icon: "clock.badge.exclamationmark",
                color: .orange
            )

            QueueMetricTile(
                title: appLanguage.text("Priority", "สำคัญ"),
                value: "\(highPriorityCount)",
                icon: "exclamationmark.triangle.fill",
                color: .red
            )

            QueueMetricTile(
                title: appLanguage.text("Open", "เปิดอยู่"),
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
    let clearLabel: String

    init(text: Binding<String>, placeholder: String = "Search customer or reading", clearLabel: String = "Clear Search") {
        _text = text
        self.placeholder = placeholder
        self.clearLabel = clearLabel
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
                .accessibilityLabel(clearLabel)
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
    let appLanguage: AppLanguage

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
                        title: conversation.status.title(in: appLanguage),
                        color: conversation.status.color,
                        icon: conversation.status.icon
                    )

                    ConversationMetaChip(
                        title: conversation.priority.title(in: appLanguage),
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

private struct CoinMetaChip: View {
    let title: String
    var color: Color = .orange

    var body: some View {
        HStack(spacing: 5) {
            HoroCoinIcon(size: 14)

            Text(title)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(color.opacity(0.13))
        .clipShape(Capsule())
    }
}

private struct HoroCoinIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.93, blue: 0.44),
                            Color(red: 0.98, green: 0.69, blue: 0.16),
                            Color(red: 0.80, green: 0.43, blue: 0.08)
                        ],
                        center: .topLeading,
                        startRadius: size * 0.08,
                        endRadius: size * 0.62
                    )
                )

            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.70),
                            Color(red: 0.70, green: 0.33, blue: 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(1.1, size * 0.09)
                )

            Circle()
                .strokeBorder(Color.white.opacity(0.36), lineWidth: max(0.8, size * 0.035))
                .padding(size * 0.18)

            Text("C")
                .font(.system(size: size * 0.43, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.38, green: 0.20, blue: 0.04))
        }
        .frame(width: size, height: size)
        .shadow(color: Color.orange.opacity(0.18), radius: size * 0.10, x: 0, y: size * 0.04)
        .accessibilityHidden(true)
    }
}

private struct MockChatDetailView: View {
    let conversationID: UUID
    @ObservedObject var chatStore: TestChatViewModel
    @ObservedObject var supabaseApp: SupabaseAppViewModel
    let seerName: String
    let seerInitials: String
    let appLanguage: AppLanguage

    @State private var draft = ""

    private var conversation: ChatConversation {
        chatStore.conversation(id: conversationID) ?? .emptyTestConversation
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatCustomerHeader(conversation: conversation, appLanguage: appLanguage)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(conversation.messages) { message in
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
                .onChange(of: conversation.messages.count) { _, _ in
                    scrollToLatestMessage(with: proxy)
                }
            }

            ChatComposer(
                draft: $draft,
                placeholder: appLanguage.text("Message customer", "ส่งข้อความถึงลูกค้า"),
                quickReplies: conversation.quickReplies,
                attachLabel: appLanguage.text("Attach File", "แนบไฟล์"),
                sendLabel: appLanguage.text("Send Message", "ส่งข้อความ"),
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
                .accessibilityLabel(appLanguage.text("Call Customer", "โทรหาลูกค้า"))

                Button {
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .accessibilityLabel(appLanguage.text("Resolve Conversation", "ปิดงานสนทนา"))
            }
        }
    }

    private func sendMessage() {
        let cleanDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanDraft.isEmpty else {
            return
        }

        draft = ""

        Task {
            let didSendToSupabase = await supabaseApp.sendMessage(
                conversationID: conversationID,
                sender: .seer,
                text: cleanDraft,
                chatStore: chatStore
            )

            if !didSendToSupabase {
                chatStore.sendMessage(
                    conversationID: conversationID,
                    sender: .seer,
                    text: cleanDraft
                )
            }
        }
    }

    private func scrollToLatestMessage(with proxy: ScrollViewProxy) {
        guard let id = conversation.messages.last?.id else {
            return
        }

        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }
}

private struct ChatCustomerHeader: View {
    let conversation: ChatConversation
    let appLanguage: AppLanguage

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
                            title: conversation.status.title(in: appLanguage),
                            color: conversation.status.color,
                            icon: conversation.status.icon
                        )
                    }

                    Text("\(conversation.customerId) • \(conversation.accountTier) \(appLanguage.text("member", "สมาชิก"))")
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
                    title: conversation.priority.title(in: appLanguage),
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
    let attachLabel: String
    let sendLabel: String
    let onSend: () -> Void

    init(
        draft: Binding<String>,
        placeholder: String,
        quickReplies: [String],
        attachLabel: String = "Attach File",
        sendLabel: String = "Send Message",
        onSend: @escaping () -> Void
    ) {
        _draft = draft
        self.placeholder = placeholder
        self.quickReplies = quickReplies
        self.attachLabel = attachLabel
        self.sendLabel = sendLabel
        self.onSend = onSend
    }

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
                .accessibilityLabel(attachLabel)

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
                .accessibilityLabel(sendLabel)
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
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .waiting:
            return language.text("Waiting", "รอคิว")
        case .active:
            return language.text("Active", "กำลังดำเนินการ")
        case .followUp:
            return language.text("Follow Up", "ติดตามผล")
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
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .normal:
            return language.text("Normal", "ปกติ")
        case .high:
            return language.text("High", "สำคัญ")
        case .vip:
            return language.text("VIP", "VIP")
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
    let id: UUID
    let seerName: String
    let seerId: String
    let customerName: String
    let customerId: String
    let topic: String
    var status: ConversationStatus
    let priority: ConversationPriority
    let accountTier: String
    let waitTime: String
    var unreadCount: Int
    let tint: Color
    var messages: [ChatMessage]
    let quickReplies: [String]

    init(
        id: UUID = UUID(),
        seerName: String = "Aurora Veil",
        seerId: String = "S-8001",
        customerName: String,
        customerId: String,
        topic: String,
        status: ConversationStatus,
        priority: ConversationPriority,
        accountTier: String,
        waitTime: String,
        unreadCount: Int,
        tint: Color,
        messages: [ChatMessage],
        quickReplies: [String]
    ) {
        self.id = id
        self.seerName = seerName
        self.seerId = seerId
        self.customerName = customerName
        self.customerId = customerId
        self.topic = topic
        self.status = status
        self.priority = priority
        self.accountTier = accountTier
        self.waitTime = waitTime
        self.unreadCount = unreadCount
        self.tint = tint
        self.messages = messages
        self.quickReplies = quickReplies
    }

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

    static var emptyTestConversation: ChatConversation {
        ChatConversation(
            customerName: "Test Customer",
            customerId: "C-TEST",
            topic: "Test API chat",
            status: .active,
            priority: .normal,
            accountTier: "Test",
            waitTime: "Now",
            unreadCount: 0,
            tint: .teal,
            messages: [
                ChatMessage(
                    sender: .system,
                    text: "This test conversation is no longer available.",
                    timestamp: Date()
                )
            ],
            quickReplies: []
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

@MainActor
private final class TestChatViewModel: ObservableObject {
    @Published private(set) var conversations: [ChatConversation]

    init(conversations: [ChatConversation] = ChatConversation.mockConversations) {
        self.conversations = conversations
    }

    func conversation(id: UUID) -> ChatConversation? {
        conversations.first { $0.id == id }
    }

    func replaceConversations(_ conversations: [ChatConversation]) {
        self.conversations = conversations
    }

    @discardableResult
    func startConversation(with seer: CustomerSeer, firstMessage: String) -> UUID {
        let cleanText = firstMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let conversation = ChatConversation(
            seerName: seer.name,
            seerId: seer.accountID?.uuidString ?? seer.id.uuidString,
            customerName: TestAccount.customer.displayName,
            customerId: "C-TEST",
            topic: seer.skills.first.map { "\($0) reading" } ?? "General reading",
            status: .waiting,
            priority: .normal,
            accountTier: "Test",
            waitTime: "Now",
            unreadCount: 0,
            tint: seer.tint,
            messages: [
                ChatMessage(
                    sender: .system,
                    text: "New reading chat started with \(seer.name).",
                    timestamp: Date()
                ),
                ChatMessage(
                    sender: .customer,
                    text: cleanText.isEmpty ? "Hi \(seer.name), I would like to start a reading." : cleanText,
                    timestamp: Date()
                )
            ],
            quickReplies: [
                "Thank you.",
                "Can you explain more?",
                "I want to book a call."
            ]
        )

        conversations.insert(conversation, at: 0)
        return conversation.id
    }

    func sendMessage(conversationID: UUID, sender: ChatMessage.Sender, text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanText.isEmpty,
              let index = conversations.firstIndex(where: { $0.id == conversationID })
        else {
            return
        }

        conversations[index].messages.append(
            ChatMessage(
                sender: sender,
                text: cleanText,
                timestamp: Date()
            )
        )
        conversations[index].status = .active

        switch sender {
        case .customer:
            conversations[index].unreadCount += 1
        case .seer:
            conversations[index].unreadCount = 0
        case .system:
            break
        }
    }
}

@MainActor
private final class SupabaseAppViewModel: ObservableObject {
    @Published private(set) var isConfigured: Bool
    @Published private(set) var isConnected = false
    @Published private(set) var statusMessage: String
    @Published private(set) var walletAvailableCoin: Int?
    @Published private(set) var seers: [CustomerSeer] = []
    @Published private(set) var coinPackages: [WalletTopUpOption] = []

    private let service: SupabaseHoroDataService?
    private var signedInAccountID: UUID?
    private var signedInRole: OperationRole?

    init(configuration: SupabaseConfiguration? = .runtime) {
        if let configuration {
            service = SupabaseHoroDataService(configuration: configuration)
            isConfigured = true
            statusMessage = "Supabase settings loaded. Login will test the live database."
        } else {
            service = nil
            isConfigured = false
            statusMessage = "Local mock mode. Add SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY to connect Supabase."
        }
    }

    func signIn(testAccount: TestAccount, password: String, chatStore: TestChatViewModel) async -> Int? {
        guard let service else {
            isConnected = false
            statusMessage = "Local mock mode. Supabase URL or publishable key is missing."
            return nil
        }

        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPassword = cleanPassword.isEmpty ? service.configuration.testPassword : cleanPassword

        do {
            let userID = try await service.signIn(email: testAccount.email, password: resolvedPassword)
            let account = try await service.fetchAccount()

            signedInAccountID = userID
            signedInRole = testAccount.role
            isConnected = true
            statusMessage = "Supabase connected as \(account.role.rawValue)."

            await refreshWallet()
            await refreshSeers()
            await refreshCoinPackages()
            await refreshConversations(chatStore: chatStore)

            return walletAvailableCoin
        } catch {
            isConnected = false
            statusMessage = "Supabase login failed: \(error.localizedDescription)"
            return nil
        }
    }

    /// คำถามที่ส่งไม่สำเร็จและยังรอ retry — เก็บไว้เพื่อคง idempotency key เดิม
    private var pendingQuestionDraft: SupabaseQuestionDraft?

    func startQuestion(with seer: CustomerSeer, firstMessage: String, chatStore: TestChatViewModel) async -> Bool {
        guard let service, isConnected else {
            statusMessage = "Supabase is not connected. Created a local test chat instead."
            return false
        }

        guard let serviceID = seer.serviceID else {
            statusMessage = "\(seer.name) has no enabled Supabase service yet."
            return false
        }

        // ใช้ draft เดิมถ้าคำถามนี้เคยส่งแล้วไม่สำเร็จ — key เดิมทำให้ยิงซ้ำไม่หักเหรียญรอบสอง
        let draft = QuestionDraftPolicy.draft(
            reusing: pendingQuestionDraft,
            seerServiceID: serviceID,
            message: firstMessage
        )
        pendingQuestionDraft = draft

        do {
            let submitted = try await service.submitQuestion(draft)
            pendingQuestionDraft = nil
            statusMessage = submitted.replayed
                ? "คำถามนี้ส่งไปแล้ว ไม่ได้หักเหรียญซ้ำ"
                : "Question submitted to Supabase."
            await refreshWallet()
            await refreshConversations(chatStore: chatStore)
            return true
        } catch {
            statusMessage = "Could not submit question: \(error.localizedDescription)"
            return false
        }
    }

    func sendMessage(
        conversationID: UUID,
        sender: ChatMessage.Sender,
        text: String,
        chatStore: TestChatViewModel
    ) async -> Bool {
        guard sender != .system else {
            return false
        }

        guard let service, isConnected, let signedInAccountID else {
            return false
        }

        do {
            _ = try await service.sendQuestionMessage(
                questionID: conversationID,
                senderID: signedInAccountID,
                body: text
            )
            statusMessage = "Message synced to Supabase."
            await refreshConversations(chatStore: chatStore)
            return true
        } catch {
            statusMessage = "Message saved locally. Supabase insert failed: \(error.localizedDescription)"
            return false
        }
    }

    private func refreshWallet() async {
        guard let service else {
            return
        }

        do {
            let wallet = try await service.fetchWallet()
            walletAvailableCoin = wallet.availableCoin
        } catch {
            walletAvailableCoin = nil
        }
    }

    private func refreshSeers() async {
        guard let service else {
            return
        }

        do {
            let listings = try await service.fetchSeerListings(matching: nil)
            seers = mapSeers(listings)
        } catch {
            if seers.isEmpty {
                seers = []
            }
        }
    }

    private func refreshCoinPackages() async {
        guard let service else {
            return
        }

        do {
            let packages = try await service.fetchCoinPackages()
            coinPackages = packages.map { package in
                WalletTopUpOption(
                    id: package.code,
                    coins: package.coinAmount + package.bonusCoin,
                    priceLabel: "\(package.currency) \(package.priceMinor / 100)",
                    subtitle: package.allowedMethods.isEmpty
                        ? "Supabase coin package"
                        : "Accepts \(package.allowedMethods.joined(separator: ", "))"
                )
            }
        } catch {
            coinPackages = []
        }
    }

    private func refreshConversations(chatStore: TestChatViewModel) async {
        guard let service else {
            return
        }

        do {
            let questions = try await service.fetchQuestions()
            let conversations = await mapConversations(questions, service: service)
            chatStore.replaceConversations(conversations)
        } catch {
            statusMessage = "Supabase chat refresh failed: \(error.localizedDescription)"
        }
    }

    private func mapSeers(_ listings: [SupabaseSeerListing]) -> [CustomerSeer] {
        let tintPalette: [Color] = [.purple, .teal, .orange, .indigo, .pink, .blue]

        return listings.enumerated().map { index, listing in
            let skills = listing.skills.isEmpty ? ["General Reading"] : listing.skills
            let priceCoin = listing.priceCoin ?? 0
            let bio = listing.bio.trimmingCharacters(in: .whitespacesAndNewlines)
            let rating = listing.ratingAverage.map { String(format: "%.1f", $0) } ?? "New"

            return CustomerSeer(
                id: listing.id,
                accountID: listing.id,
                serviceID: listing.serviceID,
                avatarURL: listing.avatarURL.flatMap { URL(string: $0) },
                name: listing.displayName,
                title: skills.first ?? "Horo Seer",
                specialty: bio.isEmpty ? "Live Supabase seer profile." : bio,
                rating: rating,
                reviewCount: listing.ratingCount,
                rate: priceCoin > 0 ? "\(priceCoin) coins" : "Ask",
                nextAvailable: listing.acceptsQuestion ? "Now" : "Unavailable",
                skills: skills,
                styles: listing.serviceID == nil
                    ? ["Profile connected", "Service setup required"]
                    : ["Live Supabase profile", "Question chat enabled"],
                bio: bio.isEmpty ? "This seer profile is loaded from Supabase." : bio,
                tint: tintPalette[index % tintPalette.count]
            )
        }
    }

    private func mapConversations(
        _ questions: [SupabaseQuestion],
        service: SupabaseHoroDataService
    ) async -> [ChatConversation] {
        var conversations: [ChatConversation] = []

        for question in questions {
            let rows = (try? await service.fetchMessages(questionID: question.id)) ?? []
            conversations.append(mapConversation(question, messages: rows))
        }

        return conversations
    }

    private func mapConversation(
        _ question: SupabaseQuestion,
        messages: [SupabaseQuestionMessage]
    ) -> ChatConversation {
        let seer = seers.first { $0.accountID == question.seerID }
        let seerName = seer?.name ?? fallbackSeerName(for: question)
        let mappedMessages = messages.map { message in
            ChatMessage(
                sender: sender(for: message, question: question),
                text: message.content ?? "",
                timestamp: date(from: message.createdAt)
            )
        }

        let resolvedMessages = mappedMessages.isEmpty
            ? [
                ChatMessage(
                    sender: .system,
                    text: "Question created in Supabase.",
                    timestamp: date(from: question.createdAt)
                )
            ]
            : mappedMessages

        return ChatConversation(
            id: question.id,
            seerName: seerName,
            seerId: shortID(question.seerID),
            customerName: signedInRole == .customer ? TestAccount.customer.displayName : "Customer \(shortID(question.userID))",
            customerId: shortID(question.userID),
            topic: "\(question.priceCoin) coin question",
            status: status(from: question.status),
            priority: .normal,
            accountTier: "Supabase",
            waitTime: question.status.capitalized,
            unreadCount: 0,
            tint: seer?.tint ?? .teal,
            messages: resolvedMessages,
            quickReplies: signedInRole == .seer
                ? ["I am reading that now.", "Please share one more detail.", "I will guide you step by step."]
                : ["Thank you.", "Can you explain more?", "I want to book a call."]
        )
    }

    private func fallbackSeerName(for question: SupabaseQuestion) -> String {
        if signedInRole == .seer, question.seerID == signedInAccountID {
            return TestAccount.seer.displayName
        }

        return "Seer \(shortID(question.seerID))"
    }

    private func sender(for message: SupabaseQuestionMessage, question: SupabaseQuestion) -> ChatMessage.Sender {
        guard let senderID = message.senderID else {
            return .system
        }

        return senderID == question.seerID ? .seer : .customer
    }

    private func status(from value: String) -> ConversationStatus {
        switch value.lowercased() {
        case "pending", "submitted", "waiting":
            return .waiting
        case "completed", "closed", "resolved", "cancelled", "expired":
            return .followUp
        default:
            return .active
        }
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).uppercased()
    }

    private func date(from value: String) -> Date {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value) ?? Date()
    }
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
    @ObservedObject var supabaseApp: SupabaseAppViewModel
    @ObservedObject var chatStore: TestChatViewModel
    @Binding var coinBalance: Int
    let appLanguage: AppLanguage

    let onOpenChat: () -> Void

    @State private var selectedMenu: CustomerHomeMenu = .overview
    @State private var seerSearchText = ""

    private let profile = CustomerMockProfile.default
    private let readings = CustomerReading.mockReadings
    private var seers: [CustomerSeer] {
        supabaseApp.seers.isEmpty ? CustomerSeer.mockSeers : supabaseApp.seers
    }

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
                CustomerHeroCard(
                    profile: profile,
                    coinBalance: supabaseApp.walletAvailableCoin ?? coinBalance,
                    appLanguage: appLanguage,
                    onOpenChat: onOpenChat
                )

                DataConnectionBanner(
                    message: supabaseApp.statusMessage,
                    isConnected: supabaseApp.isConnected
                )

                CustomerHomeMenuPicker(selection: $selectedMenu, appLanguage: appLanguage)

                switch selectedMenu {
                case .overview:
                    CustomerReadingStatusCard(reading: readings[0], appLanguage: appLanguage)

                    CustomerActionGrid(
                        appLanguage: appLanguage,
                        onOpenChat: onOpenChat,
                        onFindSeer: { selectedMenu = .findSeer }
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: appLanguage.text("Upcoming Guidance", "คำแนะนำถัดไป"),
                            subtitle: appLanguage.text("Mock customer requests and reading history", "คำขอและประวัติคำทำนายทดสอบ")
                        )

                        LazyVStack(spacing: 10) {
                            ForEach(readings) { reading in
                                CustomerReadingRow(reading: reading, appLanguage: appLanguage)
                            }
                        }
                    }

                    CustomerFeaturedSeersPreview(
                        supabaseApp: supabaseApp,
                        chatStore: chatStore,
                        coinBalance: $coinBalance,
                        seers: Array(seers.prefix(2)),
                        appLanguage: appLanguage,
                        onOpenChat: onOpenChat
                    )
                case .findSeer:
                    CustomerSeerDiscoveryView(
                        searchText: $seerSearchText,
                        supabaseApp: supabaseApp,
                        chatStore: chatStore,
                        coinBalance: $coinBalance,
                        seers: filteredSeers,
                        allSeerCount: seers.count,
                        appLanguage: appLanguage,
                        onOpenChat: onOpenChat
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
    let coinBalance: Int
    let appLanguage: AppLanguage
    let onOpenChat: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ProfilePhotoView(profile: profile.userProfile, size: 64)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(appLanguage.text("Customer Space", "พื้นที่ลูกค้า"))
                        .font(.headline)

                    StatusBadge(title: profile.memberTier, color: .indigo)
                }

                Text(profile.fullName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(appLanguage.text("Next insight window: \(profile.nextInsightWindow)", "รอบคำแนะนำถัดไป: \(profile.nextInsightWindow)"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.teal)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    HoroCoinIcon(size: 16)

                    Text(appLanguage.text("\(coinBalance) coins", "\(coinBalance) เหรียญ"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 8)

            Button(action: onOpenChat) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title2)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(appLanguage.text("Open Chat", "เปิดแชท"))
        }
        .padding(16)
        .cardStyle()
    }
}

private struct CustomerReadingStatusCard: View {
    let reading: CustomerReading
    let appLanguage: AppLanguage

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
                    Text(appLanguage.text("Active Reading", "คำทำนายที่กำลังดำเนินการ"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(reading.color)

                    Text(reading.title(in: appLanguage))
                        .font(.headline)

                    Text(reading.subtitle(in: appLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                ConversationMetaChip(title: reading.status(in: appLanguage), color: reading.color, icon: "sparkles")
                ConversationMetaChip(title: reading.timeframe(in: appLanguage), color: .blue, icon: "calendar")
            }
        }
        .padding(16)
        .cardStyle(borderColor: reading.color.opacity(0.35))
    }
}

private struct CustomerActionGrid: View {
    let appLanguage: AppLanguage
    let onOpenChat: () -> Void
    let onFindSeer: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            CustomerActionTile(
                title: appLanguage.text("Ask Seer", "ถามหมอดู"),
                subtitle: appLanguage.text("Start a chat", "เริ่มแชท"),
                icon: "bubble.left.and.bubble.right.fill",
                color: .teal,
                action: onOpenChat
            )

            CustomerActionTile(
                title: appLanguage.text("Find Seer", "ค้นหาหมอดู"),
                subtitle: appLanguage.text("Search guides", "ค้นหาผู้แนะนำ"),
                icon: "person.2.fill",
                color: .purple,
                action: onFindSeer
            )

            CustomerActionTile(
                title: appLanguage.text("Daily Card", "ไพ่ประจำวัน"),
                subtitle: appLanguage.text("Preview insight", "ดูคำแนะนำสั้น ๆ"),
                icon: "rectangle.stack.fill",
                color: .orange,
                action: {}
            )

            CustomerActionTile(
                title: appLanguage.text("Saved Notes", "บันทึกที่เก็บไว้"),
                subtitle: appLanguage.text("3 entries", "3 รายการ"),
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
    let appLanguage: AppLanguage

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
                Text(reading.title(in: appLanguage))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(reading.subtitle(in: appLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(reading.status(in: appLanguage))
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
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .overview:
            return language.text("Overview", "ภาพรวม")
        case .findSeer:
            return language.text("Find Seer", "ค้นหาหมอดู")
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
    let appLanguage: AppLanguage

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CustomerHomeMenu.allCases) { menu in
                Button {
                    withAnimation(.snappy) {
                        selection = menu
                    }
                } label: {
                    Label(menu.title(in: appLanguage), systemImage: menu.icon)
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
                .accessibilityLabel(menu.title(in: appLanguage))
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
    @ObservedObject var supabaseApp: SupabaseAppViewModel
    @ObservedObject var chatStore: TestChatViewModel
    @Binding var coinBalance: Int

    let seers: [CustomerSeer]
    let appLanguage: AppLanguage
    let onOpenChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: appLanguage.text("Suggested Seers", "หมอดูแนะนำ"),
                subtitle: appLanguage.text("Popular guides based on your recent focus", "ผู้แนะนำยอดนิยมตามเรื่องที่คุณสนใจ")
            )

            LazyVStack(spacing: 12) {
                ForEach(seers) { seer in
                    NavigationLink {
                        CustomerSeerProfileView(
                            seer: seer,
                            supabaseApp: supabaseApp,
                            chatStore: chatStore,
                            coinBalance: $coinBalance,
                            appLanguage: appLanguage,
                            onOpenChat: onOpenChat
                        )
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
    @ObservedObject var supabaseApp: SupabaseAppViewModel
    @ObservedObject var chatStore: TestChatViewModel
    @Binding var coinBalance: Int

    let seers: [CustomerSeer]
    let allSeerCount: Int
    let appLanguage: AppLanguage
    let onOpenChat: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: appLanguage.text("Find Seer", "ค้นหาหมอดู"),
                subtitle: appLanguage.text("\(seers.count) of \(allSeerCount) mock seers", "พบ \(seers.count) จาก \(allSeerCount) รายการ")
            )

            ConversationSearchField(
                text: $searchText,
                placeholder: appLanguage.text("Search seer, skill, or style", "ค้นหาหมอดู ทักษะ หรือสไตล์"),
                clearLabel: appLanguage.text("Clear Search", "ล้างการค้นหา")
            )

            if seers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(appLanguage.text("No seers found", "ไม่พบหมอดู"))
                        .font(.headline)

                    Text(appLanguage.text("Try a skill like relationship, tarot, career, or astrology.", "ลองค้นหาทักษะ เช่น ความรัก ไพ่ทาโรต์ งาน หรือโหราศาสตร์"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .padding(16)
                .cardStyle()
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(seers) { seer in
                        NavigationLink {
                            CustomerSeerProfileView(
                                seer: seer,
                                supabaseApp: supabaseApp,
                                chatStore: chatStore,
                                coinBalance: $coinBalance,
                                appLanguage: appLanguage,
                                onOpenChat: onOpenChat
                            )
                        } label: {
                            CustomerSeerGridCard(seer: seer)
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
            CustomerSeerPhotoView(seer: seer, width: 64, height: 72)

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
                    CoinMetaChip(title: seer.rate)
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

private struct CustomerSeerGridCard: View {
    let seer: CustomerSeer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomerSeerPhotoView(seer: seer, height: 104)
                .overlay(alignment: .topTrailing) {
                    Label(seer.rating, systemImage: "star.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(8)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(seer.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(seer.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(seer.tint)
                    .lineLimit(2)

                Text(seer.specialty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                ForEach(Array(seer.skills.prefix(2)), id: \.self) { skill in
                    SeerTag(title: skill, color: seer.tint)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                CoinMetaChip(title: seer.rate)
                ConversationMetaChip(title: seer.nextAvailable, color: .green, icon: "clock.fill")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 232, alignment: .topLeading)
        .padding(12)
        .cardStyle(borderColor: seer.tint.opacity(0.32))
    }
}

private struct CustomerSeerPhotoView: View {
    let seer: CustomerSeer
    var width: CGFloat?
    let height: CGFloat

    var body: some View {
        ZStack {
            if let avatarURL = seer.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        seerPlaceholder
                    @unknown default:
                        seerPlaceholder
                    }
                }
            } else {
                seerPlaceholder
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.28), lineWidth: 1)
        }
        .accessibilityLabel("\(seer.name) Profile Picture")
    }

    private var seerPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: seer.pictureColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: "sparkles")
                .font(.system(size: height * 0.34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.22))
                .offset(x: height * 0.26, y: -height * 0.18)

            Text(seer.initials)
                .font(.system(size: height * 0.24, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        }
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
    @ObservedObject var supabaseApp: SupabaseAppViewModel
    @ObservedObject var chatStore: TestChatViewModel
    @Binding var coinBalance: Int
    let appLanguage: AppLanguage

    let onOpenChat: () -> Void

    @State private var isAddFundsSheetPresented = false
    @State private var activeNotice: CustomerSeerActionNotice?
    @State private var topUpReason = ""

    private let skillColumns = [
        GridItem(.adaptive(minimum: 112), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CustomerSeerProfileHero(
                    seer: seer,
                    coinBalance: coinBalance,
                    appLanguage: appLanguage,
                    onBookReading: bookReading,
                    onMessage: messageSeer,
                    onAddCoins: {
                        topUpReason = appLanguage.text("Add THB to coins to book or call \(seer.name).", "เติม THB เป็นเหรียญเพื่อจองหรือโทรหา \(seer.name)")
                        isAddFundsSheetPresented = true
                    }
                )

                SeerCallOptionsSection(
                    seer: seer,
                    coinBalance: coinBalance,
                    appLanguage: appLanguage,
                    onSelect: handleCallOption
                )

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: appLanguage.text("Skills", "ทักษะ"),
                        subtitle: appLanguage.text("What this seer can help with", "เรื่องที่หมอดูคนนี้ช่วยได้")
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
                        title: appLanguage.text("Styles", "สไตล์การดู"),
                        subtitle: appLanguage.text("How the reading usually feels", "บรรยากาศของคำทำนาย")
                    )

                    LazyVStack(spacing: 10) {
                        ForEach(seer.styles, id: \.self) { style in
                            SeerStyleRow(title: style, tint: seer.tint)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(
                        title: appLanguage.text("Profile", "โปรไฟล์"),
                        subtitle: appLanguage.text("Mock seer introduction", "แนะนำหมอดูแบบทดสอบ")
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
        .sheet(isPresented: $isAddFundsSheetPresented) {
            AddFundsSheet(
                coinBalance: $coinBalance,
                reason: topUpReason.isEmpty ? appLanguage.text("Add THB to coins before starting a seer call.", "เติม THB เป็นเหรียญก่อนเริ่มโทรหาหมอดู") : topUpReason,
                appLanguage: appLanguage
            )
        }
        .alert(item: $activeNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text(appLanguage.text("OK", "ตกลง")))
            )
        }
    }

    private func bookReading() {
        activeNotice = CustomerSeerActionNotice(
            title: appLanguage.text("Booking Requested", "ส่งคำขอจองแล้ว"),
            message: appLanguage.text("A mock reading request was sent to \(seer.name).", "ส่งคำขอทำนายทดสอบไปหา \(seer.name) แล้ว")
        )
    }

    private func messageSeer() {
        Task {
            let didStartLiveQuestion = await supabaseApp.startQuestion(
                with: seer,
                firstMessage: appLanguage.text("Hi \(seer.name), I would like to start a reading.", "สวัสดี \(seer.name) ฉันอยากเริ่มดูดวง"),
                chatStore: chatStore
            )

            if !didStartLiveQuestion {
                chatStore.startConversation(
                    with: seer,
                    firstMessage: appLanguage.text("Hi \(seer.name), I would like to start a reading.", "สวัสดี \(seer.name) ฉันอยากเริ่มดูดวง")
                )
            }
        }

        onOpenChat()
    }

    private func handleCallOption(_ option: SeerCallOption) {
        guard coinBalance >= option.coinCost else {
            topUpReason = appLanguage.text("\(option.title(in: appLanguage)) with \(seer.name) requires \(option.coinCost) coins.", "\(option.title(in: appLanguage)) กับ \(seer.name) ต้องใช้ \(option.coinCost) เหรียญ")
            isAddFundsSheetPresented = true
            return
        }

        coinBalance -= option.coinCost
        activeNotice = CustomerSeerActionNotice(
            title: appLanguage.text("Call Booked", "จองสายแล้ว"),
            message: appLanguage.text("\(option.title(in: appLanguage)) with \(seer.name) is booked. \(option.coinCost) coins were used.", "จอง \(option.title(in: appLanguage)) กับ \(seer.name) แล้ว ใช้ \(option.coinCost) เหรียญ")
        )
    }
}

private struct CustomerSeerProfileHero: View {
    let seer: CustomerSeer
    let coinBalance: Int
    let appLanguage: AppLanguage
    let onBookReading: () -> Void
    let onMessage: () -> Void
    let onAddCoins: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            CustomerSeerPhotoView(seer: seer, height: 180)

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
                ConversationMetaChip(title: appLanguage.text("\(seer.rating) rating", "คะแนน \(seer.rating)"), color: .yellow, icon: "star.fill")
                ConversationMetaChip(title: appLanguage.text("\(seer.reviewCount) reviews", "\(seer.reviewCount) รีวิว"), color: .blue, icon: "text.bubble.fill")
                ConversationMetaChip(title: seer.nextAvailable, color: .green, icon: "clock.fill")
            }

            HStack(spacing: 8) {
                CoinMetaChip(title: appLanguage.text("\(coinBalance) coins", "\(coinBalance) เหรียญ"), color: .indigo)

                Button(action: onAddCoins) {
                    Label(appLanguage.text("Add Coins", "เติมเหรียญ"), systemImage: "plus.circle.fill")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Button(action: onMessage) {
                    Label(appLanguage.text("Message", "ส่งข้อความ"), systemImage: "bubble.left.and.bubble.right.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: onBookReading) {
                    Label(appLanguage.text("Book", "จอง"), systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(16)
        .cardStyle(borderColor: seer.tint.opacity(0.34))
    }
}

private struct SeerCallOptionsSection: View {
    let seer: CustomerSeer
    let coinBalance: Int
    let appLanguage: AppLanguage
    let onSelect: (SeerCallOption) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 96), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: appLanguage.text("Call Seer", "โทรหาหมอดู"),
                subtitle: appLanguage.text("Calls use your in-app coins", "การโทรใช้เหรียญในแอป")
            )

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(SeerCallOption.allCases) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: option.icon)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(seer.tint)

                                HoroCoinIcon(size: 22)
                            }

                            Text(option.title(in: appLanguage))
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)

                            HStack(spacing: 5) {
                                HoroCoinIcon(size: 14)

                                Text(appLanguage.text("\(option.coinCost) coins", "\(option.coinCost) เหรียญ"))
                                    .font(.caption.weight(.bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                            }
                            .foregroundStyle(coinBalance >= option.coinCost ? .green : .orange)
                        }
                        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
                        .padding(12)
                        .cardStyle(borderColor: seer.tint.opacity(0.28))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(appLanguage.text("Book \(option.title(in: appLanguage))", "จอง \(option.title(in: appLanguage))"))
                }
            }
        }
    }
}

private enum SeerCallOption: String, CaseIterable, Identifiable {
    case fifteen
    case thirty
    case sixty

    var id: String { rawValue }

    var title: String {
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .fifteen:
            return language.text("15 mins", "15 นาที")
        case .thirty:
            return language.text("30 mins", "30 นาที")
        case .sixty:
            return language.text("1 hr", "1 ชม.")
        }
    }

    var coinCost: Int {
        switch self {
        case .fifteen:
            return 199
        case .thirty:
            return 349
        case .sixty:
            return 599
        }
    }

    var icon: String {
        switch self {
        case .fifteen:
            return "phone.fill"
        case .thirty:
            return "phone.connection.fill"
        case .sixty:
            return "phone.circle.fill"
        }
    }
}

private struct CustomerSeerActionNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
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
    @ObservedObject var chatStore: TestChatViewModel
    @ObservedObject var supabaseApp: SupabaseAppViewModel
    let appLanguage: AppLanguage

    private var conversations: [ChatConversation] {
        chatStore.conversations
    }

    private var title: String {
        appLanguage == .thai ? "แชทกับหมอดู" : "My Seer Chats"
    }

    private var subtitle: String {
        appLanguage == .thai ? "ข้อความทดสอบผ่าน mock API" : "Shared test API messages"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: title,
                        subtitle: subtitle
                    )

                    LazyVStack(spacing: 12) {
                        ForEach(conversations) { conversation in
                            NavigationLink {
                                CustomerChatDetailView(
                                    conversationID: conversation.id,
                                    chatStore: chatStore,
                                    supabaseApp: supabaseApp,
                                    appLanguage: appLanguage
                                )
                            } label: {
                                CustomerConversationRow(conversation: conversation, appLanguage: appLanguage)
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
    let conversation: ChatConversation
    let appLanguage: AppLanguage

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
                    title: conversation.status.title(in: appLanguage),
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
    let conversationID: UUID
    @ObservedObject var chatStore: TestChatViewModel
    @ObservedObject var supabaseApp: SupabaseAppViewModel
    let appLanguage: AppLanguage

    @State private var draft = ""

    private var conversation: ChatConversation {
        chatStore.conversation(id: conversationID) ?? .emptyTestConversation
    }

    var body: some View {
        VStack(spacing: 0) {
            CustomerChatHeader(conversation: conversation, appLanguage: appLanguage)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(conversation.messages) { message in
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
                .onChange(of: conversation.messages.count) { _, _ in
                    scrollToLatestMessage(with: proxy)
                }
            }

            ChatComposer(
                draft: $draft,
                placeholder: appLanguage.text("Message seer", "ส่งข้อความถึงหมอดู"),
                quickReplies: conversation.quickReplies,
                attachLabel: appLanguage.text("Attach File", "แนบไฟล์"),
                sendLabel: appLanguage.text("Send Message", "ส่งข้อความ"),
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

        draft = ""

        Task {
            let didSendToSupabase = await supabaseApp.sendMessage(
                conversationID: conversationID,
                sender: .customer,
                text: cleanDraft,
                chatStore: chatStore
            )

            if !didSendToSupabase {
                chatStore.sendMessage(
                    conversationID: conversationID,
                    sender: .customer,
                    text: cleanDraft
                )
            }
        }
    }

    private func scrollToLatestMessage(with proxy: ScrollViewProxy) {
        guard let id = conversation.messages.last?.id else {
            return
        }

        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }
}

private struct CustomerChatHeader: View {
    let conversation: ChatConversation
    let appLanguage: AppLanguage

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
                    title: conversation.status.title(in: appLanguage),
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
    @Binding var appAppearance: AppAppearance
    @Binding var appLanguage: AppLanguage

    let testAccount: TestAccount

    @Binding var coinBalance: Int

    let onLogout: () -> Void

    @State private var isAddFundsSheetPresented = false
    @State private var editableProfile = CustomerMockProfile.default.userProfile

    private let profileDetails = CustomerMockProfile.default

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 14) {
                    ProfilePhotoView(
                        profile: editableProfile,
                        size: 138,
                        showsCameraBadge: true
                    )

                    VStack(spacing: 5) {
                        Text(editableProfile.fullName)
                            .font(.title2.bold())

                        Text(editableProfile.location)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            StatusBadge(title: appLanguage.text("Customer", "ลูกค้า"), color: .indigo)
                            StatusBadge(title: profileDetails.memberTier, color: .teal)
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(22)
                .cardStyle()

                CustomerWalletSection(
                    coinBalance: coinBalance,
                    appLanguage: appLanguage,
                    onAddCoins: { isAddFundsSheetPresented = true }
                )

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: appLanguage.text("Account", "บัญชี"), subtitle: appLanguage.text("Mock customer information", "ข้อมูลลูกค้าแบบทดสอบ"))

                    VStack(spacing: 0) {
                        ProfileDetailRow(icon: "person.text.rectangle", title: appLanguage.text("Test Login", "ล็อกอินทดสอบ"), value: testAccount.login, appLanguage: appLanguage)
                        Divider().padding(.leading, 40)
                        ProfileDetailRow(icon: "at", title: appLanguage.text("Test Email", "อีเมลทดสอบ"), value: testAccount.email, appLanguage: appLanguage)
                        Divider().padding(.leading, 40)
                        ProfileDetailRow(icon: "envelope", title: appLanguage.text("Email", "อีเมล"), value: editableProfile.email, appLanguage: appLanguage)
                        Divider().padding(.leading, 40)
                        ProfileDetailRow(icon: "sparkles", title: appLanguage.text("Focus", "เรื่องที่สนใจ"), value: profileDetails.focus(in: appLanguage), appLanguage: appLanguage)
                        Divider().padding(.leading, 40)
                        ProfileDetailRow(icon: "calendar", title: appLanguage.text("Birth Info", "ข้อมูลเกิด"), value: editableProfile.location, appLanguage: appLanguage)
                    }
                    .padding(.vertical, 4)
                    .cardStyle()
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: appLanguage.text("Preferences", "การตั้งค่า"), subtitle: appLanguage.profilePreferenceSubtitle)

                    VStack(spacing: 0) {
                        ProfileDetailRow(icon: "bell.badge", title: appLanguage.text("Reading Alerts", "แจ้งเตือนคำทำนาย"), value: appLanguage.text("Enabled", "เปิดใช้งาน"), appLanguage: appLanguage)
                        Divider().padding(.leading, 40)
                        ProfileDetailRow(icon: "lock.shield", title: appLanguage.text("Role Access", "สิทธิ์บทบาท"), value: appLanguage.text("Customer", "ลูกค้า"), appLanguage: appLanguage)
                        Divider().padding(.leading, 40)
                        AppearancePickerRow(selection: $appAppearance, appLanguage: appLanguage)
                        Divider().padding(.leading, 40)
                        LanguagePickerRow(selection: $appLanguage)
                    }
                    .padding(.vertical, 4)
                    .cardStyle()
                }

                ProfileLogoutButton(appLanguage: appLanguage, action: onLogout)
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
                        profile: editableProfile,
                        appLanguage: appLanguage,
                        onSave: { editableProfile = $0 }
                    )
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(appLanguage.editProfileTitle)
            }
        }
        .sheet(isPresented: $isAddFundsSheetPresented) {
            AddFundsSheet(
                coinBalance: $coinBalance,
                reason: appLanguage.text("Add THB to get coins for readings and seer calls.", "เติม THB เพื่อรับเหรียญสำหรับคำทำนายและการโทรหาหมอดู"),
                appLanguage: appLanguage
            )
        }
    }
}

private struct CustomerWalletSection: View {
    let coinBalance: Int
    let appLanguage: AppLanguage
    let onAddCoins: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: appLanguage.text("Coin Wallet", "กระเป๋าเหรียญ"), subtitle: appLanguage.text("Add THB to get in-app coins", "เติม THB เพื่อรับเหรียญในแอป"))

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    HoroCoinIcon(size: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appLanguage.text("\(coinBalance) coins", "\(coinBalance) เหรียญ"))
                            .font(.title3.bold().monospacedDigit())

                        Text(appLanguage.text("Coins are used for seer calls and paid readings", "เหรียญใช้สำหรับโทรหาหมอดูและคำทำนายแบบชำระเงิน"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)
                }

                Button(action: onAddCoins) {
                    Label(appLanguage.text("Add THB to Coins", "เติม THB เป็นเหรียญ"), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(16)
            .cardStyle(borderColor: Color.orange.opacity(0.34))
        }
    }
}

private struct AddFundsSheet: View {
    @Binding var coinBalance: Int

    let reason: String
    let appLanguage: AppLanguage

    @Environment(\.dismiss) private var dismiss
    @State private var selectedOption = WalletTopUpOption.options[1]
    @State private var selectedMethod: MockPaymentMethod = .applePay
    @State private var didCompletePayment = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appLanguage.text("Current Balance", "ยอดคงเหลือปัจจุบัน"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        HStack(alignment: .center, spacing: 10) {
                            HoroCoinIcon(size: 40)

                            Text("\(coinBalance)")
                                .font(.largeTitle.bold().monospacedDigit())

                            Text(appLanguage.text("coins", "เหรียญ"))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }

                        Text(reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .cardStyle(borderColor: Color.orange.opacity(0.34))

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: appLanguage.text("Top Up", "เติมเงิน"), subtitle: appLanguage.text("Pay THB and receive in-app coins", "ชำระ THB แล้วรับเหรียญในแอป"))

                        LazyVStack(spacing: 10) {
                            ForEach(WalletTopUpOption.options) { option in
                                Button {
                                    selectedOption = option
                                } label: {
                                    WalletTopUpOptionRow(
                                        option: option,
                                        isSelected: selectedOption == option,
                                        appLanguage: appLanguage
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: appLanguage.text("Payment", "การชำระเงิน"), subtitle: appLanguage.text("Mock payment method", "วิธีชำระเงินทดสอบ"))

                        LazyVStack(spacing: 10) {
                            ForEach(MockPaymentMethod.allCases) { method in
                                Button {
                                    selectedMethod = method
                                } label: {
                                    MockPaymentMethodRow(
                                        method: method,
                                        isSelected: selectedMethod == method,
                                        appLanguage: appLanguage
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button(action: completePayment) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                            Text(appLanguage.text("Pay \(selectedOption.priceLabel)", "ชำระ \(selectedOption.priceLabel)"))
                            HoroCoinIcon(size: 18)
                            Text(appLanguage.text("+\(selectedOption.coins) coins", "+\(selectedOption.coins) เหรียญ"))
                        }
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(16)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle(appLanguage.text("Add Coins", "เติมเหรียญ"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appLanguage.text("Close", "ปิด")) {
                        dismiss()
                    }
                }
            }
            .alert(appLanguage.text("Payment Complete", "ชำระเงินสำเร็จ"), isPresented: $didCompletePayment) {
                Button(appLanguage.text("Done", "เสร็จ")) {
                    dismiss()
                }
            } message: {
                Text(appLanguage.text("\(selectedOption.coins) coins were added after paying \(selectedOption.priceLabel) with \(selectedMethod.title(in: appLanguage)).", "เพิ่ม \(selectedOption.coins) เหรียญหลังชำระ \(selectedOption.priceLabel) ด้วย \(selectedMethod.title(in: appLanguage))"))
            }
        }
    }

    private func completePayment() {
        coinBalance += selectedOption.coins
        didCompletePayment = true
    }
}

private struct WalletTopUpOptionRow: View {
    let option: WalletTopUpOption
    let isSelected: Bool
    let appLanguage: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isSelected ? .teal : .secondary)

            HoroCoinIcon(size: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(appLanguage.text("\(option.coins) coins", "\(option.coins) เหรียญ"))
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(option.subtitle(in: appLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(option.priceLabel)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(14)
        .cardStyle(borderColor: isSelected ? Color.teal.opacity(0.48) : AppColors.border)
    }
}

private struct WalletTopUpOption: Identifiable, Equatable {
    let id: String
    let coins: Int
    let priceLabel: String
    let subtitle: String

    func subtitle(in language: AppLanguage) -> String {
        switch id {
        case "starter":
            return language.text(subtitle, "แพ็กเริ่มต้นสำหรับสายสั้น")
        case "popular":
            return language.text(subtitle, "แพ็กยอดนิยมสำหรับแชทและสาย 30 นาที")
        case "deep":
            return language.text(subtitle, "แพ็กอ่านดวงเชิงลึกสำหรับเวลานาน")
        default:
            return subtitle
        }
    }

    static let options = [
        WalletTopUpOption(
            id: "starter",
            coins: 200,
            priceLabel: "THB 200",
            subtitle: "Starter coin pack for short calls"
        ),
        WalletTopUpOption(
            id: "popular",
            coins: 500,
            priceLabel: "THB 500",
            subtitle: "Popular coin pack for chat and 30 min calls"
        ),
        WalletTopUpOption(
            id: "deep",
            coins: 1_000,
            priceLabel: "THB 1,000",
            subtitle: "Deep reading coin pack for longer sessions"
        )
    ]
}

private enum MockPaymentMethod: String, CaseIterable, Identifiable {
    case applePay
    case card
    case qrPayment
    case promo

    var id: String { rawValue }

    var title: String {
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .applePay:
            return "Apple Pay"
        case .card:
            return language.text("Card", "บัตร")
        case .qrPayment:
            return language.text("QR Payment", "ชำระผ่าน QR")
        case .promo:
            return language.text("Promo", "โค้ดโปรโมชัน")
        }
    }

    var icon: String {
        switch self {
        case .applePay:
            return "apple.logo"
        case .card:
            return "banknote.fill"
        case .qrPayment:
            return "qrcode"
        case .promo:
            return "giftcard.fill"
        }
    }
}

private struct MockPaymentMethodRow: View {
    let method: MockPaymentMethod
    let isSelected: Bool
    let appLanguage: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: method.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(isSelected ? .teal : .secondary)
                .frame(width: 28)

            Text(method.title(in: appLanguage))
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .teal : .secondary)
        }
        .padding(14)
        .cardStyle(borderColor: isSelected ? Color.teal.opacity(0.48) : AppColors.border)
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
            location: birthInfo,
            avatarStyle: .sunrise
        )
    }

    func focus(in language: AppLanguage) -> String {
        language.text(focus, "ความรักและจังหวะเวลา")
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
    let id: UUID
    let accountID: UUID?
    let serviceID: UUID?
    let avatarURL: URL?
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

    init(
        id: UUID = UUID(),
        accountID: UUID? = nil,
        serviceID: UUID? = nil,
        avatarURL: URL? = nil,
        name: String,
        title: String,
        specialty: String,
        rating: String,
        reviewCount: Int,
        rate: String,
        nextAvailable: String,
        skills: [String],
        styles: [String],
        bio: String,
        tint: Color
    ) {
        self.id = id
        self.accountID = accountID
        self.serviceID = serviceID
        self.avatarURL = avatarURL
        self.name = name
        self.title = title
        self.specialty = specialty
        self.rating = rating
        self.reviewCount = reviewCount
        self.rate = rate
        self.nextAvailable = nextAvailable
        self.skills = skills
        self.styles = styles
        self.bio = bio
        self.tint = tint
    }

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

    var pictureColors: [Color] {
        [
            tint.opacity(0.92),
            Color.blue.opacity(0.72),
            Color.indigo.opacity(0.88)
        ]
    }

    static let mockSeers = [
        CustomerSeer(
            name: "Aurora Veil",
            title: "Relationship Timing Seer",
            specialty: "Soft guidance for love, reconnecting, and emotional timing.",
            rating: "4.9",
            reviewCount: 218,
            rate: "180 coins",
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
            rate: "150 coins",
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
            rate: "90 coins",
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
            rate: "210 coins",
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
            rate: "120 coins",
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

    func title(in language: AppLanguage) -> String {
        switch title {
        case "Relationship Timing":
            return language.text(title, "จังหวะความรัก")
        case "Career Crossroads":
            return language.text(title, "ทางแยกเรื่องงาน")
        case "Daily Energy":
            return language.text(title, "พลังงานประจำวัน")
        default:
            return title
        }
    }

    func subtitle(in language: AppLanguage) -> String {
        switch title {
        case "Relationship Timing":
            return language.text(subtitle, "Aurora กำลังเตรียมคำทำนายถัดไปของคุณ")
        case "Career Crossroads":
            return language.text(subtitle, "คำแนะนำที่บันทึกไว้จากครั้งก่อน")
        case "Daily Energy":
            return language.text(subtitle, "พรีวิวไพ่สั้น ๆ สำหรับเช้านี้")
        default:
            return subtitle
        }
    }

    func status(in language: AppLanguage) -> String {
        switch status {
        case "In Progress":
            return language.text(status, "กำลังดำเนินการ")
        case "Saved":
            return language.text(status, "บันทึกแล้ว")
        case "Ready":
            return language.text(status, "พร้อมแล้ว")
        default:
            return status
        }
    }

    func timeframe(in language: AppLanguage) -> String {
        switch timeframe {
        case "Today":
            return language.text(timeframe, "วันนี้")
        case "Yesterday":
            return language.text(timeframe, "เมื่อวาน")
        case "Daily":
            return language.text(timeframe, "รายวัน")
        default:
            return timeframe
        }
    }

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
    let appLanguage: AppLanguage

    private let conversations = ChatConversation.mockConversations

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SeerDashboardHeader(
                    profile: profile,
                    activeCount: activeCount,
                    appLanguage: appLanguage,
                    onViewProfile: onViewProfile
                )

                RoleOverviewSection(activeRole: .seer, appLanguage: appLanguage)

                OperationsMetricsGrid(
                    queueCount: conversations.count,
                    activeCount: activeCount,
                    completedCount: completedCount,
                    appLanguage: appLanguage
                )

                WorkQueuePreview(
                    conversations: Array(conversations.prefix(2)),
                    appLanguage: appLanguage,
                    onOpenChat: onOpenChat
                )

                RecordsSectionHeader(onCreate: onCreateRecord, appLanguage: appLanguage)

                if records.isEmpty {
                    EmptyRecordsView(onCreate: onCreateRecord, appLanguage: appLanguage)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(records) { record in
                            RecordCard(
                                record: record,
                                appLanguage: appLanguage,
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
    let appLanguage: AppLanguage
    let onViewProfile: () -> Void

    var body: some View {
        Button(action: onViewProfile) {
            HStack(spacing: 14) {
                ProfilePhotoView(profile: profile, size: 62)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(appLanguage.text("Seer Operation", "งานหมอดู"))
                            .font(.headline)
                            .foregroundStyle(.primary)

                        StatusBadge(title: appLanguage.text("On Duty", "กำลังปฏิบัติงาน"), color: .green)
                    }

                    Text(profile.fullName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.caption2)

                        Text(appLanguage.text("\(activeCount) active reading notes", "บันทึกที่กำลังทำ \(activeCount) รายการ"))
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
    let appLanguage: AppLanguage

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            MetricTile(title: appLanguage.text("Queue", "คิว"), value: queueCount, color: .blue, icon: "person.2.wave.2.fill")
            MetricTile(title: appLanguage.text("Active", "กำลังทำ"), value: activeCount, color: .teal, icon: "timer")
            MetricTile(title: appLanguage.text("Done", "เสร็จแล้ว"), value: completedCount, color: .green, icon: "checkmark.seal")
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
    let appLanguage: AppLanguage
    let onOpenChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(
                    title: appLanguage.text("Priority Queue", "คิวสำคัญ"),
                    subtitle: appLanguage.text("Customer readings needing seer action", "คำทำนายที่รอหมอดูดำเนินการ")
                )

                Spacer()

                Button(action: onOpenChat) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel(appLanguage.text("Open Chat", "เปิดแชท"))
            }

            LazyVStack(spacing: 10) {
                ForEach(conversations) { conversation in
                    QueuePreviewRow(conversation: conversation, appLanguage: appLanguage)
                }
            }
        }
    }
}

private struct QueuePreviewRow: View {
    let conversation: ChatConversation
    let appLanguage: AppLanguage

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
                title: conversation.priority.title(in: appLanguage),
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
    let appLanguage: AppLanguage

    var body: some View {
        HStack {
            SectionHeader(
                title: appLanguage.text("Reading Notes", "บันทึกคำทำนาย"),
                subtitle: appLanguage.text("Create, update, complete, or delete seer notes", "สร้าง แก้ไข ทำเสร็จ หรือลบบันทึกงานหมอดู")
            )

            Spacer()

            Button(action: onCreate) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .accessibilityLabel(appLanguage.addRecordTitle)
        }
        .padding(.top, 2)
    }
}

private struct EmptyRecordsView: View {
    let onCreate: () -> Void
    let appLanguage: AppLanguage

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.blue)

            VStack(spacing: 6) {
                Text(appLanguage.text("No Records Yet", "ยังไม่มีบันทึก"))
                    .font(.title3.bold())

                Text(appLanguage.text("Add the first seer note for this mock reading flow.", "เพิ่มบันทึกแรกสำหรับขั้นตอนคำทำนายทดสอบ"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onCreate) {
                Label(appLanguage.addRecordTitle, systemImage: "plus.circle.fill")
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
    let appLanguage: AppLanguage
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
            .accessibilityLabel(record.isCompleted ? appLanguage.text("Reopen Record", "เปิดบันทึกอีกครั้ง") : appLanguage.text("Complete Record", "ทำบันทึกเสร็จ"))

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(record.title)
                            .font(.headline)
                            .foregroundStyle(record.isCompleted ? .secondary : .primary)
                            .strikethrough(record.isCompleted)
                            .lineLimit(2)

                        if record.isCompleted {
                            StatusBadge(title: appLanguage.text("Done", "เสร็จแล้ว"), color: .green)
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
                    Label(appLanguage.text("Edit", "แก้ไข"), systemImage: "pencil")
                }

                Button(action: onToggle) {
                    Label(
                        record.isCompleted ? appLanguage.text("Reopen", "เปิดอีกครั้ง") : appLanguage.text("Mark Done", "ทำเสร็จ"),
                        systemImage: record.isCompleted ? "arrow.uturn.left.circle" : "checkmark.circle"
                    )
                }

                Button(role: .destructive, action: onDelete) {
                    Label(appLanguage.text("Delete", "ลบ"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel(appLanguage.text("Record Actions", "เมนูบันทึก"))
        }
        .padding(14)
        .cardStyle(borderColor: record.isCompleted ? Color.green.opacity(0.35) : AppColors.border)
        .contextMenu {
            Button(action: onEdit) {
                Label(appLanguage.text("Edit", "แก้ไข"), systemImage: "pencil")
            }

            Button(action: onToggle) {
                Label(
                    record.isCompleted ? appLanguage.text("Reopen", "เปิดอีกครั้ง") : appLanguage.text("Mark Done", "ทำเสร็จ"),
                    systemImage: record.isCompleted ? "arrow.uturn.left.circle" : "checkmark.circle"
                )
            }

            Button(role: .destructive, action: onDelete) {
                Label(appLanguage.text("Delete", "ลบ"), systemImage: "trash")
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
    @Binding var appAppearance: AppAppearance
    @Binding var appLanguage: AppLanguage

    let testAccount: TestAccount
    let onLogout: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ProfileHeroCard(profile: profileViewModel.profile, appLanguage: appLanguage)

                RoleOverviewSection(activeRole: .seer, appLanguage: appLanguage)

                ProfileContactSection(
                    profile: profileViewModel.profile,
                    testAccount: testAccount,
                    appLanguage: appLanguage
                )

                ProfileActivitySection(
                    totalCount: totalCount,
                    activeCount: activeCount,
                    completedCount: completedCount,
                    appLanguage: appLanguage,
                    onCreateRecord: onCreateRecord
                )

                ProfileSettingsSection(
                    appAppearance: $appAppearance,
                    appLanguage: $appLanguage
                )

                ProfileLogoutButton(appLanguage: appLanguage, action: onLogout)
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
                        appLanguage: appLanguage,
                        onSave: { profileViewModel.update(profile: $0) }
                    )
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(appLanguage.editProfileTitle)
            }
        }
    }
}

private struct ProfileHeroCard: View {
    let profile: UserProfile
    let appLanguage: AppLanguage

    var body: some View {
        VStack(spacing: 14) {
            ProfilePhotoView(
                profile: profile,
                size: 138,
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
                    StatusBadge(title: appLanguage.text("Seer", "หมอดู"), color: .teal)
                    StatusBadge(title: appLanguage.text("On Duty", "กำลังปฏิบัติงาน"), color: .green)
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
    let testAccount: TestAccount
    let appLanguage: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: appLanguage.text("Contact", "ติดต่อ"), subtitle: appLanguage.text("Seer profile detail", "รายละเอียดโปรไฟล์หมอดู"))

            VStack(spacing: 0) {
                ProfileDetailRow(icon: "person.text.rectangle", title: appLanguage.text("Test Login", "ล็อกอินทดสอบ"), value: testAccount.login, appLanguage: appLanguage)
                Divider().padding(.leading, 40)
                ProfileDetailRow(icon: "at", title: appLanguage.text("Test Email", "อีเมลทดสอบ"), value: testAccount.email, appLanguage: appLanguage)
                Divider().padding(.leading, 40)
                ProfileDetailRow(icon: "envelope", title: appLanguage.text("Email", "อีเมล"), value: profile.email, appLanguage: appLanguage)
                Divider().padding(.leading, 40)
                ProfileDetailRow(icon: "phone", title: appLanguage.text("Phone", "โทรศัพท์"), value: profile.phone, appLanguage: appLanguage)
                Divider().padding(.leading, 40)
                ProfileDetailRow(icon: "location", title: appLanguage.text("Location", "ที่อยู่"), value: profile.location, appLanguage: appLanguage)
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
    let appLanguage: AppLanguage
    let onCreateRecord: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: appLanguage.text("Activity", "กิจกรรม"), subtitle: appLanguage.text("Local reading notes", "บันทึกคำทำนายในเครื่อง"))

                Spacer()

                Button(action: onCreateRecord) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel(appLanguage.addRecordTitle)
            }

            VStack(spacing: 0) {
                ProfileDetailRow(icon: "square.stack.3d.up", title: appLanguage.text("Total Records", "บันทึกทั้งหมด"), value: "\(totalCount)", appLanguage: appLanguage)
                Divider().padding(.leading, 40)
                ProfileDetailRow(icon: "timer", title: appLanguage.text("Active Records", "บันทึกที่กำลังทำ"), value: "\(activeCount)", appLanguage: appLanguage)
                Divider().padding(.leading, 40)
                ProfileDetailRow(icon: "checkmark.seal", title: appLanguage.text("Completed", "เสร็จแล้ว"), value: "\(completedCount)", appLanguage: appLanguage)
            }
            .padding(.vertical, 4)
            .cardStyle()
        }
    }
}

private struct ProfileSettingsSection: View {
    @Binding var appAppearance: AppAppearance
    @Binding var appLanguage: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: appLanguage.text("Workspace", "พื้นที่ทำงาน"), subtitle: appLanguage.profilePreferenceSubtitle)

            VStack(spacing: 0) {
                ProfileDetailRow(icon: "bell.badge", title: appLanguage.text("Queue Alerts", "แจ้งเตือนคิว"), value: appLanguage.text("Enabled", "เปิดใช้งาน"), appLanguage: appLanguage)
                Divider().padding(.leading, 40)
                ProfileDetailRow(icon: "lock.shield", title: appLanguage.text("Role Access", "สิทธิ์บทบาท"), value: appLanguage.text("Seer", "หมอดู"), appLanguage: appLanguage)
                Divider().padding(.leading, 40)
                AppearancePickerRow(selection: $appAppearance, appLanguage: appLanguage)
                Divider().padding(.leading, 40)
                LanguagePickerRow(selection: $appLanguage)
            }
            .padding(.vertical, 4)
            .cardStyle()
        }
    }
}

private struct AppearancePickerRow: View {
    @Binding var selection: AppAppearance
    let appLanguage: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: selection.icon)
                    .foregroundStyle(.teal)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(appLanguage.text("Appearance", "ธีมแอป"))
                        .foregroundStyle(.secondary)

                    Text(selection.title(in: appLanguage))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)
            }

            Picker(appLanguage.text("Appearance", "ธีมแอป"), selection: $selection) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.title(in: appLanguage))
                        .tag(appearance)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct LanguagePickerRow: View {
    @Binding var selection: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "globe.asia.australia.fill")
                    .foregroundStyle(.teal)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(selection.languageRowTitle)
                        .foregroundStyle(.secondary)

                    Text(selection.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)
            }

            Picker(selection.languageRowTitle, selection: $selection) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title)
                        .tag(language)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct ProfileLogoutButton: View {
    let appLanguage: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Label(appLanguage.text("Log Out", "ออกจากระบบ"), systemImage: "rectangle.portrait.and.arrow.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.top, 4)
    }
}

private struct ProfileEditorView: View {
    let appLanguage: AppLanguage
    let onSave: (UserProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fullName: String
    @State private var role: String
    @State private var email: String
    @State private var phone: String
    @State private var location: String
    @State private var avatarStyle: ProfileAvatarStyle

    private var canSave: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var draftProfile: UserProfile {
        UserProfile(
            fullName: fullName,
            role: role,
            email: email,
            phone: phone,
            location: location,
            avatarStyle: avatarStyle
        )
    }

    init(profile: UserProfile, appLanguage: AppLanguage, onSave: @escaping (UserProfile) -> Void) {
        self.appLanguage = appLanguage
        self.onSave = onSave
        _fullName = State(initialValue: profile.fullName)
        _role = State(initialValue: profile.role)
        _email = State(initialValue: profile.email)
        _phone = State(initialValue: profile.phone)
        _location = State(initialValue: profile.location)
        _avatarStyle = State(initialValue: profile.avatarStyle)
    }

    var body: some View {
        Form {
            Section(appLanguage.text("Profile Picture", "รูปโปรไฟล์")) {
                HStack {
                    Spacer()
                    ProfilePhotoView(
                        profile: draftProfile,
                        size: 120,
                        showsCameraBadge: true
                    )
                    Spacer()
                }
                .padding(.vertical, 8)

                AvatarStylePicker(selection: $avatarStyle, appLanguage: appLanguage)
            }

            Section(appLanguage.text("Personal", "ข้อมูลส่วนตัว")) {
                TextField(appLanguage.text("Full Name", "ชื่อ-นามสกุล"), text: $fullName)
                    .textInputAutocapitalization(.words)

                TextField(appLanguage.text("Role", "บทบาท"), text: $role)
                    .textInputAutocapitalization(.words)
            }

            Section(appLanguage.text("Contact", "ติดต่อ")) {
                TextField(appLanguage.text("Email", "อีเมล"), text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField(appLanguage.text("Phone", "โทรศัพท์"), text: $phone)
                    .keyboardType(.phonePad)

                TextField(appLanguage.text("Location", "ที่อยู่"), text: $location)
                    .textInputAutocapitalization(.words)
            }
        }
        .navigationTitle(appLanguage.editProfileTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(appLanguage.cancelTitle) {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(appLanguage.saveTitle) {
                    onSave(draftProfile)
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }
}

private struct AvatarStylePicker: View {
    @Binding var selection: ProfileAvatarStyle
    let appLanguage: AppLanguage

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(ProfileAvatarStyle.allCases) { style in
                Button {
                    selection = style
                } label: {
                    AvatarStyleOptionCard(
                        style: style,
                        isSelected: selection == style,
                        appLanguage: appLanguage
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AvatarStyleOptionCard: View {
    let style: ProfileAvatarStyle
    let isSelected: Bool
    let appLanguage: AppLanguage

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: style.colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: style.icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            Text(style.title(in: appLanguage))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.teal)
            }
        }
        .padding(10)
        .background(AppColors.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.teal.opacity(0.58) : AppColors.border)
        }
    }
}

private struct ProfileDetailRow: View {
    let icon: String
    let title: String
    let value: String
    let appLanguage: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.teal)
                .frame(width: 24)

            Text(title)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value.isEmpty ? appLanguage.text("Not set", "ยังไม่ได้ตั้งค่า") : value)
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
                            colors: profile.avatarStyle.colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: profile.avatarStyle.icon)
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
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .create:
            return language.text("New Record", "บันทึกใหม่")
        case .edit:
            return language.text("Edit Record", "แก้ไขบันทึก")
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
    let appLanguage: AppLanguage
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(mode: RecordEditorMode, appLanguage: AppLanguage, onSave: @escaping (String, String) -> Void) {
        self.mode = mode
        self.appLanguage = appLanguage
        self.onSave = onSave
        _title = State(initialValue: mode.record?.title ?? "")
        _notes = State(initialValue: mode.record?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(appLanguage.text("Details", "รายละเอียด")) {
                    TextField(appLanguage.text("Title", "หัวข้อ"), text: $title)
                        .textInputAutocapitalization(.sentences)

                    TextField(appLanguage.text("Notes", "บันทึก"), text: $notes, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle(mode.title(in: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appLanguage.cancelTitle) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(appLanguage.saveTitle) {
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
