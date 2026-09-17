import Foundation

public enum ScanScopeMode: String, Equatable, Sendable {
    case quick
    case selectedProjects
    case fullHome
}

public enum ScanScopeAuthorizationError: Error, Equatable, Sendable {
    case policyUnavailable
    case invalidPolicy
    case invalidRoot
    case foreignConsent
    case expiredConsent
    case consumedConsent
}

public struct FullHomeScanConsent: Sendable {
    fileprivate let id: UUID
    fileprivate init(id: UUID) { self.id = id }
}

/// An immutable, bridge-issued read boundary. Its initializer is deliberately not public: app
/// code can request one from `ScanScopeAuthority`, but cannot turn a Boolean or an arbitrary path
/// into traversal authority.
public struct AuthorizedScanScope: Sendable {
    public let mode: ScanScopeMode
    public let roots: [String]
    public let excludedRoots: [String]
    public let policyRevision: UInt64
    fileprivate let authorityID: UUID
    fileprivate let grantID: UUID
    fileprivate let ownerID: UUID
    fileprivate let homeDirectory: String
    fileprivate let expiresAt: UInt64
    fileprivate let ledger: ScanScopeGrantLedger

    fileprivate init(mode: ScanScopeMode, roots: [String], excludedRoots: [String],
                     policyRevision: UInt64, authorityID: UUID, grantID: UUID,
                     ownerID: UUID, homeDirectory: String, expiresAt: UInt64,
                     ledger: ScanScopeGrantLedger) {
        self.mode = mode
        self.roots = roots
        self.excludedRoots = excludedRoots
        self.policyRevision = policyRevision
        self.authorityID = authorityID
        self.grantID = grantID
        self.ownerID = ownerID
        self.homeDirectory = homeDirectory
        self.expiresAt = expiresAt
        self.ledger = ledger
    }

    func consumeForStart(ownerID: UUID, environment: CleanEnvironment) throws {
        try ledger.consume(id: grantID, authorityID: authorityID, ownerID: ownerID,
            homeDirectory: PathGuard.canonicalize(environment.homeDirectory),
            policyRevision: policyRevision, expiresAt: expiresAt)
    }
}

private final class ScanScopeGrantLedger: @unchecked Sendable {
    private struct Grant {
        let authorityID: UUID
        let ownerID: UUID
        let homeDirectory: String
        let policyRevision: UInt64
        let expiresAt: UInt64
        var consumed: Bool
    }
    private let lock = NSLock()
    private let nowNanoseconds: @Sendable () -> UInt64
    private var grants: [UUID: Grant] = [:]

    init(nowNanoseconds: @escaping @Sendable () -> UInt64) {
        self.nowNanoseconds = nowNanoseconds
    }

    func register(id: UUID, authorityID: UUID, ownerID: UUID, homeDirectory: String,
                  policyRevision: UInt64, expiresAt: UInt64) {
        lock.lock(); defer { lock.unlock() }
        grants[id] = Grant(authorityID: authorityID, ownerID: ownerID,
            homeDirectory: homeDirectory, policyRevision: policyRevision,
            expiresAt: expiresAt, consumed: false)
    }

    func consume(id: UUID, authorityID: UUID, ownerID: UUID, homeDirectory: String,
                 policyRevision: UInt64, expiresAt: UInt64) throws {
        lock.lock(); defer { lock.unlock() }
        guard var grant = grants[id], !grant.consumed else {
            throw ScanScopeAuthorizationError.consumedConsent
        }
        guard grant.authorityID == authorityID, grant.ownerID == ownerID,
              grant.homeDirectory == homeDirectory,
              grant.policyRevision == policyRevision,
              grant.expiresAt == expiresAt else {
            throw ScanScopeAuthorizationError.foreignConsent
        }
        guard nowNanoseconds() < grant.expiresAt else {
            grants.removeValue(forKey: id)
            throw ScanScopeAuthorizationError.expiredConsent
        }
        grant.consumed = true
        grants[id] = grant
    }
}

/// Owns the one-run full-home consent ledger and derives every normal scope from the bridge's
/// acknowledged document. This object is app-owned and shared across windows.
@MainActor
public final class ScanScopeAuthority {
    private struct IssuedConsent {
        let ownerID: UUID
        let policyRevision: UInt64
        let home: String
        let expiresAt: UInt64
        var consumed: Bool
    }

    private let id = UUID()
    private let bridge: ExecutionPolicyBridge
    private let homeDirectory: String
    private let nowNanoseconds: @Sendable () -> UInt64
    private let consentLifetimeNanoseconds: UInt64
    private let grantLedger: ScanScopeGrantLedger
    private var consents: [UUID: IssuedConsent] = [:]

    public init(bridge: ExecutionPolicyBridge, homeDirectory: String) {
        self.bridge = bridge
        self.homeDirectory = PathGuard.canonicalize(homeDirectory)
        let clock: @Sendable () -> UInt64 = {
            UInt64(max(0, ProcessInfo.processInfo.systemUptime) * 1_000_000_000)
        }
        self.nowNanoseconds = clock
        self.consentLifetimeNanoseconds = 5 * 60 * 1_000_000_000
        self.grantLedger = ScanScopeGrantLedger(nowNanoseconds: clock)
    }

    internal init(bridge: ExecutionPolicyBridge, homeDirectory: String,
                  consentLifetimeNanoseconds: UInt64,
                  nowNanoseconds: @escaping @Sendable () -> UInt64) {
        self.bridge = bridge
        self.homeDirectory = PathGuard.canonicalize(homeDirectory)
        self.consentLifetimeNanoseconds = consentLifetimeNanoseconds
        self.nowNanoseconds = nowNanoseconds
        self.grantLedger = ScanScopeGrantLedger(nowNanoseconds: nowNanoseconds)
    }

    public func authorizePolicyDefault(ownerID: UUID) throws -> AuthorizedScanScope {
        _ = ownerID // Keeps the call site explicitly window-bound even though default scope is reusable.
        let snapshot = try policySnapshot()
        let mode: ScanScopeMode
        guard case .stored(.choice(let raw))? = snapshot.policy.fields[
            SettingID(rawValue: "scan.defaultScope")]?.value,
              let resolved = ScanScopeMode(rawValue: raw), resolved != .fullHome else {
            throw ScanScopeAuthorizationError.invalidPolicy
        }
        mode = resolved
        let roots: [String]
        switch mode {
        case .quick:
            roots = quickRoots(environment: snapshot.environment)
        case .selectedProjects:
            roots = try selectedProjectRoots(snapshot.environment.gitRoots)
        case .fullHome:
            throw ScanScopeAuthorizationError.invalidPolicy
        }
        return try authorization(mode: mode, roots: roots, ownerID: ownerID,
            snapshot: snapshot)
    }

    public func issueFullHomeConsent(ownerID: UUID) throws -> FullHomeScanConsent {
        let snapshot = try policySnapshot()
        reapExpiredConsents()
        let token = UUID()
        let now = nowNanoseconds()
        let (expiry, overflow) = now.addingReportingOverflow(consentLifetimeNanoseconds)
        guard !overflow else { throw ScanScopeAuthorizationError.invalidPolicy }
        consents[token] = IssuedConsent(ownerID: ownerID,
            policyRevision: snapshot.envelope.revision, home: homeDirectory,
            expiresAt: expiry, consumed: false)
        return FullHomeScanConsent(id: token)
    }

    public func authorizeFullHome(consent: FullHomeScanConsent,
                                  ownerID: UUID) throws -> AuthorizedScanScope {
        let snapshot = try policySnapshot()
        guard var issued = consents[consent.id] else {
            throw ScanScopeAuthorizationError.consumedConsent
        }
        guard !issued.consumed else { throw ScanScopeAuthorizationError.consumedConsent }
        guard issued.ownerID == ownerID, issued.home == homeDirectory else {
            throw ScanScopeAuthorizationError.foreignConsent
        }
        guard nowNanoseconds() < issued.expiresAt else {
            consents.removeValue(forKey: consent.id)
            throw ScanScopeAuthorizationError.expiredConsent
        }
        guard issued.policyRevision == snapshot.envelope.revision else {
            consents.removeValue(forKey: consent.id)
            throw ScanScopeAuthorizationError.expiredConsent
        }
        issued.consumed = true
        consents[consent.id] = issued
        return try authorization(mode: .fullHome, roots: [homeDirectory],
            ownerID: ownerID, snapshot: snapshot)
    }

    private struct PolicySnapshot {
        let envelope: SettingsEnvelope
        let policy: EffectivePolicy
        let environment: CleanEnvironment
    }

    private func policySnapshot() throws -> PolicySnapshot {
        guard let envelope = bridge.acknowledgedEnvelope, envelope.revision > 0 else {
            throw ScanScopeAuthorizationError.policyUnavailable
        }
        let profiles = envelope.preferences?.profiles ?? []
        let profile = envelope.activeProfileID.flatMap { active in
            profiles.first { $0.id == active }
        }
        if envelope.activeProfileID != nil, profile == nil {
            throw ScanScopeAuthorizationError.invalidPolicy
        }
        var layers: [PolicyLayer: PolicyValues] = [
            .global: envelope.preferences?.global ?? .init()
        ]
        if let profile { layers[.profile] = profile.values }
        let policy: EffectivePolicy
        do {
            policy = try PolicyResolver.resolve(.init(layers: layers,
                selectedVolumeID: nil, approvedVolumeIDs: [], capacityBytes: nil,
                logicalCPUCount: max(1, ProcessInfo.processInfo.activeProcessorCount),
                lowPower: false, seriousThermal: false, critical: false,
                mandatoryExclusions: Set(CleanEnvironment.defaultProtectedRoots(
                    homeDirectory: homeDirectory))))
        } catch {
            throw ScanScopeAuthorizationError.invalidPolicy
        }
        return PolicySnapshot(envelope: envelope, policy: policy,
            environment: envelope.config.makePolicyEnvironment(
                homeDirectory: homeDirectory, detectedTools: []))
    }

    private func quickRoots(environment: CleanEnvironment) -> [String] {
        let fileManager = FileManager.default
        let relativeRoots = [
            "Library/Developer/Xcode/DerivedData",
            "Library/Developer/Xcode/DocumentationCache",
            "Library/Developer/CoreSimulator/Caches",
            "Library/Developer/CoreSimulator/Temp",
            "Library/Caches/org.swift.swiftpm",
            "Library/org.swift.swiftpm",
            "Library/Caches/typescript",
            "Library/Caches/electron",
            "Library/Caches/electron-builder",
            "Library/Caches/com.apple.helpd",
            "Library/Application Support/Claude/Cache",
            "Library/Application Support/Claude/Code Cache",
            "Library/Application Support/Claude/GPUCache",
            ".npm/_cacache",
            ".cache/uv",
            ".cache/puppeteer",
            ".bun/install/cache",
            ".gradle/caches",
            ".npm/_npx",
            ".m2/repository",
            ".cocoapods/repos",
            "Library/Android/sdk/temp"
        ]
        let candidates = relativeRoots.map { PathGuard.canonicalize(environment.path($0)) }
            .filter(fileManager.fileExists(atPath:))
        return canonicalMinimalRoots(candidates)
    }

    private func selectedProjectRoots(_ rawRoots: [String]) throws -> [String] {
        var roots: [String] = []
        for raw in rawRoots {
            let canonical = PathGuard.canonicalize(raw)
            guard canonical != homeDirectory,
                  PathGuard.isEqualOrDescendant(canonical, of: homeDirectory) else {
                throw ScanScopeAuthorizationError.invalidRoot
            }
            roots.append(canonical)
        }
        return canonicalMinimalRoots(roots)
    }

    private func authorization(mode: ScanScopeMode, roots: [String], ownerID: UUID,
                               snapshot: PolicySnapshot) throws -> AuthorizedScanScope {
        let exclusions = snapshot.policy.exclusions.map(PathGuard.canonicalize).sorted()
        let narrowed = roots.filter { root in
            !exclusions.contains { PathGuard.isEqualOrDescendant(root, of: $0) }
        }
        let now = nowNanoseconds()
        let (expiry, overflow) = now.addingReportingOverflow(consentLifetimeNanoseconds)
        guard !overflow else { throw ScanScopeAuthorizationError.invalidPolicy }
        let grantID = UUID()
        grantLedger.register(id: grantID, authorityID: id, ownerID: ownerID,
            homeDirectory: homeDirectory, policyRevision: snapshot.envelope.revision,
            expiresAt: expiry)
        return AuthorizedScanScope(mode: mode, roots: narrowed, excludedRoots: exclusions,
            policyRevision: snapshot.envelope.revision, authorityID: id,
            grantID: grantID, ownerID: ownerID, homeDirectory: homeDirectory,
            expiresAt: expiry, ledger: grantLedger)
    }

    private func canonicalMinimalRoots(_ rawRoots: [String]) -> [String] {
        let sorted = Set(rawRoots.map(PathGuard.canonicalize)).sorted {
            ($0.split(separator: "/").count, $0) < ($1.split(separator: "/").count, $1)
        }
        var result: [String] = []
        for root in sorted where !result.contains(where: {
            PathGuard.isEqualOrDescendant(root, of: $0)
        }) {
            result.append(root)
        }
        return result.sorted()
    }

    private func reapExpiredConsents() {
        let now = nowNanoseconds()
        consents = consents.filter { !$0.value.consumed && $0.value.expiresAt > now }
    }
}
