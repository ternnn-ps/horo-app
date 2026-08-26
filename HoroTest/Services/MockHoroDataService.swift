import Foundation

struct MockHoroDataSeed {
    var users: [HoroUser]
    var seerProfiles: [SeerProfile]
    var customerProfiles: [CustomerProfile]
    var readingRequests: [ReadingRequest]
    var chatThreads: [ChatThread]
    var messagesByThread: [UUID: [ChatMessageRecord]]

    static let sample: MockHoroDataSeed = {
        let now = Date(timeIntervalSince1970: 1_787_740_800)
        let customerId = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let auroraUserId = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let kirinUserId = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let auroraProfileId = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let kirinProfileId = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        let requestId = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let threadId = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!

        let users = [
            HoroUser(
                id: customerId,
                role: .customer,
                displayName: "Mali Chan",
                email: "mali@example.com",
                createdAt: now,
                updatedAt: now
            ),
            HoroUser(
                id: auroraUserId,
                role: .seer,
                displayName: "Aurora Veil",
                email: "aurora@example.com",
                createdAt: now,
                updatedAt: now
            ),
            HoroUser(
                id: kirinUserId,
                role: .seer,
                displayName: "Kirin Moon",
                email: "kirin@example.com",
                createdAt: now,
                updatedAt: now
            )
        ]

        let seers = [
            SeerProfile(
                id: auroraProfileId,
                userId: auroraUserId,
                displayName: "Aurora Veil",
                headline: "Relationship Timing Seer",
                bio: "Soft guidance for love, reconnecting, and emotional timing.",
                skills: ["Relationship", "Timing", "Tarot", "Birth Chart"],
                styles: ["Gentle and reflective", "Clear next steps"],
                ratingAverage: 4.9,
                reviewCount: 218,
                rateLabel: "$18",
                nextAvailableAt: now,
                isOnline: true,
                createdAt: now,
                updatedAt: now
            ),
            SeerProfile(
                id: kirinProfileId,
                userId: kirinUserId,
                displayName: "Kirin Moon",
                headline: "Career Path Reader",
                bio: "Practical readings for work decisions, interviews, and pivots.",
                skills: ["Career", "Decision", "Astrology", "Strategy"],
                styles: ["Direct and practical", "Structured summary"],
                ratingAverage: 4.8,
                reviewCount: 176,
                rateLabel: "$15",
                nextAvailableAt: now.addingTimeInterval(300),
                isOnline: true,
                createdAt: now,
                updatedAt: now
            )
        ]

        let customers = [
            CustomerProfile(
                id: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!,
                userId: customerId,
                displayName: "Mali Chan",
                birthTime: "09:15",
                birthPlace: "Bangkok",
                focusTopics: ["Relationships", "Timing"],
                memberTier: "Gold",
                createdAt: now,
                updatedAt: now
            )
        ]

        let request = ReadingRequest(
            id: requestId,
            customerId: customerId,
            seerId: auroraProfileId,
            topic: "Relationship Timing",
            question: "Is this the right moment to reconnect?",
            status: .active,
            requestedFor: now,
            createdAt: now,
            updatedAt: now
        )

        let thread = ChatThread(
            id: threadId,
            readingRequestId: requestId,
            customerId: customerId,
            seerId: auroraProfileId,
            lastMessagePreview: "I am checking the timing window now.",
            unreadForCustomer: 1,
            unreadForSeer: 0,
            createdAt: now,
            updatedAt: now.addingTimeInterval(120)
        )

        let messages = [
            ChatMessageRecord(
                id: UUID(uuidString: "70000000-0000-0000-0000-000000000001")!,
                threadId: threadId,
                senderId: customerId,
                senderRole: .customer,
                body: "I want to know if this is the right moment to reconnect.",
                createdAt: now.addingTimeInterval(60)
            ),
            ChatMessageRecord(
                id: UUID(uuidString: "70000000-0000-0000-0000-000000000002")!,
                threadId: threadId,
                senderId: auroraProfileId,
                senderRole: .seer,
                body: "I am checking the timing window now.",
                createdAt: now.addingTimeInterval(120)
            )
        ]

        return MockHoroDataSeed(
            users: users,
            seerProfiles: seers,
            customerProfiles: customers,
            readingRequests: [request],
            chatThreads: [thread],
            messagesByThread: [threadId: messages]
        )
    }()
}

actor MockHoroDataService: HoroDataServicing {
    private var currentSessionUser: HoroUser?
    private var users: [HoroUser]
    private var seerProfiles: [SeerProfile]
    private var customerProfiles: [CustomerProfile]
    private var readingRequests: [ReadingRequest]
    private var chatThreads: [ChatThread]
    private var messagesByThread: [UUID: [ChatMessageRecord]]

    init(seed: MockHoroDataSeed = .sample) {
        users = seed.users
        seerProfiles = seed.seerProfiles
        customerProfiles = seed.customerProfiles
        readingRequests = seed.readingRequests
        chatThreads = seed.chatThreads
        messagesByThread = seed.messagesByThread
    }

    func signInMock(as role: HoroUserRole) async throws -> HoroUser {
        guard let user = users.first(where: { $0.role == role }) else {
            throw HoroDataError.notFound("No mock \(role.rawValue) user exists.")
        }

        currentSessionUser = user
        return user
    }

    func currentUser() async -> HoroUser? {
        currentSessionUser
    }

    func fetchSeers(matching query: String?) async throws -> [SeerProfile] {
        let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return seerProfiles
            .filter { $0.matches(normalizedQuery) }
            .sorted {
                if $0.isOnline != $1.isOnline {
                    return $0.isOnline && !$1.isOnline
                }

                return $0.ratingAverage > $1.ratingAverage
            }
    }

    func fetchSeer(id: UUID) async throws -> SeerProfile {
        guard let seer = seerProfiles.first(where: { $0.id == id }) else {
            throw HoroDataError.notFound("Seer profile was not found.")
        }

        return seer
    }

    func fetchCustomerProfile(userId: UUID) async throws -> CustomerProfile {
        guard let profile = customerProfiles.first(where: { $0.userId == userId }) else {
            throw HoroDataError.notFound("Customer profile was not found.")
        }

        return profile
    }

    func createReadingRequest(_ draft: ReadingRequestDraft) async throws -> ReadingRequest {
        let topic = draft.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let question = draft.question.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !topic.isEmpty else {
            throw HoroDataError.invalidInput("Reading topic is required.")
        }

        guard !question.isEmpty else {
            throw HoroDataError.invalidInput("Reading question is required.")
        }

        guard customerProfiles.contains(where: { $0.userId == draft.customerId }) else {
            throw HoroDataError.notFound("Customer profile was not found.")
        }

        guard seerProfiles.contains(where: { $0.id == draft.seerId }) else {
            throw HoroDataError.notFound("Seer profile was not found.")
        }

        let now = Date()
        let request = ReadingRequest(
            customerId: draft.customerId,
            seerId: draft.seerId,
            topic: topic,
            question: question,
            requestedFor: draft.requestedFor,
            createdAt: now,
            updatedAt: now
        )

        readingRequests.insert(request, at: 0)

        let thread = ChatThread(
            readingRequestId: request.id,
            customerId: request.customerId,
            seerId: request.seerId,
            lastMessagePreview: question,
            unreadForCustomer: 0,
            unreadForSeer: 1,
            createdAt: now,
            updatedAt: now
        )

        chatThreads.insert(thread, at: 0)
        messagesByThread[thread.id] = []

        return request
    }

    func fetchReadingRequests(for userId: UUID, role: HoroUserRole) async throws -> [ReadingRequest] {
        readingRequests
            .filter { request in
                switch role {
                case .customer:
                    return request.customerId == userId
                case .seer:
                    return request.seerId == userId || seerProfiles.contains {
                        $0.id == request.seerId && $0.userId == userId
                    }
                }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func updateReadingRequestStatus(id: UUID, status: ReadingRequestStatus) async throws -> ReadingRequest {
        guard let index = readingRequests.firstIndex(where: { $0.id == id }) else {
            throw HoroDataError.notFound("Reading request was not found.")
        }

        readingRequests[index].status = status
        readingRequests[index].updatedAt = Date()

        if status == .completed {
            readingRequests[index].completedAt = Date()
        }

        return readingRequests[index]
    }

    func deleteReadingRequest(id: UUID) async throws {
        guard readingRequests.contains(where: { $0.id == id }) else {
            throw HoroDataError.notFound("Reading request was not found.")
        }

        let removedThreadIds = chatThreads
            .filter { $0.readingRequestId == id }
            .map(\.id)

        readingRequests.removeAll { $0.id == id }
        chatThreads.removeAll { $0.readingRequestId == id }

        for threadId in removedThreadIds {
            messagesByThread[threadId] = nil
        }
    }

    func fetchChatThreads(for userId: UUID, role: HoroUserRole) async throws -> [ChatThread] {
        chatThreads
            .filter { thread in
                switch role {
                case .customer:
                    return thread.customerId == userId
                case .seer:
                    return thread.seerId == userId || seerProfiles.contains {
                        $0.id == thread.seerId && $0.userId == userId
                    }
                }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchMessages(threadId: UUID) async throws -> [ChatMessageRecord] {
        guard chatThreads.contains(where: { $0.id == threadId }) else {
            throw HoroDataError.notFound("Chat thread was not found.")
        }

        return (messagesByThread[threadId] ?? [])
            .sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    func sendMessage(
        threadId: UUID,
        senderId: UUID,
        senderRole: HoroUserRole,
        body: String
    ) async throws -> ChatMessageRecord {
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanBody.isEmpty else {
            throw HoroDataError.invalidInput("Message body is required.")
        }

        guard let threadIndex = chatThreads.firstIndex(where: { $0.id == threadId }) else {
            throw HoroDataError.notFound("Chat thread was not found.")
        }

        let now = Date()
        let message = ChatMessageRecord(
            threadId: threadId,
            senderId: senderId,
            senderRole: senderRole,
            body: cleanBody,
            createdAt: now
        )

        messagesByThread[threadId, default: []].append(message)
        chatThreads[threadIndex].lastMessagePreview = cleanBody
        chatThreads[threadIndex].updatedAt = now

        switch senderRole {
        case .customer:
            chatThreads[threadIndex].unreadForSeer += 1
        case .seer:
            chatThreads[threadIndex].unreadForCustomer += 1
        }

        return message
    }
}
