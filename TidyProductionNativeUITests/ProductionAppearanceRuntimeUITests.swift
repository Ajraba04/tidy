import XCTest

/// These exercise SwiftUI presentation environments in the actual production
/// scenes. They do not claim system preference delivery or human AT acceptance.
final class ProductionAppearanceRuntimeUITests: XCTestCase {
    @MainActor
    func testProductionLightAppearanceKeepsSettingsAndCleanupUsable() throws {
        try verifyAppearance(dark: false, increased: false, reducedMotion: false)
    }

    @MainActor
    func testProductionDarkAppearanceKeepsSettingsAndCleanupUsable() throws {
        try verifyAppearance(dark: true, increased: false, reducedMotion: false)
    }

    @MainActor
    func testProductionLightIncreasedContrastAndReducedMotion() throws {
        try verifyAppearance(dark: false, increased: true, reducedMotion: true)
    }

    @MainActor
    func testProductionDarkIncreasedContrastAndReducedMotion() throws {
        try verifyAppearance(dark: true, increased: true, reducedMotion: true)
    }

    @MainActor
    func testProductionCompactSettingsAndCleanupPassAutomatedAccessibilityAudit() throws {
        continueAfterFailure = false
        assertAuditIssueClassificationBoundaries()
        try verifyAppearance(dark: false, increased: false, reducedMotion: false,
                             compact: true)
    }

    @MainActor
    private func verifyAppearance(dark: Bool, increased: Bool,
                                  reducedMotion: Bool, compact: Bool = false) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
            "--tidy-runtime-cleanup-on-termination",
            dark ? "--tidy-runtime-appearance-dark" : "--tidy-runtime-appearance-light"]
        if increased { app.launchArguments.append("--tidy-runtime-increased-contrast") }
        if reducedMotion { app.launchArguments.append("--tidy-runtime-reduce-motion") }
        if compact { app.launchArguments.append("--tidy-runtime-compact") }
        addTeardownBlock { @MainActor in self.cleanup(app) }
        addTeardownBlock { @MainActor in self.restoreVerificationControlsIfNeeded(app) }
        app.launch()

        let control = app.windows["Tidy Production Runtime Verification"]
        let attestation = control.staticTexts["runtime.appearance.environment"]
        XCTAssertTrue(attestation.waitForExistence(timeout: 15), app.debugDescription)
        let expected = "\(dark ? "dark" : "light") "
            + "\(increased ? "increased" : "standard") "
            + "motion:\(reducedMotion ? "reduced" : "normal")"
        XCTAssertEqual(attestation.value as? String, expected)
        XCTAssertEqual(control.staticTexts["runtime.synthetic.isolation"].value as? String,
                       "isolated")
        XCTAssertEqual(control.staticTexts["runtime.authorization"].value as? String,
                       "all-denied")
        let syntheticHome = control.staticTexts["runtime.synthetic.home"].value as? String
        XCTAssertTrue(syntheticHome?.hasPrefix("/") == true,
            "Runtime appearance host did not attest an absolute fixture home")

        control.buttons["runtime.open.settings"].click()
        let settings = app.windows["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        if compact {
            let geometry = control.staticTexts["runtime.settings.geometry"]
            XCTAssertTrue(geometry.waitForExistence(timeout: 5))
            let description = geometry.value as? String ?? "missing"
            let geometryAttachment = XCTAttachment(string: description)
            geometryAttachment.name = "Settings window size constraints"
            geometryAttachment.lifetime = .keepAlways
            add(geometryAttachment)
            // A fixed host-only AppKit input sets the real production window's
            // content size. This tests compact layout, not a synthetic drag.
            control.click()
            control.buttons["runtime.settings.compact"].click()
            settings.click()
            XCTAssertLessThanOrEqual(settings.frame.width, 500,
                "Settings could not resize to its compact width: \(description)")
        }
        let editor = settings.checkBoxes["settings.control.feature.headroom"]
        let metadata = settings.descendants(matching: .any)
            .matching(identifier: "settings.metadata.feature.headroom").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), settings.debugDescription)
        XCTAssertTrue(editor.isEnabled)
        XCTAssertTrue(editor.isHittable)
        XCTAssertTrue(metadata.exists)
        XCTAssertNotEqual(metadata.elementType, .staticText)
        XCTAssertEqual(metadata.label, "Feature Headroom, feature.headroom")
        XCTAssertNotEqual(metadata.identifier, editor.identifier)
        let lines = metadata.staticTexts.allElementsBoundByIndex
        XCTAssertEqual(lines.count, 7, metadata.debugDescription)
        XCTAssertTrue(lines.allSatisfy { !($0.value as? String ?? $0.label).isEmpty }, metadata.debugDescription)
        let expectedLines = [
            "Configure feature headroom with Tidy's safe default.",
            "Default: On", "Effective: On", "Source: Built-in", "Rule: On or off",
            "Changes apply to future policy planning and never start cleanup by themselves. Effect: This change invalidates the current cleanup plan."]
        for (index, text) in expectedLines.enumerated() {
            let child = metadata.staticTexts["settings.metadata.feature.headroom.primary.\(index)"]
            XCTAssertEqual(child.value as? String ?? child.label, text, metadata.debugDescription)
        }
        let availability = metadata.staticTexts["settings.metadata.feature.headroom.availability"]
        XCTAssertEqual(availability.value as? String ?? availability.label,
            "Available according to the policy layer and editor shown here. Resolution: restriction. Layers: global, profile.",
            metadata.debugDescription)
        XCTAssertTrue(settings.frame.contains(editor.frame))
        XCTAssertTrue(settings.frame.contains(metadata.frame))
        XCTAssertGreaterThanOrEqual(metadata.frame.height, 120,
                                   "The seven-line metadata block collapsed")
        let row = settings.descendants(matching: .any)["settings.row.feature.headroom"]
        XCTAssertGreaterThanOrEqual(row.frame.height, metadata.frame.height + editor.frame.height)
        let settingsViewport = settings.scrollViews.firstMatch
        XCTAssertTrue(settingsViewport.frame.contains(metadata.frame),
            "The settings metadata is clipped by its scroll viewport: "
                + "viewport=\(settingsViewport.frame), metadata=\(metadata.frame)")
        capture(settings, name: "\(expected)-settings")
        if compact {
            hideVerificationControls(app, control: control, subjectWindow: settings)
            try auditSettingsWithViewportProof(app, subjectWindow: settings)
            restoreVerificationControlsIfNeeded(app)
            settings.click()
        }

        let search = settings.textFields["settings.search"]
        XCTAssertEqual(search.label, "Search settings")
        search.click()
        search.typeText(String(repeating: "long-query-", count: 8))
        XCTAssertEqual(search.value as? String, String(repeating: "long-query-", count: 8))
        let noMatches = settings.staticTexts["No settings match"]
        XCTAssertTrue(noMatches.waitForExistence(timeout: 10), settings.debugDescription)
        XCTAssertTrue(settingsViewport.frame.contains(noMatches.frame),
                      "The no-results explanation is clipped by its scroll viewport")
        capture(settings, name: "\(expected)-long-search")
        settings.typeKey("w", modifierFlags: .command)
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: settings)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)

        control.click()
        control.buttons["runtime.open.clean.safe"].click()
        let clean = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "clean")).firstMatch
        XCTAssertTrue(clean.waitForExistence(timeout: 10), app.debugDescription)
        let cleanNow = clean.buttons["Clean Now"]
        XCTAssertTrue(cleanNow.waitForExistence(timeout: 45), clean.debugDescription)
        XCTAssertFalse(cleanNow.isEnabled)
        XCTAssertTrue(clean.frame.contains(cleanNow.frame))
        capture(clean, name: "\(expected)-safe-clean")
        if compact {
            hideVerificationControls(app, control: control, subjectWindow: clean)
            try audit(app, subjectWindow: clean)
            restoreVerificationControlsIfNeeded(app)
        }
    }

    @MainActor
    private func hideVerificationControls(
        _ app: XCUIApplication,
        control: XCUIElement,
        subjectWindow: XCUIElement
    ) {
        control.click()
        control.buttons["runtime.audit.hide"].click()
        XCTAssertFalse(control.exists, "Runtime verification controls remained visible")
        XCTAssertTrue(subjectWindow.exists, "Audit subject disappeared with the controls")
        let visibleWindows = app.windows.allElementsBoundByIndex
        XCTAssertEqual(visibleWindows.count, 1,
            "Expected only the audit subject after hiding controls: \(app.debugDescription)")
        XCTAssertEqual(visibleWindows.first?.frame, subjectWindow.frame,
            "The remaining app window is not the audit subject")
    }

    @MainActor
    private func restoreVerificationControlsIfNeeded(_ app: XCUIApplication) {
        guard app.state != .notRunning else { return }
        let control = app.windows["Tidy Production Runtime Verification"]
        guard !control.exists else { return }
        app.activate()
        let menu = app.menuBars.menuBarItems["Runtime Verification"]
        XCTAssertTrue(menu.exists, app.debugDescription)
        menu.click()
        let showControls = app.menuItems["Show Verification Controls"]
        XCTAssertTrue(showControls.exists, app.debugDescription)
        showControls.click()
        XCTAssertTrue(control.exists, "Runtime verification controls were not restored")
    }

    private struct AuditElementStamp: Equatable {
        let identifier: String
        let label: String
        let kind: UInt
        let frame: CGRect
    }

    private struct MetadataIdentity: Equatable {
        let childID: String
        let childLabel: String
        let childKind: UInt
        let groupID: String
        let groupLabel: String
        let groupKind: UInt
        let text: String
    }

    private struct MetadataStamp: Equatable {
        let identity: MetadataIdentity
        let childFrame: CGRect
        let groupFrame: CGRect
    }

    private struct SettingsAuditSnapshot: Equatable {
        let subject: AuditElementStamp
        let windows: [AuditElementStamp]
        let viewport: AuditElementStamp
        let metadata: [String: MetadataStamp]
    }

    private struct ViewportProofLedger {
        struct Coverage {
            let identity: MetadataIdentity
            let fullAuditNumber: Int
        }
        var obligations: [String: MetadataIdentity] = [:]
        var observed: [String: MetadataIdentity] = [:]
        var coverage: [String: Coverage] = [:]
        var provenGroups: Set<String> = []
        var auditNumber = 0
        var unresolved: [MetadataIdentity] {
            obligations.values.filter { coverage[$0.childID]?.identity != $0 }
                .sorted { $0.childID < $1.childID }
        }
        mutating func observe(_ snapshot: SettingsAuditSnapshot) throws {
            for (id, child) in snapshot.metadata {
                if let prior = observed[id], prior != child.identity {
                    throw ViewportProofFailure.invalid("Re-resolved metadata identity or text changed")
                }
                guard observed[id] != nil || observed.count < 56 else {
                    throw ViewportProofFailure.invalid("Observed metadata capacity exceeded")
                }
                observed[id] = child.identity
            }
        }
        mutating func deferContrast(_ identity: MetadataIdentity) throws {
            if let prior = obligations[identity.childID], prior != identity {
                throw ViewportProofFailure.invalid("Deferred metadata content changed")
            }
            guard obligations[identity.childID] != nil || obligations.count < 56 else {
                throw ViewportProofFailure.invalid("Metadata obligation capacity exceeded")
            }
            // This exact obligation exists before an issue is deferred, even
            // when an earlier full visible audit already covers the same text.
            obligations[identity.childID] = identity
        }
    }

    private enum ViewportProofFailure: Error {
        case invalid(String)
    }

    private static let metadataFeatures = ["headroom", "buildPrep", "projects", "rescue",
        "ecosystems", "budgets", "history", "maintenance"]

    private static func metadataChildIDs(groupID: String) -> [String] {
        (0..<6).map { groupID + ".primary.\($0)" } + [groupID + ".availability"]
    }

    @MainActor
    private func uniqueElement(_ query: XCUIElementQuery, description: String) throws -> XCUIElement {
        guard query.count == 1 else { throw ViewportProofFailure.invalid("Nonunique/missing \(description)") }
        let element = query.element(boundBy: 0)
        guard element.exists else { throw ViewportProofFailure.invalid("Missing \(description)") }
        return element
    }

    @MainActor
    private func elementStamp(_ element: XCUIElement) throws -> AuditElementStamp {
        guard Self.isValidAuditFrame(element.frame) else {
            throw ViewportProofFailure.invalid("Invalid frame for \(element.identifier)")
        }
        return AuditElementStamp(identifier: element.identifier, label: element.label,
            kind: element.elementType.rawValue, frame: element.frame)
    }

    @MainActor
    private func settingsAuditSnapshot(_ app: XCUIApplication,
                                       subjectWindow: XCUIElement) throws -> SettingsAuditSnapshot {
        let subject = try elementStamp(subjectWindow)
        guard subjectWindow.elementType == .window,
              !subject.identifier.isEmpty || !subject.label.isEmpty else {
            throw ViewportProofFailure.invalid("Invalid Settings window identity")
        }
        let windows = try app.windows.allElementsBoundByIndex.filter(\.exists).map(elementStamp)
        guard !windows.isEmpty, windows.filter({ $0 == subject }).count == 1,
              windows.allSatisfy({ !$0.identifier.isEmpty || !$0.label.isEmpty }),
              Set(windows.map { "\($0.kind)|\($0.identifier)|\($0.label)" }).count == windows.count else {
            throw ViewportProofFailure.invalid("Invalid/duplicate app window identities")
        }
        let viewportElement = try uniqueElement(subjectWindow.scrollViews
            .matching(identifier: "settings.content"), description: "settings.content viewport")
        let viewport = try elementStamp(viewportElement)
        guard subject.frame.contains(viewport.frame) else {
            throw ViewportProofFailure.invalid("Settings viewport escapes its window")
        }
        var metadata: [String: MetadataStamp] = [:]
        for feature in Self.metadataFeatures {
            let groupID = "settings.metadata.feature." + feature
            let groups = subjectWindow.descendants(matching: .any).matching(identifier: groupID)
            // Lazy stacks need not materialize every allowlisted group. A
            // reported child can only be deferred from a complete captured group.
            if groups.count == 0 { continue }
            let group = try uniqueElement(groups, description: groupID)
            let childCount = group.staticTexts.count
            guard childCount <= 7 else {
                throw ViewportProofFailure.invalid("Unexpected metadata child count \(groupID)")
            }
            if childCount != 7 { continue }
            let groupStamp = try elementStamp(group)
            guard group.elementType != .staticText, !groupStamp.label.isEmpty else {
                throw ViewportProofFailure.invalid("Invalid real metadata group \(groupID)")
            }
            for childID in Self.metadataChildIDs(groupID: groupID) {
                let child = try uniqueElement(group.staticTexts.matching(identifier: childID), description: childID)
                _ = try uniqueElement(subjectWindow.staticTexts.matching(identifier: childID), description: childID)
                let stamp = try elementStamp(child)
                let text = child.value as? String ?? child.label
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ViewportProofFailure.invalid("Empty real metadata text \(childID)")
                }
                let identity = MetadataIdentity(childID: childID, childLabel: stamp.label, childKind: stamp.kind,
                    groupID: groupID, groupLabel: groupStamp.label, groupKind: groupStamp.kind, text: text)
                metadata[childID] = MetadataStamp(identity: identity,
                    childFrame: stamp.frame, groupFrame: groupStamp.frame)
            }
        }
        guard metadata.count <= 56 else { throw ViewportProofFailure.invalid("Metadata inventory capacity exceeded") }
        return SettingsAuditSnapshot(subject: subject, windows: windows, viewport: viewport, metadata: metadata)
    }

    private func requireSameSettingsContent(_ current: SettingsAuditSnapshot,
                                            initial: SettingsAuditSnapshot,
                                            ledger: inout ViewportProofLedger) throws {
        guard current.subject == initial.subject, current.windows == initial.windows,
              current.viewport == initial.viewport else {
            throw ViewportProofFailure.invalid("Settings window or viewport identity/geometry changed")
        }
        try ledger.observe(current)
    }

    private static func isViewportClippedContrast(auditType: XCUIAccessibilityAuditType,
                                                  child: CGRect, group: CGRect,
                                                  window: CGRect, viewport: CGRect) -> Bool {
        guard auditType == .contrast, [child, group, window, viewport].allSatisfy(isValidAuditFrame),
              window.contains(viewport), group.contains(child),
              child.minX >= viewport.minX, child.maxX <= viewport.maxX else { return false }
        return child.maxY < viewport.minY || child.minY > viewport.maxY
    }

    private static func groupIsFullyVisible(_ groupID: String, in snapshot: SettingsAuditSnapshot) -> Bool {
        let ids = metadataChildIDs(groupID: groupID)
        return ids.allSatisfy { id in
            guard let child = snapshot.metadata[id] else { return false }
            return child.groupFrame.contains(child.childFrame)
                && snapshot.viewport.frame.contains(child.groupFrame)
                && snapshot.subject.frame.contains(child.groupFrame)
                && snapshot.viewport.frame.contains(child.childFrame)
                && snapshot.subject.frame.contains(child.childFrame)
        }
    }

    @MainActor
    private func runSettingsFullAudit(_ app: XCUIApplication, subjectWindow: XCUIElement,
                                      initial: SettingsAuditSnapshot, provingGroup: String,
                                      ledger: inout ViewportProofLedger) throws {
        let before = try settingsAuditSnapshot(app, subjectWindow: subjectWindow)
        try requireSameSettingsContent(before, initial: initial, ledger: &ledger)
        guard Self.groupIsFullyVisible(provingGroup, in: before) else {
            throw ViewportProofFailure.invalid("Positive audit group is not wholly visible")
        }
        var rejected = false
        var pending = ledger
        pending.auditNumber += 1
        try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription]) { issue in
            let element = issue.element
            var deferred = false
            var legacyOffWindow = false
            var explanation = "Not eligible for exact viewport deferral"
            do {
                let during = try self.settingsAuditSnapshot(app, subjectWindow: subjectWindow)
                guard during == before else { throw ViewportProofFailure.invalid("Audit snapshot changed during full audit") }
                if let element, let known = before.metadata[element.identifier],
                   known.identity.groupID != provingGroup,
                   element.elementType == .staticText,
                   element.frame == known.childFrame,
                   (element.value as? String ?? element.label) == known.identity.text,
                   element.label == known.identity.childLabel,
                   Self.isViewportClippedContrast(auditType: issue.auditType, child: known.childFrame,
                       group: known.groupFrame, window: before.subject.frame, viewport: before.viewport.frame) {
                    try pending.deferContrast(known.identity)
                    deferred = true
                    if let proof = pending.coverage[known.identity.childID], proof.identity == known.identity {
                        explanation = "Same child/text previously passed full audit \(proof.fullAuditNumber) while its whole group was visible"
                    } else {
                        explanation = "Exact clipped child deferred; a full audit with its whole group visible remains obligatory"
                    }
                } else if !(element?.identifier.hasPrefix("settings.metadata.") ?? false) {
                    // Preserve the original strict classifier only for unrelated
                    // elements, after the complete live snapshot matched.
                    legacyOffWindow = Self.shouldIgnoreAuditIssue(auditType: issue.auditType,
                        elementFrame: element?.frame, subjectWindow: before.subject.frame,
                        appWindows: before.windows.map(\.frame))
                    if legacyOffWindow { explanation = "Original wholly-off-app-window contrast classifier" }
                }
            } catch {
                explanation = "Viewport proof rejected: \(error)"
            }
            let geometry = "auditType=\(issue.auditType.rawValue); subject=\(before.subject); "
                + "appWindows=\(before.windows); viewport=\(before.viewport); "
                + "elementFrame=\(String(describing: element?.frame)); \(explanation)"
            print("Accessibility audit: \(issue.compactDescription); identifier=\(element?.identifier ?? "none"); \(geometry)")
            let details = XCTAttachment(string: issue.detailedDescription + "\n" + geometry + "\n"
                + (element?.debugDescription ?? "No associated element"))
            details.name = deferred ? "Viewport contrast obligation"
                : (legacyOffWindow ? "Off-window contrast audit false positive" : "Accessibility audit issue")
            details.lifetime = .keepAlways
            self.add(details)
            if !deferred && !legacyOffWindow { rejected = true }
            // Every metadata ID, including unknown IDs and the group being
            // proven, remains ledger-only and cannot reach legacy handling.
            return deferred || legacyOffWindow
        }
        let after = try settingsAuditSnapshot(app, subjectWindow: subjectWindow)
        guard !rejected, after == before else {
            throw ViewportProofFailure.invalid("Full audit failed or geometry/content changed afterward")
        }
        guard Self.groupIsFullyVisible(provingGroup, in: after) else {
            throw ViewportProofFailure.invalid("Positive audit group stopped being wholly visible")
        }
        pending.provenGroups.insert(provingGroup)
        for id in Self.metadataChildIDs(groupID: provingGroup) {
            guard let child = after.metadata[id] else { throw ViewportProofFailure.invalid("Missing positive child") }
            pending.coverage[id] = .init(identity: child.identity, fullAuditNumber: pending.auditNumber)
        }
        guard pending.provenGroups.count <= 8, pending.coverage.count <= 56 else {
            throw ViewportProofFailure.invalid("Positive audit proof capacity exceeded")
        }
        ledger = pending
    }

    @MainActor
    private func scrollMetadataGroup(_ groupID: String, app: XCUIApplication,
                                     subjectWindow: XCUIElement, initial: SettingsAuditSnapshot,
                                     ledger: inout ViewportProofLedger,
                                     restoreFrame: CGRect? = nil) throws {
        for _ in 0..<16 {
            let before = try settingsAuditSnapshot(app, subjectWindow: subjectWindow)
            try requireSameSettingsContent(before, initial: initial, ledger: &ledger)
            let moveUp: Bool
            var magnitude: CGFloat = 140
            if let group = before.metadata[Self.metadataChildIDs(groupID: groupID)[0]] {
                if let restoreFrame {
                    if group.groupFrame == restoreFrame { return }
                } else if Self.groupIsFullyVisible(groupID, in: before) { return }
                guard group.groupFrame.height <= before.viewport.frame.height,
                      group.groupFrame.minX >= before.viewport.frame.minX,
                      group.groupFrame.maxX <= before.viewport.frame.maxX else {
                    throw ViewportProofFailure.invalid("Metadata group cannot fit the viewport")
                }
                moveUp = restoreFrame.map { group.groupFrame.minY < $0.minY }
                    ?? (group.groupFrame.minY < before.viewport.frame.minY)
                if let restoreFrame {
                    guard group.groupFrame.size == restoreFrame.size,
                          group.groupFrame.minX == restoreFrame.minX else {
                        throw ViewportProofFailure.invalid("Scrolling cannot restore changed group dimensions")
                    }
                    magnitude = min(140, abs(group.groupFrame.minY - restoreFrame.minY))
                } else {
                    // Do not jump over the interval in which a tall group fits.
                    let slack = before.viewport.frame.height - group.groupFrame.height
                    let margin = min(4, slack / 2)
                    let gap = moveUp ? before.viewport.frame.minY - group.groupFrame.minY
                        : group.groupFrame.maxY - before.viewport.frame.maxY
                    magnitude = min(140, max(1, gap + margin))
                }
            } else {
                // Virtualization may remove an earlier captured target. Navigate
                // by the fixed feature order and actual currently visible groups;
                // no missing child receives a fabricated frame or proof.
                guard let targetIndex = Self.metadataFeatures.firstIndex(where: {
                    "settings.metadata.feature." + $0 == groupID
                }), let reference = before.metadata.values.filter({
                    $0.groupFrame.intersects(before.viewport.frame)
                }).min(by: {
                    abs($0.groupFrame.midY - before.viewport.frame.midY)
                        < abs($1.groupFrame.midY - before.viewport.frame.midY)
                }), let referenceIndex = Self.metadataFeatures.firstIndex(where: {
                    "settings.metadata.feature." + $0 == reference.identity.groupID
                }), targetIndex != referenceIndex else {
                    throw ViewportProofFailure.invalid("Missing target and no actual visible navigation reference")
                }
                moveUp = targetIndex < referenceIndex
            }
            let viewport = try uniqueElement(subjectWindow.scrollViews.matching(identifier: "settings.content"),
                description: "settings.content viewport")
            viewport.scroll(byDeltaX: 0, deltaY: moveUp ? magnitude : -magnitude)
            // Re-resolve every unique ID; an old wrapper cannot prove scrolling.
            let after = try settingsAuditSnapshot(app, subjectWindow: subjectWindow)
            try requireSameSettingsContent(after, initial: initial, ledger: &ledger)
            guard after.metadata != before.metadata else { throw ViewportProofFailure.invalid("Scroll made no progress") }
        }
        let final = try settingsAuditSnapshot(app, subjectWindow: subjectWindow)
        try requireSameSettingsContent(final, initial: initial, ledger: &ledger)
        let matches = restoreFrame.map { final.metadata[Self.metadataChildIDs(groupID: groupID)[0]]?.groupFrame == $0 }
            ?? Self.groupIsFullyVisible(groupID, in: final)
        guard matches else { throw ViewportProofFailure.invalid("Metadata scroll attempt limit exceeded") }
    }

    @MainActor
    private func auditSettingsWithViewportProof(_ app: XCUIApplication, subjectWindow: XCUIElement) throws {
        let initial = try settingsAuditSnapshot(app, subjectWindow: subjectWindow)
        let headroom = "settings.metadata.feature.headroom"
        guard let headroomFrame = initial.metadata[headroom + ".primary.0"]?.groupFrame,
              Self.groupIsFullyVisible(headroom, in: initial) else {
            throw ViewportProofFailure.invalid("Initial headroom group is not wholly visible")
        }
        var ledger = ViewportProofLedger()
        try ledger.observe(initial)
        try runSettingsFullAudit(app, subjectWindow: subjectWindow, initial: initial,
            provingGroup: headroom, ledger: &ledger)
        for _ in 0..<8 {
            guard let obligation = ledger.unresolved.first else { break }
            guard !ledger.provenGroups.contains(obligation.groupID) else {
                throw ViewportProofFailure.invalid("Changed or unresolved previously proven metadata")
            }
            try scrollMetadataGroup(obligation.groupID, app: app, subjectWindow: subjectWindow,
                initial: initial, ledger: &ledger)
            try runSettingsFullAudit(app, subjectWindow: subjectWindow, initial: initial,
                provingGroup: obligation.groupID, ledger: &ledger)
        }
        guard ledger.unresolved.isEmpty else { throw ViewportProofFailure.invalid("Unresolved viewport contrast obligations") }
        try scrollMetadataGroup(headroom, app: app, subjectWindow: subjectWindow,
            initial: initial, ledger: &ledger, restoreFrame: headroomFrame)
        let restored = try settingsAuditSnapshot(app, subjectWindow: subjectWindow)
        try requireSameSettingsContent(restored, initial: initial, ledger: &ledger)
        guard Self.metadataChildIDs(groupID: headroom).allSatisfy({ restored.metadata[$0] == initial.metadata[$0] }) else {
            throw ViewportProofFailure.invalid("Initial headroom scroll geometry was not restored")
        }
        let proof = XCTAttachment(string: "Full audits completed: \(ledger.auditNumber); "
            + "positive groups: \(ledger.provenGroups.sorted()); exact deferred IDs: \(ledger.obligations.keys.sorted()); "
            + "unresolved: \(ledger.unresolved.count). Each covered child passed a full audit while its whole group was visible; "
            + "this is not an independent per-element pixel contrast measurement.")
        proof.name = "Settings viewport positive-audit ledger"
        proof.lifetime = .keepAlways
        add(proof)
    }

    @MainActor
    private func audit(_ app: XCUIApplication, subjectWindow: XCUIElement) throws {
        let capturedWindowFrame = subjectWindow.frame
        let viewport = subjectWindow.scrollViews.firstMatch
        let capturedViewportFrame = viewport.exists ? viewport.frame : nil
        let capturedAppWindowFrames = app.windows.allElementsBoundByIndex
            .filter(\.exists)
            .map(\.frame)
        try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription]) { issue in
            let element = issue.element
            let elementFrame = element?.frame
            let liveWindowFrame = subjectWindow.frame
            let liveAppWindowFrames = app.windows.allElementsBoundByIndex
                .filter(\.exists)
                .map(\.frame)
            let windowFramesAreStable = liveWindowFrame == capturedWindowFrame
                && liveAppWindowFrames == capturedAppWindowFrames
            let isOffWindowContrast = windowFramesAreStable
                && Self.shouldIgnoreAuditIssue(
                    auditType: issue.auditType,
                    elementFrame: elementFrame,
                    subjectWindow: capturedWindowFrame,
                    appWindows: capturedAppWindowFrames)
            let geometry = "auditType=\(issue.auditType.rawValue); "
                + "capturedSubjectWindow=\(capturedWindowFrame); "
                + "liveSubjectWindow=\(liveWindowFrame); "
                + "capturedAppWindows=\(capturedAppWindowFrames); "
                + "liveAppWindows=\(liveAppWindowFrames); "
                + "elementFrame=\(String(describing: elementFrame)); "
                + "capturedViewport=\(String(describing: capturedViewportFrame)); "
                + "liveViewport=\(String(describing: viewport.exists ? viewport.frame : nil))"
            print("Accessibility audit: \(issue.compactDescription); "
                + "identifier=\(element?.identifier ?? "none"); "
                + "label=\(element?.label ?? "none"); \(geometry)")
            if isOffWindowContrast {
                print("Ignoring off-window contrast audit false positive; \(geometry)")
            }
            let details = XCTAttachment(string: issue.detailedDescription + "\n" + geometry + "\n"
                + (element?.debugDescription ?? "No associated element"))
            details.name = isOffWindowContrast
                ? "Off-window contrast audit false positive"
                : "Accessibility audit issue"
            details.lifetime = .keepAlways
            self.add(details)
            if !windowFramesAreStable {
                XCTFail("App window geometry changed during accessibility audit; \(geometry)")
                return false
            }
            return isOffWindowContrast
        }
        XCTAssertEqual(subjectWindow.frame, capturedWindowFrame,
            "Subject window moved during accessibility audit")
        XCTAssertEqual(
            app.windows.allElementsBoundByIndex.filter(\.exists).map(\.frame),
            capturedAppWindowFrames,
            "App window geometry changed during accessibility audit")
    }

    private func assertAuditIssueClassificationBoundaries() {
        let window = CGRect(x: 100, y: 100, width: 400, height: 500)
        let below = CGRect(x: 100, y: 601, width: 100, height: 20)
        XCTAssertTrue(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: below,
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .sufficientElementDescription,
            elementFrame: below,
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: [.contrast, .sufficientElementDescription],
            elementFrame: below,
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: XCUIAccessibilityAuditType(rawValue: UInt64(1) << 63),
            elementFrame: below,
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: nil,
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: below,
            subjectWindow: .zero,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: below,
            subjectWindow: window,
            appWindows: []))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: below,
            subjectWindow: window,
            appWindows: [window, .zero]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: CGRect(x: 100, y: 601, width: -100, height: 20),
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: .zero,
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 20),
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: CGRect(x: 120, y: 120, width: 100, height: 20),
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: CGRect(x: 100, y: 599, width: 100, height: 20),
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: CGRect(x: 100, y: 600, width: 100, height: 20),
            subjectWindow: window,
            appWindows: [window]))
        let otherWindow = CGRect(x: 80, y: 580, width: 440, height: 200)
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: below,
            subjectWindow: window,
            appWindows: [window, otherWindow]))

        let viewport = CGRect(x: 120, y: 160, width: 360, height: 300)
        let group = CGRect(x: 120, y: 400, width: 360, height: 180)
        let clipped = CGRect(x: 130, y: 461, width: 100, height: 16)
        XCTAssertTrue(Self.isViewportClippedContrast(auditType: .contrast,
            child: clipped, group: group, window: window, viewport: viewport))
        XCTAssertTrue(Self.isViewportClippedContrast(auditType: .contrast,
            child: CGRect(x: 130, y: 140, width: 100, height: 16),
            group: CGRect(x: 120, y: 120, width: 360, height: 80), window: window, viewport: viewport))
        for kind in [XCUIAccessibilityAuditType.sufficientElementDescription,
                     [.contrast, .sufficientElementDescription],
                     XCUIAccessibilityAuditType(rawValue: UInt64(1) << 63)] {
            XCTAssertFalse(Self.isViewportClippedContrast(auditType: kind,
                child: clipped, group: group, window: window, viewport: viewport))
        }
        for invalidOrIntersecting in [CGRect.zero,
            CGRect(x: CGFloat.nan, y: 461, width: 100, height: 16),
            CGRect(x: 130, y: 461, width: -100, height: 16),
            CGRect(x: 130, y: 459, width: 100, height: 16),
            CGRect(x: 130, y: 460, width: 100, height: 16),
            CGRect(x: 130, y: 144, width: 100, height: 16),
            CGRect(x: 119, y: 461, width: 100, height: 16),
            CGRect(x: 450, y: 461, width: 100, height: 16)] {
            XCTAssertFalse(Self.isViewportClippedContrast(auditType: .contrast,
                child: invalidOrIntersecting, group: group, window: window, viewport: viewport))
        }
        XCTAssertFalse(Self.isViewportClippedContrast(auditType: .contrast,
            child: clipped, group: .zero, window: window, viewport: viewport))
        XCTAssertFalse(Self.isViewportClippedContrast(auditType: .contrast,
            child: clipped, group: CGRect(x: 120, y: 400, width: 360, height: 60),
            window: window, viewport: viewport))
        XCTAssertFalse(Self.isViewportClippedContrast(auditType: .contrast,
            child: clipped, group: group, window: window,
            viewport: CGRect(x: 90, y: 160, width: 400, height: 300)))
    }

    private static func shouldIgnoreAuditIssue(
        auditType: XCUIAccessibilityAuditType,
        elementFrame: CGRect?,
        subjectWindow: CGRect,
        appWindows: [CGRect]
    ) -> Bool {
        guard auditType == .contrast,
              let elementFrame,
              isValidAuditFrame(elementFrame),
              isValidAuditFrame(subjectWindow),
              !appWindows.isEmpty,
              appWindows.allSatisfy(isValidAuditFrame),
              appWindows.contains(subjectWindow) else { return false }
        return appWindows.allSatisfy { window in
            elementFrame.maxX < window.minX
                || elementFrame.minX > window.maxX
                || elementFrame.maxY < window.minY
                || elementFrame.minY > window.maxY
        }
    }

    private static func isValidAuditFrame(_ frame: CGRect) -> Bool {
        frame.size.width > 0 && frame.size.height > 0
            && [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
                frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
    }

    @MainActor
    private func capture(_ element: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func cleanup(_ app: XCUIApplication) {
        let control = app.windows["Tidy Production Runtime Verification"]
        let homePath = control.staticTexts["runtime.synthetic.home"].value as? String
        guard let homePath else {
            app.terminate()
            XCTFail("Runtime appearance host did not attest its fixture home")
            return
        }
        let root = URL(fileURLWithPath: homePath).deletingLastPathComponent()
        guard root.lastPathComponent.hasPrefix("tidy-production-runtime-"),
              root.path.hasPrefix("/private/var/folders/")
                || root.path.hasPrefix("/private/tmp/"),
              !root.path.hasPrefix(NSHomeDirectory() + "/") else {
            app.terminate()
            XCTFail("Runtime appearance host supplied an unsafe fixture root")
            return
        }
        control.click()
        control.buttons["runtime.fixture.cleanupAndQuit"].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !FileManager.default.fileExists(atPath: root.path)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
    }
}
