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

enum SeerPersonalityTrait: String, CaseIterable, Codable, Identifiable {
    case listener
    case talkative
    case fun
    case calm
    case comforting

    var id: String { rawValue }

    static let defaultSelection: [SeerPersonalityTrait] = [
        .listener,
        .fun,
        .comforting
    ]
}

enum SeerSkillType: String, CaseIterable, Codable, Identifiable {
    case tarot
    case oracle
    case sacred
    case sevenNineBase

    var id: String { rawValue }

    static let defaultSelection: [SeerSkillType] = [
        .tarot,
        .oracle
    ]
}

struct UserProfile: Codable, Equatable {
    var fullName: String
    var role: String
    var email: String
    var phone: String
    var location: String
    var avatarStyle: ProfileAvatarStyle
    var reviewRating: Double
    var reviewCount: Int
    var personalityTraits: [SeerPersonalityTrait]
    var seerSkills: [SeerSkillType]

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
        avatarStyle: ProfileAvatarStyle = .ocean,
        reviewRating: Double = 4.8,
        reviewCount: Int = 128,
        personalityTraits: [SeerPersonalityTrait] = SeerPersonalityTrait.defaultSelection,
        seerSkills: [SeerSkillType] = SeerSkillType.defaultSelection
    ) {
        self.fullName = fullName
        self.role = role
        self.email = email
        self.phone = phone
        self.location = location
        self.avatarStyle = avatarStyle
        self.reviewRating = reviewRating
        self.reviewCount = reviewCount
        self.personalityTraits = personalityTraits
        self.seerSkills = seerSkills
    }

    private enum CodingKeys: String, CodingKey {
        case fullName
        case role
        case email
        case phone
        case location
        case avatarStyle
        case reviewRating
        case reviewCount
        case personalityTraits
        case seerSkills
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        fullName = try container.decode(String.self, forKey: .fullName)
        role = try container.decode(String.self, forKey: .role)
        email = try container.decode(String.self, forKey: .email)
        phone = try container.decode(String.self, forKey: .phone)
        location = try container.decode(String.self, forKey: .location)
        avatarStyle = try container.decodeIfPresent(ProfileAvatarStyle.self, forKey: .avatarStyle) ?? .ocean
        reviewRating = try container.decodeIfPresent(Double.self, forKey: .reviewRating) ?? 4.8
        reviewCount = try container.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 128
        personalityTraits = try container.decodeIfPresent([SeerPersonalityTrait].self, forKey: .personalityTraits) ?? SeerPersonalityTrait.defaultSelection
        seerSkills = try container.decodeIfPresent([SeerSkillType].self, forKey: .seerSkills) ?? SeerSkillType.defaultSelection
    }

    static let `default` = UserProfile(
        fullName: "Pacharapol S.",
        role: "Seer Operations",
        email: "pacharapol@example.com",
        phone: "+66 00 000 0000",
        location: "Bangkok, Thailand",
        avatarStyle: .ocean,
        reviewRating: 4.8,
        reviewCount: 128,
        personalityTraits: SeerPersonalityTrait.defaultSelection,
        seerSkills: SeerSkillType.defaultSelection
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
            avatarStyle: newProfile.avatarStyle,
            reviewRating: min(max(newProfile.reviewRating, 0), 5),
            reviewCount: max(newProfile.reviewCount, 0),
            personalityTraits: newProfile.personalityTraits,
            seerSkills: newProfile.seerSkills
        )

        guard !cleanProfile.fullName.isEmpty else {
            return
        }

        profile = cleanProfile
        store.save(cleanProfile)
    }
}
