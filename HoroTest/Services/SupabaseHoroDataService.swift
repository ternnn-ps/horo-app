import Foundation

struct SupabaseConfiguration: Equatable {
    let url: URL
    let anonKey: String

    init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }

    init?(urlString: String, anonKey: String) {
        guard let url = URL(string: urlString),
              !anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        self.url = url
        self.anonKey = anonKey
    }
}

final class SupabaseHoroDataService: HoroDataServicing {
    let configuration: SupabaseConfiguration

    init(configuration: SupabaseConfiguration) {
        self.configuration = configuration
    }

    func signInMock(as role: HoroUserRole) async throws -> HoroUser {
        throw unavailable()
    }

    func currentUser() async -> HoroUser? {
        nil
    }

    func fetchSeers(matching query: String?) async throws -> [SeerProfile] {
        throw unavailable()
    }

    func fetchSeer(id: UUID) async throws -> SeerProfile {
        throw unavailable()
    }

    func fetchCustomerProfile(userId: UUID) async throws -> CustomerProfile {
        throw unavailable()
    }

    func createReadingRequest(_ draft: ReadingRequestDraft) async throws -> ReadingRequest {
        throw unavailable()
    }

    func fetchReadingRequests(for userId: UUID, role: HoroUserRole) async throws -> [ReadingRequest] {
        throw unavailable()
    }

    func updateReadingRequestStatus(id: UUID, status: ReadingRequestStatus) async throws -> ReadingRequest {
        throw unavailable()
    }

    func deleteReadingRequest(id: UUID) async throws {
        throw unavailable()
    }

    func fetchChatThreads(for userId: UUID, role: HoroUserRole) async throws -> [ChatThread] {
        throw unavailable()
    }

    func fetchMessages(threadId: UUID) async throws -> [ChatMessageRecord] {
        throw unavailable()
    }

    @discardableResult
    func sendMessage(
        threadId: UUID,
        senderId: UUID,
        senderRole: HoroUserRole,
        body: String
    ) async throws -> ChatMessageRecord {
        throw unavailable()
    }

    private func unavailable() -> HoroDataError {
        HoroDataError.notConfigured(
            "Supabase service is scaffolded. Add the Supabase Swift SDK and implement queries for the table-backed models."
        )
    }
}
