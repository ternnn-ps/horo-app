import XCTest
@testable import HoroTest

final class HoroDataServiceTests: XCTestCase {
    func testSignInMockReturnsRequestedRole() async throws {
        let service = MockHoroDataService()

        let user = try await service.signInMock(as: .customer)
        let currentUser = await service.currentUser()

        XCTAssertEqual(user.role, .customer)
        XCTAssertEqual(currentUser, user)
    }

    func testFetchSeersSearchesSkillsAndHeadline() async throws {
        let service = MockHoroDataService()

        let careerSeers = try await service.fetchSeers(matching: "career")
        let relationshipSeers = try await service.fetchSeers(matching: "relationship")

        XCTAssertEqual(careerSeers.map(\.displayName), ["Kirin Moon"])
        XCTAssertEqual(relationshipSeers.map(\.displayName), ["Aurora Veil"])
    }

    func testCreateReadingRequestCreatesThreadForBothRoles() async throws {
        let service = MockHoroDataService()
        let customer = MockHoroDataSeed.sample.users.first { $0.role == .customer }!
        let seer = MockHoroDataSeed.sample.seerProfiles.first { $0.displayName == "Kirin Moon" }!

        let request = try await service.createReadingRequest(
            ReadingRequestDraft(
                customerId: customer.id,
                seerId: seer.id,
                topic: "Career decision",
                question: "Should I wait for the next offer?"
            )
        )

        let customerRequests = try await service.fetchReadingRequests(for: customer.id, role: .customer)
        let seerThreads = try await service.fetchChatThreads(for: seer.userId, role: .seer)

        XCTAssertEqual(request.status, .pending)
        XCTAssertTrue(customerRequests.contains { $0.id == request.id })
        XCTAssertTrue(seerThreads.contains { $0.readingRequestId == request.id })
    }

    func testSendMessagePersistsAndUpdatesThreadPreview() async throws {
        let service = MockHoroDataService()
        let customer = MockHoroDataSeed.sample.users.first { $0.role == .customer }!
        let thread = MockHoroDataSeed.sample.chatThreads[0]

        let message = try await service.sendMessage(
            threadId: thread.id,
            senderId: customer.id,
            senderRole: .customer,
            body: " Can I add one more detail? "
        )

        let messages = try await service.fetchMessages(threadId: thread.id)
        let updatedThreads = try await service.fetchChatThreads(for: customer.id, role: .customer)
        let updatedThread = updatedThreads.first { $0.id == thread.id }

        XCTAssertEqual(message.body, "Can I add one more detail?")
        XCTAssertEqual(messages.last, message)
        XCTAssertEqual(updatedThread?.lastMessagePreview, message.body)
        XCTAssertEqual(updatedThread?.unreadForSeer, thread.unreadForSeer + 1)
    }

    func testDeleteReadingRequestRemovesRelatedThread() async throws {
        let service = MockHoroDataService()
        let customer = MockHoroDataSeed.sample.users.first { $0.role == .customer }!
        let request = MockHoroDataSeed.sample.readingRequests[0]

        try await service.deleteReadingRequest(id: request.id)

        let requests = try await service.fetchReadingRequests(for: customer.id, role: .customer)
        let threads = try await service.fetchChatThreads(for: customer.id, role: .customer)

        XCTAssertFalse(requests.contains { $0.id == request.id })
        XCTAssertFalse(threads.contains { $0.readingRequestId == request.id })
    }
}
