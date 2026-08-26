import Combine
import Foundation

struct UserProfile: Codable, Equatable {
    var fullName: String
    var role: String
    var email: String
    var phone: String
    var location: String

    var initials: String {
        let initials = fullName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()

        return initials.isEmpty ? "U" : initials
    }

    static let `default` = UserProfile(
        fullName: "Pacharapol S.",
        role: "Seer Operations",
        email: "pacharapol@example.com",
        phone: "+66 00 000 0000",
        location: "Bangkok, Thailand"
    )
}

protocol UserProfileStoring {
    func load() -> UserProfile
    func save(_ profile: UserProfile)
}

struct UserDefaultsUserProfileStore: UserProfileStoring {
    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = "horo-test.user-profile") {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> UserProfile {
        guard let data = userDefaults.data(forKey: key) else {
            return .default
        }

        return (try? JSONDecoder().decode(UserProfile.self, from: data)) ?? .default
    }

    func save(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }
}

final class UserProfileViewModel: ObservableObject {
    @Published private(set) var profile: UserProfile

    private let store: UserProfileStoring

    init(store: UserProfileStoring = UserDefaultsUserProfileStore()) {
        self.store = store
        profile = store.load()
    }

    func update(profile newProfile: UserProfile) {
        let cleanProfile = UserProfile(
            fullName: newProfile.fullName.trimmingCharacters(in: .whitespacesAndNewlines),
            role: newProfile.role.trimmingCharacters(in: .whitespacesAndNewlines),
            email: newProfile.email.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: newProfile.phone.trimmingCharacters(in: .whitespacesAndNewlines),
            location: newProfile.location.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard !cleanProfile.fullName.isEmpty else {
            return
        }

        profile = cleanProfile
        store.save(cleanProfile)
    }
}
