import Combine
import Foundation

enum ProfileAvatarStyle: String, CaseIterable, Codable, Identifiable {
    case ocean
    case sunrise
    case violet
    case forest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ocean:
            return "Ocean"
        case .sunrise:
            return "Sunrise"
        case .violet:
            return "Violet"
        case .forest:
            return "Forest"
        }
    }
}

struct UserProfile: Codable, Equatable {
    var fullName: String
    var role: String
    var email: String
    var phone: String
    var location: String
    var avatarStyle: ProfileAvatarStyle

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

    init(
        fullName: String,
        role: String,
        email: String,
        phone: String,
        location: String,
        avatarStyle: ProfileAvatarStyle = .ocean
    ) {
        self.fullName = fullName
        self.role = role
        self.email = email
        self.phone = phone
        self.location = location
        self.avatarStyle = avatarStyle
    }

    private enum CodingKeys: String, CodingKey {
        case fullName
        case role
        case email
        case phone
        case location
        case avatarStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        fullName = try container.decode(String.self, forKey: .fullName)
        role = try container.decode(String.self, forKey: .role)
        email = try container.decode(String.self, forKey: .email)
        phone = try container.decode(String.self, forKey: .phone)
        location = try container.decode(String.self, forKey: .location)
        avatarStyle = try container.decodeIfPresent(ProfileAvatarStyle.self, forKey: .avatarStyle) ?? .ocean
    }

    static let `default` = UserProfile(
        fullName: "Pacharapol S.",
        role: "Seer Operations",
        email: "pacharapol@example.com",
        phone: "+66 00 000 0000",
        location: "Bangkok, Thailand",
        avatarStyle: .ocean
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
            location: newProfile.location.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarStyle: newProfile.avatarStyle
        )

        guard !cleanProfile.fullName.isEmpty else {
            return
        }

        profile = cleanProfile
        store.save(cleanProfile)
    }
}
