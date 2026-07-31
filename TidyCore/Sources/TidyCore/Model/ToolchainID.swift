/// A developer tool or app whose presence gates whether a catalog item is
/// relevant on this machine.
public enum ToolchainID: String, Codable, CaseIterable, Sendable, Hashable {
    case xcode
    case homebrew
    case node
    case npm
    case pnpm
    case yarn
    case bun
    case cocoapods
    case pip
    case uv
    case deno
    case go
    case flutter
    case dart
    case gradle
    case android
    case git
    case chrome
    case safari
    case jetbrains
    case playwright

    public var displayName: String {
        switch self {
        case .xcode: return "Xcode"
        case .homebrew: return "Homebrew"
        case .node: return "Node.js"
        case .npm: return "npm"
        case .pnpm: return "pnpm"
        case .yarn: return "Yarn"
        case .bun: return "Bun"
        case .cocoapods: return "CocoaPods"
        case .pip: return "pip"
        case .uv: return "uv"
        case .deno: return "Deno"
        case .go: return "Go"
        case .flutter: return "Flutter"
        case .dart: return "Dart"
        case .gradle: return "Gradle"
        case .android: return "Android SDK"
        case .git: return "Git"
        case .chrome: return "Google Chrome"
        case .safari: return "Safari"
        case .jetbrains: return "JetBrains IDEs"
        case .playwright: return "Playwright"
        }
    }
}
