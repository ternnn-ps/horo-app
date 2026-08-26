import Combine
import Foundation

struct TestRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var notes: String
    var isCompleted: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

protocol RecordStoring {
    func load() -> [TestRecord]
    func save(_ records: [TestRecord])
}

struct UserDefaultsRecordStore: RecordStoring {
    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = "horo-test.records") {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> [TestRecord] {
        guard let data = userDefaults.data(forKey: key) else {
            return []
        }

        return (try? JSONDecoder().decode([TestRecord].self, from: data)) ?? []
    }

    func save(_ records: [TestRecord]) {
        guard let data = try? JSONEncoder().encode(records) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }
}

final class RecordListViewModel: ObservableObject {
    @Published private(set) var records: [TestRecord]

    private let store: RecordStoring

    var totalCount: Int {
        records.count
    }

    var activeCount: Int {
        records.filter { !$0.isCompleted }.count
    }

    var completedCount: Int {
        records.filter(\.isCompleted).count
    }

    init(store: RecordStoring = UserDefaultsRecordStore()) {
        self.store = store
        records = store.load().sorted { $0.updatedAt > $1.updatedAt }
    }

    func create(title: String, notes: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty else {
            return
        }

        let record = TestRecord(
            title: cleanTitle,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        records.insert(record, at: 0)
        persist()
    }

    func update(_ record: TestRecord, title: String, notes: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty,
              let index = records.firstIndex(where: { $0.id == record.id })
        else {
            return
        }

        records[index].title = cleanTitle
        records[index].notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        records[index].updatedAt = Date()
        sortRecords()
        persist()
    }

    func toggleCompletion(for record: TestRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else {
            return
        }

        records[index].isCompleted.toggle()
        records[index].updatedAt = Date()
        sortRecords()
        persist()
    }

    func delete(_ record: TestRecord) {
        records.removeAll { $0.id == record.id }
        persist()
    }

    private func sortRecords() {
        records.sort { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        store.save(records)
    }
}
