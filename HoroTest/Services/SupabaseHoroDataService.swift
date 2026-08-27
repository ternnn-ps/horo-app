import Foundation

struct SupabaseConfiguration: Equatable {
    let url: URL
    let anonKey: String
    let testPassword: String

    init(url: URL, anonKey: String, testPassword: String = "HoroTest123!") {
        self.url = url
        self.anonKey = anonKey
        self.testPassword = testPassword
    }

    init?(urlString: String, anonKey: String, testPassword: String = "HoroTest123!") {
        guard let url = URL(string: urlString),
              !anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        self.init(url: url, anonKey: anonKey, testPassword: testPassword)
    }

    static var runtime: SupabaseConfiguration? {
        guard let urlString = runtimeValue("SUPABASE_URL", "HORO_SUPABASE_URL"),
              let anonKey = runtimeValue("SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY", "HORO_SUPABASE_ANON_KEY")
        else {
            return nil
        }

        return SupabaseConfiguration(
            urlString: urlString,
            anonKey: anonKey,
            testPassword: runtimeValue("SUPABASE_TEST_PASSWORD", "HORO_TEST_PASSWORD") ?? "HoroTest123!"
        )
    }

    private static func runtimeValue(_ keys: String...) -> String? {
        keys.lazy.compactMap(runtimeSingleValue).first
    }

    private static let bundledConfig: [String: String] = {
        guard let url = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: String]
        else {
            return [:]
        }

        return dictionary
    }()

    private static func runtimeSingleValue(_ key: String) -> String? {
        let environmentValue = ProcessInfo.processInfo.environment[key]
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let bundledConfigValue = bundledConfig[key]

        return [environmentValue, bundleValue, bundledConfigValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { value in
                !value.isEmpty && !value.contains("$(")
            }
    }
}

struct SupabaseAuthSession: Equatable {
    let userID: UUID
    let email: String
    let accessToken: String
    let refreshToken: String?
}

struct SupabaseAccount: Decodable, Equatable, Identifiable {
    enum Role: String, Decodable {
        case user
        case seer
        case admin

        var appRole: HoroUserRole {
            switch self {
            case .seer:
                return .seer
            case .user, .admin:
                return .customer
            }
        }
    }

    let id: UUID
    let role: Role
    let status: String
}

struct SupabaseWallet: Decodable, Equatable {
    let accountID: UUID
    let availableCoin: Int
    let reservedCoin: Int
    let payableCoin: Int

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case availableCoin = "available_coin"
        case reservedCoin = "reserved_coin"
        case payableCoin = "payable_coin"
    }
}

struct SupabaseCoinPackage: Decodable, Equatable, Identifiable {
    let id: UUID
    let code: String
    let coinAmount: Int
    let bonusCoin: Int
    let priceMinor: Int
    let currency: String
    let allowedMethods: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case coinAmount = "coin_amount"
        case bonusCoin = "bonus_coin"
        case priceMinor = "price_minor"
        case currency
        case allowedMethods = "allowed_methods"
    }
}

struct SupabaseSeerListing: Decodable, Equatable, Identifiable {
    let id: UUID
    let displayName: String
    let bio: String
    let avatarURL: String?
    let approvalStatus: String
    let isActive: Bool
    let acceptsQuestion: Bool
    let ratingAverage: Double?
    let ratingCount: Int
    let questionCount: Int
    let mainSkillID: Int?
    var skills: [String] = []
    var serviceID: UUID?
    var priceCoin: Int?

    enum CodingKeys: String, CodingKey {
        case id = "account_id"
        case displayName = "display_name"
        case bio
        case avatarURL = "avatar_url"
        case approvalStatus = "approval_status"
        case isActive = "is_active"
        case acceptsQuestion = "accepts_question"
        case ratingAverage = "rating_avg"
        case ratingCount = "rating_count"
        case questionCount = "question_count"
        case mainSkillID = "main_skill_id"
    }
}

struct SupabaseQuestion: Decodable, Equatable, Identifiable {
    let id: UUID
    let userID: UUID
    let seerID: UUID
    let seerServiceID: UUID
    let status: String
    let priceCoin: Int
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case seerID = "seer_id"
        case seerServiceID = "seer_service_id"
        case status
        case priceCoin = "price_coin"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SupabaseQuestionMessage: Decodable, Equatable, Identifiable {
    let id: Int64
    let questionID: UUID
    let senderID: UUID?
    let messageType: String
    let content: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case questionID = "question_id"
        case senderID = "sender_id"
        case messageType = "message_type"
        case content
        case createdAt = "created_at"
    }
}

/// คำถามที่กำลังร่าง พร้อม idempotency key ที่ต้องคงค่าเดิมตลอดอายุของ draft
///
/// `submit_question` กันการหักเหรียญซ้ำด้วย `client_request_id` — ถ้าส่ง key เดิมมันจะคืน
/// `replayed: true` โดยไม่แตะกระเป๋าเงิน แต่กลไกนี้ใช้ไม่ได้เลยถ้า client สุ่ม key ใหม่ตอน retry
/// จึงไม่มี default UUID ใน init: ต้องสร้างผ่าน `startDraft` ครั้งเดียวตอนเริ่มร่าง
/// แล้วส่งตัวเดิมซ้ำจนกว่าจะสำเร็จหรือผู้ใช้ทิ้ง draft
struct SupabaseQuestionDraft: Equatable {
    let seerServiceID: UUID
    let firstMessage: String
    let clientMessageID: UUID
    let clientRequestID: UUID

    static func startDraft(seerServiceID: UUID, firstMessage: String) -> SupabaseQuestionDraft {
        SupabaseQuestionDraft(
            seerServiceID: seerServiceID,
            firstMessage: firstMessage,
            clientMessageID: UUID(),
            clientRequestID: UUID()
        )
    }

    /// แก้ข้อความได้โดยคง key เดิม — ยังเป็นคำถามเดียวกันที่ยังส่งไม่สำเร็จ
    func replacingMessage(_ text: String) -> SupabaseQuestionDraft {
        SupabaseQuestionDraft(
            seerServiceID: seerServiceID,
            firstMessage: text,
            clientMessageID: clientMessageID,
            clientRequestID: clientRequestID
        )
    }
}

/// ผลลัพธ์ของ RPC ที่เปลี่ยนสถานะคำถาม — cancel / request_close / respond_close คืนรูปเดียวกัน
/// `replayed` มาเมื่อเรียกซ้ำบนสถานะที่ทำไปแล้ว (ไม่ถือว่าผิดพลาด และไม่แตะเงินรอบสอง)
struct SupabaseQuestionLifecycle: Decodable, Equatable {
    let questionID: UUID
    let status: String
    let replayed: Bool?

    enum CodingKeys: String, CodingKey {
        case questionID = "question_id"
        case status
        case replayed
    }
}

/// กติกาเดียวของการเลือก idempotency key ตอนซื้อคำถาม — แยกออกมาเพื่อให้เทสได้
///
/// บั๊กที่กันอยู่: ผู้ใช้กดส่ง เน็ตหลุด กดใหม่ ถ้าได้ key ใหม่ = ซื้อสองครั้ง หักเหรียญสองรอบ
enum QuestionDraftPolicy {
    static func draft(
        reusing pending: SupabaseQuestionDraft?,
        seerServiceID: UUID,
        message: String
    ) -> SupabaseQuestionDraft {
        if let pending, pending.seerServiceID == seerServiceID {
            return pending.replacingMessage(message)
        }
        return .startDraft(seerServiceID: seerServiceID, firstMessage: message)
    }
}

struct SupabaseSubmittedQuestion: Decodable, Equatable {
    let questionID: UUID
    let status: String
    let priceCoin: Int
    let expiresAt: String?
    let replayed: Bool

    enum CodingKeys: String, CodingKey {
        case questionID = "question_id"
        case status
        case priceCoin = "price_coin"
        case expiresAt = "expires_at"
        case replayed
    }
}

final class SupabaseHoroDataService: HoroDataServicing {
    let configuration: SupabaseConfiguration
    let auth: ChataAuth

    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    init(configuration: SupabaseConfiguration, authStorageKey: String? = nil) {
        self.configuration = configuration
        self.auth = ChataAuth(configuration: configuration, storageKey: authStorageKey)
    }

    var isSignedIn: Bool {
        auth.isSignedIn
    }

    var signedInUserID: UUID? {
        auth.currentUserID
    }

    @discardableResult
    func signIn(email: String, password: String) async throws -> UUID {
        try await auth.signIn(email: email, password: password)
    }

    @discardableResult
    func signUp(email: String, password: String) async throws -> UUID {
        try await auth.signUp(email: email, password: password)
    }

    func signOut() async throws {
        try await auth.signOut()
    }

    func fetchAccount() async throws -> SupabaseAccount {
        let accounts: [SupabaseAccount] = try await request(
            path: "rest/v1/account",
            queryItems: [
                URLQueryItem(name: "select", value: "id,role,status"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )

        guard let account = accounts.first else {
            throw HoroDataError.notFound("Supabase account row was not found for the signed-in user.")
        }

        return account
    }

    func fetchWallet() async throws -> SupabaseWallet {
        let wallets: [SupabaseWallet] = try await request(
            path: "rest/v1/v_my_wallet",
            queryItems: [
                URLQueryItem(name: "select", value: "account_id,available_coin,reserved_coin,payable_coin"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )

        guard let wallet = wallets.first else {
            throw HoroDataError.notFound("Wallet was not found for the signed-in user.")
        }

        return wallet
    }

    func fetchCoinPackages() async throws -> [SupabaseCoinPackage] {
        try await request(
            path: "rest/v1/coin_package",
            queryItems: [
                URLQueryItem(name: "select", value: "id,code,coin_amount,bonus_coin,price_minor,currency,allowed_methods"),
                URLQueryItem(name: "is_enabled", value: "eq.true"),
                URLQueryItem(name: "order", value: "sort_order.asc")
            ],
            requiresSession: false
        )
    }

    func fetchSeerListings(matching query: String?) async throws -> [SupabaseSeerListing] {
        async let profileRows: [SupabaseSeerListing] = request(
            path: "rest/v1/seer_profile",
            queryItems: [
                URLQueryItem(name: "select", value: "account_id,display_name,bio,avatar_url,approval_status,is_active,accepts_question,rating_avg,rating_count,question_count,main_skill_id"),
                URLQueryItem(name: "approval_status", value: "eq.approved"),
                URLQueryItem(name: "is_active", value: "eq.true"),
                URLQueryItem(name: "order", value: "rating_avg.desc.nullslast")
            ],
            requiresSession: false
        )

        async let serviceRows: [SupabaseSeerServiceRow] = request(
            path: "rest/v1/seer_service",
            queryItems: [
                URLQueryItem(name: "select", value: "id,seer_id,price_coin,is_enabled"),
                URLQueryItem(name: "is_enabled", value: "eq.true")
            ],
            requiresSession: false
        )

        async let seerSkillRows: [SupabaseSeerSkillRow] = request(
            path: "rest/v1/seer_skill",
            queryItems: [URLQueryItem(name: "select", value: "seer_id,skill_id,is_main")],
            requiresSession: false
        )

        async let skillRows: [SupabaseSkillRow] = request(
            path: "rest/v1/skill",
            queryItems: [
                URLQueryItem(name: "select", value: "id,name"),
                URLQueryItem(name: "is_enabled", value: "eq.true")
            ],
            requiresSession: false
        )

        let rows = try await profileRows
        let servicesBySeer = Dictionary(grouping: try await serviceRows, by: \.seerID)
        let skillsByID = Dictionary(uniqueKeysWithValues: try await skillRows.map { ($0.id, $0.name) })
        let skillIDsBySeer = Dictionary(grouping: try await seerSkillRows, by: \.seerID)

        let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        return rows.compactMap { row in
            var listing = row
            let enabledService = servicesBySeer[row.id]?.first
            listing.serviceID = enabledService?.id
            listing.priceCoin = enabledService?.priceCoin
            listing.skills = (skillIDsBySeer[row.id] ?? [])
                .sorted { $0.isMain && !$1.isMain }
                .compactMap { skillsByID[$0.skillID] }

            guard !normalizedQuery.isEmpty else {
                return listing
            }

            let searchableText = ([listing.displayName, listing.bio] + listing.skills)
                .joined(separator: " ")
                .lowercased()
            return searchableText.contains(normalizedQuery) ? listing : nil
        }
    }

    func fetchQuestions() async throws -> [SupabaseQuestion] {
        try await request(
            path: "rest/v1/question",
            queryItems: [
                URLQueryItem(name: "select", value: "id,user_id,seer_id,seer_service_id,status,price_coin,created_at,updated_at"),
                URLQueryItem(name: "order", value: "updated_at.desc")
            ]
        )
    }

    func fetchMessages(questionID: UUID) async throws -> [SupabaseQuestionMessage] {
        try await request(
            path: "rest/v1/question_message",
            queryItems: [
                URLQueryItem(name: "select", value: "id,question_id,sender_id,message_type,content,created_at"),
                URLQueryItem(name: "question_id", value: "eq.\(questionID.uuidString)"),
                URLQueryItem(name: "order", value: "id.asc")
            ]
        )
    }

    func submitQuestion(_ draft: SupabaseQuestionDraft) async throws -> SupabaseSubmittedQuestion {
        try await request(
            path: "rest/v1/rpc/submit_question",
            method: "POST",
            body: [
                "p_seer_service_id": draft.seerServiceID.uuidString,
                "p_first_message": draft.firstMessage,
                "p_client_message_id": draft.clientMessageID.uuidString,
                "p_client_request_id": draft.clientRequestID.uuidString
            ]
        )
    }

    @discardableResult
    func sendQuestionMessage(questionID: UUID, senderID: UUID, body: String) async throws -> SupabaseQuestionMessage {
        let inserted: [SupabaseQuestionMessage] = try await request(
            path: "rest/v1/question_message",
            method: "POST",
            headers: ["Prefer": "return=representation"],
            body: [
                "question_id": questionID.uuidString,
                "sender_id": senderID.uuidString,
                "client_message_id": UUID().uuidString,
                "message_type": "text",
                "content": body
            ]
        )

        guard let message = inserted.first else {
            throw HoroDataError.server("Supabase did not return the inserted message.")
        }

        return message
    }


    /// หมอดูกดขอปิดงาน — ยังไม่มีเงินย้ายจนกว่าผู้ใช้จะยืนยัน
    @discardableResult
    func requestCloseQuestion(id: UUID) async throws -> SupabaseQuestionLifecycle {
        try await request(
            path: "rest/v1/rpc/request_close_question",
            method: "POST",
            body: ["p_question_id": id.uuidString]
        )
    }

    /// ผู้ใช้ตอบคำขอปิดงาน — accept = true คือจุดที่เหรียญออกจาก escrow เข้าหมอดูจริง
    @discardableResult
    func respondCloseQuestion(id: UUID, accept: Bool) async throws -> SupabaseQuestionLifecycle {
        try await request(
            path: "rest/v1/rpc/respond_close_question",
            method: "POST",
            body: RespondCloseBody(questionID: id.uuidString, accept: accept)
        )
    }

    /// ผู้ใช้ยกเลิกคำถามที่หมอดูยังไม่ตอบ — คืนเหรียญเต็มจำนวน
    @discardableResult
    func cancelQuestion(id: UUID) async throws -> SupabaseQuestionLifecycle {
        try await request(
            path: "rest/v1/rpc/cancel_question",
            method: "POST",
            body: ["p_question_id": id.uuidString]
        )
    }

    func signInMock(as role: HoroUserRole) async throws -> HoroUser {
        let email = role == .seer ? "seer@horo.test" : "customer@horo.test"
        let userID = try await signIn(email: email, password: configuration.testPassword)
        let account = try await fetchAccount()

        return HoroUser(
            id: userID,
            role: account.role.appRole,
            displayName: email,
            email: email
        )
    }

    func currentUser() async -> HoroUser? {
        guard let userID = auth.currentUserID else {
            return nil
        }

        return HoroUser(
            id: userID,
            role: .customer,
            displayName: "",
            email: ""
        )
    }

    func fetchSeers(matching query: String?) async throws -> [SeerProfile] {
        let listings = try await fetchSeerListings(matching: query)

        return listings.map { listing in
            SeerProfile(
                id: listing.id,
                userId: listing.id,
                displayName: listing.displayName,
                headline: listing.skills.first ?? "Horo Seer",
                bio: listing.bio,
                skills: listing.skills,
                styles: [],
                ratingAverage: listing.ratingAverage ?? 0,
                reviewCount: listing.ratingCount,
                rateLabel: listing.priceCoin.map { "\($0) coins" } ?? "Ask",
                isOnline: listing.isActive
            )
        }
    }

    func fetchSeer(id: UUID) async throws -> SeerProfile {
        guard let listing = try await fetchSeerListings(matching: nil).first(where: { $0.id == id }) else {
            throw HoroDataError.notFound("Seer profile was not found.")
        }

        return SeerProfile(
            id: listing.id,
            userId: listing.id,
            displayName: listing.displayName,
            headline: listing.skills.first ?? "Horo Seer",
            bio: listing.bio,
            skills: listing.skills,
            styles: [],
            ratingAverage: listing.ratingAverage ?? 0,
            reviewCount: listing.ratingCount,
            rateLabel: listing.priceCoin.map { "\($0) coins" } ?? "Ask",
            isOnline: listing.isActive
        )
    }

    func fetchCustomerProfile(userId: UUID) async throws -> CustomerProfile {
        let rows: [SupabaseUserProfileRow] = try await request(
            path: "rest/v1/user_profile",
            queryItems: [
                URLQueryItem(name: "select", value: "account_id,display_name,birthdate,created_at,updated_at"),
                URLQueryItem(name: "account_id", value: "eq.\(userId.uuidString)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )

        guard let row = rows.first else {
            throw HoroDataError.notFound("Customer profile was not found.")
        }

        return CustomerProfile(
            id: row.accountID,
            userId: row.accountID,
            displayName: row.displayName,
            memberTier: "Standard"
        )
    }

    func createReadingRequest(_ draft: ReadingRequestDraft) async throws -> ReadingRequest {
        throw HoroDataError.notConfigured("Use submitQuestion for the current Supabase question schema.")
    }

    func fetchReadingRequests(for userId: UUID, role: HoroUserRole) async throws -> [ReadingRequest] {
        let questions = try await fetchQuestions()

        return questions.map { question in
            ReadingRequest(
                id: question.id,
                customerId: question.userID,
                seerId: question.seerID,
                topic: "Question",
                question: "",
                status: ReadingRequestStatus(rawValue: question.status) ?? .active,
                createdAt: Date(),
                updatedAt: Date()
            )
        }
    }

    func updateReadingRequestStatus(id: UUID, status: ReadingRequestStatus) async throws -> ReadingRequest {
        throw HoroDataError.notConfigured("Use question lifecycle RPCs for the current Supabase question schema.")
    }

    func deleteReadingRequest(id: UUID) async throws {
        throw HoroDataError.notConfigured("Use cancel_question for the current Supabase question schema.")
    }

    func fetchChatThreads(for userId: UUID, role: HoroUserRole) async throws -> [ChatThread] {
        throw HoroDataError.notConfigured("Chat threads are represented by question rows in the current Supabase schema.")
    }

    func fetchMessages(threadId: UUID) async throws -> [ChatMessageRecord] {
        let messages = try await fetchMessages(questionID: threadId)

        return messages.map { message in
            ChatMessageRecord(
                threadId: message.questionID,
                senderId: message.senderID ?? UUID(),
                senderRole: .customer,
                body: message.content ?? "",
                createdAt: Date()
            )
        }
    }

    @discardableResult
    func sendMessage(
        threadId: UUID,
        senderId: UUID,
        senderRole: HoroUserRole,
        body: String
    ) async throws -> ChatMessageRecord {
        let message = try await sendQuestionMessage(questionID: threadId, senderID: senderId, body: body)

        return ChatMessageRecord(
            threadId: message.questionID,
            senderId: message.senderID ?? senderId,
            senderRole: senderRole,
            body: message.content ?? "",
            createdAt: Date()
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        headers: [String: String] = [:],
        body: Body? = Optional<Data>.none,
        requiresSession: Bool = true
    ) async throws -> Response {
        var request = URLRequest(url: url(path: path, queryItems: queryItems))
        request.httpMethod = method
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        let bearer = requiresSession ? try await auth.accessToken() : configuration.anonKey
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try jsonEncoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HoroDataError.server("Supabase returned a non-HTTP response.")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw decodeSupabaseError(from: data, statusCode: httpResponse.statusCode)
        }

        do {
            return try jsonDecoder.decode(Response.self, from: data)
        } catch {
            throw HoroDataError.decoding("Could not decode Supabase response: \(error.localizedDescription)")
        }
    }

    private func url(path: String, queryItems: [URLQueryItem]) -> URL {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = configuration.url.appendingPathComponent(cleanPath)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        return components?.url ?? endpoint
    }

    private func decodeSupabaseError(from data: Data, statusCode: Int) -> HoroDataError {
        if let error = try? jsonDecoder.decode(SupabaseErrorResponse.self, from: data) {
            return .server(error.message)
        }

        let message = String(data: data, encoding: .utf8) ?? "Unknown Supabase error"
        return .server("Supabase HTTP \(statusCode): \(message)")
    }
}

private struct AuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let user: AuthUserResponse

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

private struct AuthUserResponse: Decodable {
    let id: String
    let email: String?
}

private struct SupabaseErrorResponse: Decodable {
    let message: String
}

private struct SupabaseSeerServiceRow: Decodable, Equatable, Identifiable {
    let id: UUID
    let seerID: UUID
    let priceCoin: Int
    let isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case seerID = "seer_id"
        case priceCoin = "price_coin"
        case isEnabled = "is_enabled"
    }
}

private struct SupabaseSeerSkillRow: Decodable, Equatable {
    let seerID: UUID
    let skillID: Int
    let isMain: Bool

    enum CodingKeys: String, CodingKey {
        case seerID = "seer_id"
        case skillID = "skill_id"
        case isMain = "is_main"
    }
}

private struct SupabaseSkillRow: Decodable, Equatable {
    let id: Int
    let name: String
}

private struct SupabaseUserProfileRow: Decodable, Equatable {
    let accountID: UUID
    let displayName: String
    let birthdate: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case displayName = "display_name"
        case birthdate
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct RespondCloseBody: Encodable {
    let questionID: String
    let accept: Bool

    enum CodingKeys: String, CodingKey {
        case questionID = "p_question_id"
        case accept = "p_accept"
    }
}
