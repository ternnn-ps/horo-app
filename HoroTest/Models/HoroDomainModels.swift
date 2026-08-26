import Foundation

protocol HoroSupabaseTable {
    static var tableName: String { get }
}

enum HoroUserRole: String, CaseIterable, Codable, Identifiable {
    case seer
    case customer

    var id: String { rawValue }
}

struct HoroUser: Identifiable, Codable, Equatable, Hashable, HoroSupabaseTable {
    static let tableName = "user_profiles"

    let id: UUID
    var role: HoroUserRole
    var displayName: String
    var email: String
    var avatarPath: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case displayName = "display_name"
        case email
        case avatarPath = "avatar_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        role: HoroUserRole,
        displayName: String,
        email: String,
        avatarPath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.displayName = displayName
        self.email = email
        self.avatarPath = avatarPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct SeerProfile: Identifiable, Codable, Equatable, Hashable, HoroSupabaseTable {
    static let tableName = "seer_profiles"

    let id: UUID
    var userId: UUID
    var displayName: String
    var headline: String
    var bio: String
    var skills: [String]
    var styles: [String]
    var ratingAverage: Double
    var reviewCount: Int
    var rateLabel: String
    var nextAvailableAt: Date?
    var isOnline: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case headline
        case bio
        case skills
        case styles
        case ratingAverage = "rating_average"
        case reviewCount = "review_count"
        case rateLabel = "rate_label"
        case nextAvailableAt = "next_available_at"
        case isOnline = "is_online"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        displayName: String,
        headline: String,
        bio: String,
        skills: [String],
        styles: [String],
        ratingAverage: Double,
        reviewCount: Int,
        rateLabel: String,
        nextAvailableAt: Date? = nil,
        isOnline: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.headline = headline
        self.bio = bio
        self.skills = skills
        self.styles = styles
        self.ratingAverage = ratingAverage
        self.reviewCount = reviewCount
        self.rateLabel = rateLabel
        self.nextAvailableAt = nextAvailableAt
        self.isOnline = isOnline
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func matches(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !normalizedQuery.isEmpty else {
            return true
        }

        let searchableText = ([displayName, headline, bio, rateLabel] + skills + styles)
            .joined(separator: " ")
            .lowercased()

        return searchableText.contains(normalizedQuery)
    }
}

struct CustomerProfile: Identifiable, Codable, Equatable, Hashable, HoroSupabaseTable {
    static let tableName = "customer_profiles"

    let id: UUID
    var userId: UUID
    var displayName: String
    var birthDate: Date?
    var birthTime: String?
    var birthPlace: String?
    var focusTopics: [String]
    var memberTier: String
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case birthDate = "birth_date"
        case birthTime = "birth_time"
        case birthPlace = "birth_place"
        case focusTopics = "focus_topics"
        case memberTier = "member_tier"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        displayName: String,
        birthDate: Date? = nil,
        birthTime: String? = nil,
        birthPlace: String? = nil,
        focusTopics: [String] = [],
        memberTier: String = "Standard",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.birthDate = birthDate
        self.birthTime = birthTime
        self.birthPlace = birthPlace
        self.focusTopics = focusTopics
        self.memberTier = memberTier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum ReadingRequestStatus: String, CaseIterable, Codable, Identifiable {
    case pending
    case accepted
    case active
    case completed
    case cancelled

    var id: String { rawValue }
}

struct ReadingRequestDraft: Equatable, Hashable {
    var customerId: UUID
    var seerId: UUID
    var topic: String
    var question: String
    var requestedFor: Date?

    init(
        customerId: UUID,
        seerId: UUID,
        topic: String,
        question: String,
        requestedFor: Date? = nil
    ) {
        self.customerId = customerId
        self.seerId = seerId
        self.topic = topic
        self.question = question
        self.requestedFor = requestedFor
    }
}

struct ReadingRequest: Identifiable, Codable, Equatable, Hashable, HoroSupabaseTable {
    static let tableName = "reading_requests"

    let id: UUID
    var customerId: UUID
    var seerId: UUID
    var topic: String
    var question: String
    var status: ReadingRequestStatus
    var requestedFor: Date?
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case customerId = "customer_id"
        case seerId = "seer_id"
        case topic
        case question
        case status
        case requestedFor = "requested_for"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        customerId: UUID,
        seerId: UUID,
        topic: String,
        question: String,
        status: ReadingRequestStatus = .pending,
        requestedFor: Date? = nil,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.customerId = customerId
        self.seerId = seerId
        self.topic = topic
        self.question = question
        self.status = status
        self.requestedFor = requestedFor
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ChatThread: Identifiable, Codable, Equatable, Hashable, HoroSupabaseTable {
    static let tableName = "chat_threads"

    let id: UUID
    var readingRequestId: UUID
    var customerId: UUID
    var seerId: UUID
    var lastMessagePreview: String
    var unreadForCustomer: Int
    var unreadForSeer: Int
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case readingRequestId = "reading_request_id"
        case customerId = "customer_id"
        case seerId = "seer_id"
        case lastMessagePreview = "last_message_preview"
        case unreadForCustomer = "unread_for_customer"
        case unreadForSeer = "unread_for_seer"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        readingRequestId: UUID,
        customerId: UUID,
        seerId: UUID,
        lastMessagePreview: String = "",
        unreadForCustomer: Int = 0,
        unreadForSeer: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.readingRequestId = readingRequestId
        self.customerId = customerId
        self.seerId = seerId
        self.lastMessagePreview = lastMessagePreview
        self.unreadForCustomer = unreadForCustomer
        self.unreadForSeer = unreadForSeer
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ChatMessageRecord: Identifiable, Codable, Equatable, Hashable, HoroSupabaseTable {
    static let tableName = "chat_messages"

    let id: UUID
    var threadId: UUID
    var senderId: UUID
    var senderRole: HoroUserRole
    var body: String
    var createdAt: Date
    var readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case senderId = "sender_id"
        case senderRole = "sender_role"
        case body
        case createdAt = "created_at"
        case readAt = "read_at"
    }

    init(
        id: UUID = UUID(),
        threadId: UUID,
        senderId: UUID,
        senderRole: HoroUserRole,
        body: String,
        createdAt: Date = Date(),
        readAt: Date? = nil
    ) {
        self.id = id
        self.threadId = threadId
        self.senderId = senderId
        self.senderRole = senderRole
        self.body = body
        self.createdAt = createdAt
        self.readAt = readAt
    }
}

struct SeerReview: Identifiable, Codable, Equatable, Hashable, HoroSupabaseTable {
    static let tableName = "seer_reviews"

    let id: UUID
    var seerId: UUID
    var customerId: UUID
    var rating: Int
    var comment: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case seerId = "seer_id"
        case customerId = "customer_id"
        case rating
        case comment
        case createdAt = "created_at"
    }

    init(
        id: UUID = UUID(),
        seerId: UUID,
        customerId: UUID,
        rating: Int,
        comment: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.seerId = seerId
        self.customerId = customerId
        self.rating = rating
        self.comment = comment
        self.createdAt = createdAt
    }
}
