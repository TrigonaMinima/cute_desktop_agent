import Foundation

/// Decodes `native/config.json` — the single source of truth for brand/avatar identity,
/// also consumed at bundle time by `build-app.sh`. Keeping display name and bundle id out
/// of the type system is the naming-discipline requirement: the brand name lives only as a
/// config value, never as a literal in code.
public struct AppConfig: Decodable {
    public let displayName: String
    public let bundleIdentifier: String
    public let statusItemTitle: String
    public let avatar: AvatarKind
    /// Which brain drives the agent — optional so an older config.json without the key
    /// still decodes; read through `brainKind` for the default.
    private let brain: BrainKind?

    /// The emergent brain is the default; `"brain": "classic"` in config.json picks the
    /// blob.js-parity StateMachine at boot instead. This is only the *default* — the
    /// menu-bar "Brain" submenu (`BrainMenuController`) can switch live afterward, and a
    /// prior menu selection persisted in UserDefaults overrides this at boot (see
    /// `AppDelegate.storedBrainKind`).
    public var brainKind: BrainKind { brain ?? .emergent }
}

/// The set of `AgentBrain` conformers `config.json`'s `brain` field — and the menu-bar
/// "Brain" submenu — may name. Same decode-to-enum discipline as `AvatarKind`: an
/// unrecognized value is a config decode error at launch, not a fallback deep in brain
/// selection.
public enum BrainKind: String, Decodable, CaseIterable {
    case classic
    case emergent

    /// Menu row label — `TemperamentPreset.displayName`'s sibling.
    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .emergent: return "Emergent"
        }
    }
}

/// The set of `Avatar` conformers `config.json`'s `avatar` field may name. Decoding
/// straight into this enum (rather than resolving a raw `String` later in `makeAvatar`)
/// turns an unrecognized `avatar` value into a config decode error, caught by
/// `AppConfig.loadFromBundle`'s caller, instead of a `fatalError` reached deep inside
/// avatar selection.
public enum AvatarKind: String, Decodable {
    case slime
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
    /// adding a sibling conformer under `Render/Avatars/` and a case to `AvatarKind` —
    /// nothing else in the render layer changes. This is the one place outside
    /// `SlimeAvatar.swift` allowed to name that type — see the comment there. The switch
    /// is exhaustive (no `default`): a new `AvatarKind` case with no matching arm here is
    /// a compile error, not a runtime crash.
    func makeAvatar() -> Avatar {
        switch avatar {
        case .slime: return SlimeAvatar()
        }
    }
}
