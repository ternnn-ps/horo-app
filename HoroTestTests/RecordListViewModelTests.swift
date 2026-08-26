import XCTest
@testable import HoroTest

final class RecordListViewModelTests: XCTestCase {
    func testCreateAddsRecordAndPersists() {
        let store = InMemoryRecordStore()
        let viewModel = RecordListViewModel(store: store)

        viewModel.create(title: " First record ", notes: " Notes ")

        XCTAssertEqual(viewModel.records.count, 1)
        XCTAssertEqual(viewModel.records.first?.title, "First record")
        XCTAssertEqual(viewModel.records.first?.notes, "Notes")
        XCTAssertEqual(store.savedRecords, viewModel.records)
    }

    func testCreateIgnoresEmptyTitle() {
        let store = InMemoryRecordStore()
        let viewModel = RecordListViewModel(store: store)

        viewModel.create(title: "   ", notes: "Draft")

        XCTAssertTrue(viewModel.records.isEmpty)
        XCTAssertTrue(store.savedRecords.isEmpty)
    }

    func testUpdateChangesExistingRecord() {
        let record = TestRecord(title: "Original", notes: "")
        let store = InMemoryRecordStore(records: [record])
        let viewModel = RecordListViewModel(store: store)

        viewModel.update(record, title: "Updated", notes: "More detail")

        XCTAssertEqual(viewModel.records.first?.title, "Updated")
        XCTAssertEqual(viewModel.records.first?.notes, "More detail")
        XCTAssertEqual(store.savedRecords.first?.title, "Updated")
    }

    func testToggleCompletionUpdatesRecord() {
        let record = TestRecord(title: "Todo", notes: "")
        let store = InMemoryRecordStore(records: [record])
        let viewModel = RecordListViewModel(store: store)

        viewModel.toggleCompletion(for: record)

        XCTAssertEqual(viewModel.activeCount, 0)
        XCTAssertEqual(viewModel.completedCount, 1)
        XCTAssertTrue(viewModel.records.first?.isCompleted == true)
    }

    func testDeleteRemovesRecord() {
        let record = TestRecord(title: "Delete me", notes: "")
        let store = InMemoryRecordStore(records: [record])
        let viewModel = RecordListViewModel(store: store)

        viewModel.delete(record)

        XCTAssertTrue(viewModel.records.isEmpty)
        XCTAssertTrue(store.savedRecords.isEmpty)
    }
}

final class UserProfileViewModelTests: XCTestCase {
    func testProfileInitialsUseFirstTwoNameParts() {
        let profile = UserProfile(
            fullName: "Test User",
            role: "",
            email: "",
            phone: "",
            location: ""
        )

        XCTAssertEqual(profile.initials, "TU")
    }

    func testUpdateProfileTrimsAndPersists() {
        let store = InMemoryUserProfileStore(profile: .default)
        let viewModel = UserProfileViewModel(store: store)

        viewModel.update(
            profile: UserProfile(
                fullName: " New Name ",
                role: " Tester ",
                email: " test@example.com ",
                phone: " 123 ",
                location: " Bangkok "
            )
        )

        XCTAssertEqual(viewModel.profile.fullName, "New Name")
        XCTAssertEqual(viewModel.profile.role, "Tester")
        XCTAssertEqual(store.savedProfile?.email, "test@example.com")
    }
}

private final class InMemoryRecordStore: RecordStoring {
    var savedRecords: [TestRecord]

    init(records: [TestRecord] = []) {
        savedRecords = records
    }

    func load() -> [TestRecord] {
        savedRecords
    }

    func save(_ records: [TestRecord]) {
        savedRecords = records
    }
}

private final class InMemoryUserProfileStore: UserProfileStoring {
    var savedProfile: UserProfile?
    private let initialProfile: UserProfile

    init(profile: UserProfile) {
        initialProfile = profile
    }

    func load() -> UserProfile {
        savedProfile ?? initialProfile
    }

    func save(_ profile: UserProfile) {
        savedProfile = profile
    }
}
