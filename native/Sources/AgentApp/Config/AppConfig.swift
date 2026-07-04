import Foundation

/// Decodes `native/config.json` — the single source of truth for brand/avatar identity,
/// also consumed at bundle time by `build-app.sh`. Keeping display name and bundle id out
/// of the type system is the naming-discipline requirement: the brand name lives only as a
/// config value, never as a literal in code.
public struct AppConfig: Decodable {
    public let displayName: String
    public let bundleIdentifier: String
    public let statusItemTitle: String
    public let avatar: String
}

public enum AppConfigError: Error {
    case resourceNotFound
}

public extension AppConfig {
    /// Loads `config.json` from the app bundle's `Resources/` — `make native-run` always
    /// launches the assembled `.app` (never a raw binary), and `build-app.sh` copies
    /// `config.json` into `Contents/Resources/config.json` at bundle time.
    static func loadFromBundle(_ bundle: Bundle = .main) throws -> AppConfig {
        guard let url = bundle.url(forResource: "config", withExtension: "json") else {
            throw AppConfigError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    /// Selects the `Avatar` conformer named by `config.avatar`. Adding a new avatar means
    /// adding a sibling conformer under `Render/Avatars/` and a case here — nothing else
    /// in the render layer changes. This is the one place outside `SlimeAvatar.swift`
    /// allowed to name that type — see the comment there.
    func makeAvatar() -> Avatar {
        switch avatar {
        case "slime": return SlimeAvatar()
        default: fatalError("AgentApp: unknown avatar '\(avatar)' in config.json")
        }
    }
}
