import Foundation

enum HoroDataError: Error, Equatable, LocalizedError {
    case unauthenticated
    case notFound(String)
    case invalidInput(String)
    case notConfigured(String)
    case server(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "No signed-in user is available."
        case .notFound(let message):
            return message
        case .invalidInput(let message):
            return message
        case .notConfigured(let message):
            return message
        case .server(let message):
            return message
        case .decoding(let message):
            return message
        }
    }
}

protocol HoroDataServicing {
    func signInMock(as role: HoroUserRole) async throws -> HoroUser
    func currentUser() async -> HoroUser?

    func fetchSeers(matching query: String?) async throws -> [SeerProfile]
    func fetchSeer(id: UUID) async throws -> SeerProfile
    func fetchCustomerProfile(userId: UUID) async throws -> CustomerProfile

    func createReadingRequest(_ draft: ReadingRequestDraft) async throws -> ReadingRequest
    func fetchReadingRequests(for userId: UUID, role: HoroUserRole) async throws -> [ReadingRequest]
    func updateReadingRequestStatus(id: UUID, status: ReadingRequestStatus) async throws -> ReadingRequest
    func deleteReadingRequest(id: UUID) async throws

    func fetchChatThreads(for userId: UUID, role: HoroUserRole) async throws -> [ChatThread]
    func fetchMessages(threadId: UUID) async throws -> [ChatMessageRecord]

    @discardableResult
    func sendMessage(
        threadId: UUID,
        senderId: UUID,
        senderRole: HoroUserRole,
        body: String
    ) async throws -> ChatMessageRecord
}
