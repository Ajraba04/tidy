# Settings reference

Generated from the tested Tidy settings registry. MiB and GiB values use powers of 1024. An unavailable row remains part of the durable schema but its control is disabled until the named production consumer is accepted.

| Stable ID | Default | Allowed values | Resolution / effect | Layers | Production consumer |
|---|---|---|---|---|---|
|feature.headroom|true|boolean|restriction / invalidate|global, profile|Available: SystemMonitor and Headroom presentation|
|feature.buildPrep|true|boolean|restriction / invalidate|global, profile|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|feature.projects|true|boolean|restriction / invalidate|global, profile|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|feature.rescue|true|boolean|restriction / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|feature.ecosystems|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|feature.budgets|true|boolean|restriction / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|feature.history|true|boolean|restriction / invalidate|global, profile|Available: Bounded optional completed-run history|
|feature.maintenance|false|boolean|restriction / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|ecosystem.apple.inventory|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.apple.manualActions|false|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.android.inventory|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.android.manualActions|false|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.node.inventory|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.node.manualActions|false|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.languages.inventory|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.languages.manualActions|false|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.homebrew.inventory|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.homebrew.manualActions|false|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.docker.inventory|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.docker.manualActions|false|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.ides.inventory|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.ides.manualActions|false|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.models.inventory|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.models.manualActions|false|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.git.inventory|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.git.manualActions|false|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.data.inventory|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|ecosystem.data.manualActions|false|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.puccinialin.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.swiftpm-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.pip-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.node-gyp.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.deno-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.playwright-mcp-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.homebrew-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.xcode-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.itmstransporter-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.typescript-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.electron-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.electron-builder-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.yarn-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.go-build-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.jetbrains-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.swiftpm-clones.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.helpd.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.perplexity.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.claude-desktop-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.claude-desktop-code-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.claude-desktop-gpu-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.npm-cacache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.uv-dir.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.puppeteer.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.bun-install-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.mcp-repos.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.claude.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.core-simulator.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.google.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.diagnostic-reports.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.creative-cloud.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.ngl.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.content-delivery.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.npm-cache-clean.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.brew-cleanup.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.brew-autoremove.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.pod-cache-clean.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.uv-cache-prune.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.pnpm-store-prune.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.deno-clean.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.pip3-cache-purge.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.gradle.build-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.gradle.daemon-logs.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.system.quicklook-thumbnails.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.system.cloudkit-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.system.qlmanage-reset.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.chrome.http-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.chrome.profile-caches.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.chrome.cookies.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.webkit-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.legacy-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.webkit-global.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.favicon-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.touch-icons.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.derived-data.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.documentation-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.ios-device-support.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.watchos-device-support.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.products.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.coding-assistant.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.core-simulator-caches.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.core-simulator-temp.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.playground-devices.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.xctest-devices.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.delete-unavailable.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.xcode.archives.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.simulator.erase-all.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.simulator.delete-approved.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.git.housekeeping.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.git.reflog-expire-all.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.trash.empty.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.extras.build-outputs.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.extras.stale-node-modules.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.extras.old-transcripts.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.avds.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.system-images.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.ndk.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.sdk-temp.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.gradle-caches-full.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.gradle-wrapper.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.npm-npx.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.maven-repository.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.pub-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.dart-server.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.bubblewrap.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.cocoapods-repos.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.go-clean-modcache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.flutter.tool-state.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.flutter.sdk-cache.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.system.apfs-snapshots.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.system.claude-vm-bundles.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.system.claude-code-vm.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.memory.purge-inactive.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.memory.quit-approved-apps.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.memory.restart-for-swap.enabled|true|boolean|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|scope.projectRoots|[]|bounded local identity list|authority / consent|machine-local authority only|Unavailable: A separately accepted machine-local authority workflow is not implemented.|
|scope.externalVolumes|[]|bounded local identity list|authority / consent|machine-local authority only|Unavailable: A separately accepted machine-local authority workflow is not implemented.|
|scope.currentProject|null / automatic|project identity or null|preference / invalidate|global, profile, project, run|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|scan.preset|eco|eco, balanced, custom|preference / invalidate|global, profile|Available: Explicit scan scope and scheduler policy|
|scan.requestedWorkers|1|integer 1...4|preference / invalidate|global, profile|Available: Explicit scan scope and scheduler policy|
|scan.readOnlyProcesses|1|integer 1...2|preference / invalidate|global, profile|Available: Explicit scan scope and scheduler policy|
|scan.defaultScope|quick|quick, selectedProjects|preference / invalidate|global, profile|Available: Explicit scan scope and scheduler policy|
|scan.sliceSeconds|300|integer 30...1800|preference / invalidate|global, profile|Available: Explicit scan scope and scheduler policy|
|scan.uiBatchesPerSecond|4|integer 1...4|preference / none|global, profile|Available: Explicit scan scope and scheduler policy|
|scan.onLowPower|pauseDiscretionary|pauseAll, pauseDiscretionary|restriction / invalidate|global, profile|Available: Explicit scan scope and scheduler policy|
|scan.onSeriousThermal|pauseDiscretionary|pauseAll, pauseDiscretionary|restriction / invalidate|global, profile|Available: Explicit scan scope and scheduler policy|
|scan.resumeAfterCriticalSeconds|120|integer 120...900|preference / invalidate|global, profile|Available: Explicit scan scope and scheduler policy|
|scan.cacheEnabled|true|boolean|preference / invalidate|global, profile|Unavailable: R07 incremental-index application integration is not implemented.|
|scan.cacheMiB|64|integer 8...128|preference / invalidate|global, profile|Unavailable: R07 incremental-index application integration is not implemented.|
|scan.cacheExpiryHours|24|integer 1...48|preference / invalidate|global, profile|Unavailable: R07 incremental-index application integration is not implemented.|
|monitor.backgroundEnabled|false|boolean|authority / consent|machine-local authority only|Unavailable: Local background-monitor consent is not implemented.|
|monitor.visibleIntervalSeconds|5|integer 2...60|preference / none|global, profile|Available: SystemMonitor sampling and bounded signal history|
|monitor.hiddenIntervalSeconds|60|integer 60...900|preference / none|global, profile|Available: SystemMonitor sampling and bounded signal history|
|monitor.rawHistoryEnabled|false|boolean|preference / none|global, profile|Available: SystemMonitor sampling and bounded signal history|
|monitor.rawHistoryHours|24|integer 1...24|preference / none|global, profile|Available: SystemMonitor sampling and bounded signal history|
|monitor.suppressHiddenSampling|false|boolean|restriction / none|global, profile|Available: SystemMonitor sampling and bounded signal history|
|browsers.keepCookieDomains|[]|canonical domain list|restriction / invalidate|global, profile|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|scope.excludedRoots|[]|canonical absolute-path exclusions|restriction / invalidate|global, profile, project, run|Available: Explicit scan scope and scheduler policy|
|scope.pinnedProjects|[]|project identity set|restriction / invalidate|global, profile, project, run|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|cleanup.inactiveDays|60|integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|cleanup.transcriptDays|45|integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|cleanup.recentProtectionDays|7|integer 1...90|preference / invalidate|global, profile, project, run|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|cleanup.warmProjectCount|5|integer 0...50|preference / invalidate|global, profile, project, run|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|cleanup.minimumCandidateMiB|100|integer 1...102400|preference / invalidate|global, profile, project, run|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|cleanup.minimumItemMiB|1|integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|cleanup.retainRecentArtifacts|2|integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|cleanup.costCeiling|low|low, medium, high|preference / invalidate|global, profile, project, run|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|cleanup.requestedBatchGiB|10|integer 1...100|preference / invalidate|global, profile, project, run|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|cleanup.requestedBatchItems|20|integer 1...100|preference / invalidate|global, profile, project, run|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|cleanup.hardBatchGiB|null / automatic|null or integer 1...100|restriction / invalidate|global, profile, project, run|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|cleanup.hardBatchItems|null / automatic|null or integer 1...100|restriction / invalidate|global, profile, project, run|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|cleanup.manualInactiveAcknowledgementMinutes|10|integer 1...30|preference / invalidate|global, profile, project, run|Unavailable: R09 project inventory, ranking, and Build Prep are not implemented.|
|headroom.targetGiB|null / automatic|automatic or 1...1024 GiB within volume bounds|preference / invalidate|global, profile, project, run|Available: Measured-volume Headroom target resolution|
|headroom.warningGiB|null / automatic|automatic or fixed below clear|preference / invalidate|global, profile, project, run|Available: Measured-volume Headroom target resolution|
|headroom.clearGiB|null / automatic|automatic or fixed at or below capacity|preference / invalidate|global, profile, project, run|Available: Measured-volume Headroom target resolution|
|item.safe.cache.puccinialin.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.puccinialin.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.puccinialin.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.swiftpm-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.swiftpm-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.swiftpm-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.pip-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.pip-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.pip-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.node-gyp.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.node-gyp.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.node-gyp.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.deno-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.deno-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.deno-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.playwright-mcp-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.playwright-mcp-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.playwright-mcp-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.homebrew-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.homebrew-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.homebrew-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.xcode-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.xcode-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.xcode-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.itmstransporter-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.itmstransporter-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.itmstransporter-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.typescript-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.typescript-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.typescript-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.electron-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.electron-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.electron-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.electron-builder-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.electron-builder-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.electron-builder-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.yarn-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.yarn-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.yarn-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.go-build-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.go-build-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.go-build-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.jetbrains-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.jetbrains-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.jetbrains-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.swiftpm-clones.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.swiftpm-clones.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.swiftpm-clones.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.helpd.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.helpd.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.helpd.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.perplexity.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.perplexity.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.perplexity.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.claude-desktop-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.claude-desktop-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.claude-desktop-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.claude-desktop-code-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.claude-desktop-code-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.claude-desktop-code-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.claude-desktop-gpu-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.claude-desktop-gpu-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.claude-desktop-gpu-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.npm-cacache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.npm-cacache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.npm-cacache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.uv-dir.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.uv-dir.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.uv-dir.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.puppeteer.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.puppeteer.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.puppeteer.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.bun-install-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.bun-install-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.bun-install-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.mcp-repos.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.mcp-repos.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.cache.mcp-repos.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.claude.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.claude.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.claude.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.core-simulator.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.core-simulator.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.core-simulator.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.google.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.google.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.google.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.diagnostic-reports.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.diagnostic-reports.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.diagnostic-reports.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.creative-cloud.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.creative-cloud.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.creative-cloud.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.ngl.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.ngl.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.ngl.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.content-delivery.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.content-delivery.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.logs.content-delivery.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.npm-cache-clean.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.npm-cache-clean.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.npm-cache-clean.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.brew-cleanup.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.brew-cleanup.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.brew-cleanup.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.brew-autoremove.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.brew-autoremove.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.brew-autoremove.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.pod-cache-clean.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.pod-cache-clean.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.pod-cache-clean.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.uv-cache-prune.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.uv-cache-prune.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.uv-cache-prune.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.pnpm-store-prune.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.pnpm-store-prune.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.pnpm-store-prune.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.deno-clean.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.deno-clean.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.deno-clean.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.pip3-cache-purge.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.pip3-cache-purge.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.tool.pip3-cache-purge.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.gradle.build-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.gradle.build-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.gradle.build-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.gradle.daemon-logs.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.gradle.daemon-logs.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.gradle.daemon-logs.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.system.quicklook-thumbnails.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.system.quicklook-thumbnails.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.system.quicklook-thumbnails.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.system.cloudkit-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.system.cloudkit-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.system.cloudkit-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.system.qlmanage-reset.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.system.qlmanage-reset.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.system.qlmanage-reset.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.chrome.http-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.chrome.http-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.chrome.http-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.chrome.profile-caches.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.chrome.profile-caches.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.chrome.profile-caches.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.chrome.cookies.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.chrome.cookies.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.chrome.cookies.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.webkit-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.webkit-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.webkit-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.legacy-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.legacy-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.legacy-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.webkit-global.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.webkit-global.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.webkit-global.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.favicon-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.favicon-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.favicon-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.touch-icons.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.touch-icons.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.safari.touch-icons.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.derived-data.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.derived-data.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.derived-data.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.documentation-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.documentation-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.documentation-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.ios-device-support.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.ios-device-support.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.ios-device-support.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.watchos-device-support.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.watchos-device-support.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.watchos-device-support.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.products.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.products.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.products.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.coding-assistant.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.coding-assistant.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.xcode.coding-assistant.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.core-simulator-caches.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.core-simulator-caches.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.core-simulator-caches.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.core-simulator-temp.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.core-simulator-temp.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.core-simulator-temp.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.playground-devices.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.playground-devices.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.playground-devices.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.xctest-devices.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.xctest-devices.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.xctest-devices.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.delete-unavailable.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.delete-unavailable.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.simulator.delete-unavailable.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.xcode.archives.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.xcode.archives.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.xcode.archives.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.simulator.erase-all.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.simulator.erase-all.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.simulator.erase-all.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.simulator.delete-approved.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.simulator.delete-approved.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.simulator.delete-approved.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.git.housekeeping.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.git.housekeeping.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.git.housekeeping.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.git.reflog-expire-all.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.git.reflog-expire-all.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.git.reflog-expire-all.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.trash.empty.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.trash.empty.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.trash.empty.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.extras.build-outputs.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.extras.build-outputs.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.extras.build-outputs.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.extras.stale-node-modules.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.extras.stale-node-modules.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.extras.stale-node-modules.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.extras.old-transcripts.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.extras.old-transcripts.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.normal.extras.old-transcripts.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.avds.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.avds.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.avds.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.system-images.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.system-images.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.system-images.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.ndk.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.ndk.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.ndk.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.sdk-temp.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.sdk-temp.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.android.sdk-temp.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.gradle-caches-full.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.gradle-caches-full.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.gradle-caches-full.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.gradle-wrapper.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.gradle-wrapper.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.gradle-wrapper.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.npm-npx.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.npm-npx.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.npm-npx.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.maven-repository.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.maven-repository.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.maven-repository.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.pub-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.pub-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.pub-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.dart-server.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.dart-server.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.dart-server.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.bubblewrap.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.bubblewrap.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.bubblewrap.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.cocoapods-repos.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.cocoapods-repos.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.cocoapods-repos.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.go-clean-modcache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.go-clean-modcache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.deps.go-clean-modcache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.flutter.tool-state.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.flutter.tool-state.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.safe.flutter.tool-state.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.flutter.sdk-cache.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.flutter.sdk-cache.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.flutter.sdk-cache.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.system.apfs-snapshots.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.system.apfs-snapshots.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.system.apfs-snapshots.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.system.claude-vm-bundles.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.system.claude-vm-bundles.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.system.claude-vm-bundles.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.system.claude-code-vm.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.system.claude-code-vm.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.system.claude-code-vm.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.memory.purge-inactive.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.memory.purge-inactive.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.memory.purge-inactive.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.memory.quit-approved-apps.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.memory.quit-approved-apps.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.memory.quit-approved-apps.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.memory.restart-for-swap.inactiveDays|null / automatic|null or integer 7...365|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.memory.restart-for-swap.minimumItemMiB|null / automatic|null or integer 0...102400|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|item.deep.memory.restart-for-swap.retainRecentArtifacts|null / automatic|null or integer 0...100|preference / invalidate|global, profile, project, run|Unavailable: R10 ecosystem adapter behavior is not implemented.|
|headroom.volumeOverrides.<volumeID>|null / automatic|inherit, automatic, or fixed GiB fields|preference / invalidate|global, profile, project, run|Available: Measured-volume Headroom target resolution|
|simulators.approvedDeletionUDIDs|[]|bounded local identity list|authority / consent|machine-local authority only|Unavailable: A separately accepted machine-local authority workflow is not implemented.|
|tools.approvedExecutables|[]|bounded local identity list|authority / consent|machine-local authority only|Unavailable: A separately accepted machine-local authority workflow is not implemented.|
|docker.approvedEndpoints|[]|bounded local identity list|authority / consent|machine-local authority only|Unavailable: A separately accepted machine-local authority workflow is not implemented.|
|rescue.approvedApplications|[]|bounded local identity list|authority / consent|machine-local authority only|Unavailable: A separately accepted machine-local authority workflow is not implemented.|
|rescue.showAdvancedMemoryActions|false|boolean|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|rescue.quitTimeoutSeconds|15|integer 5...60|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.apple-derived-data.enabled|false|boolean|restriction / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.apple-derived-data.highGiB|15|null or 1...1024 GiB within volume bounds|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.apple-derived-data.lowGiB|null / automatic|null or value below high|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.apple-simulators.enabled|false|boolean|restriction / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.apple-simulators.highGiB|25|null or 1...1024 GiB within volume bounds|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.apple-simulators.lowGiB|null / automatic|null or value below high|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.android.enabled|false|boolean|restriction / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.android.highGiB|null / automatic|null or 1...1024 GiB within volume bounds|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.android.lowGiB|null / automatic|null or value below high|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.docker.enabled|false|boolean|restriction / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.docker.highGiB|30|null or 1...1024 GiB within volume bounds|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.docker.lowGiB|null / automatic|null or value below high|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.package-caches.enabled|false|boolean|restriction / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.package-caches.highGiB|10|null or 1...1024 GiB within volume bounds|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.package-caches.lowGiB|null / automatic|null or value below high|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.models.enabled|false|boolean|restriction / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.models.highGiB|50|null or 1...1024 GiB within volume bounds|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.models.lowGiB|null / automatic|null or value below high|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.ides.enabled|false|boolean|restriction / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.ides.highGiB|null / automatic|null or 1...1024 GiB within volume bounds|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.ides.lowGiB|null / automatic|null or value below high|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.git.enabled|false|boolean|restriction / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.git.highGiB|null / automatic|null or 1...1024 GiB within volume bounds|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.git.lowGiB|null / automatic|null or value below high|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.data.enabled|false|boolean|restriction / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.data.highGiB|null / automatic|null or 1...1024 GiB within volume bounds|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.data.lowGiB|null / automatic|null or value below high|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.other.enabled|false|boolean|restriction / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.other.highGiB|null / automatic|null or 1...1024 GiB within volume bounds|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|budget.other.lowGiB|null / automatic|null or value below high|preference / invalidate|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|notifications.enabled|false|boolean|authority / consent|machine-local authority only|Unavailable: A separately accepted machine-local authority workflow is not implemented.|
|notifications.pressureSustainSeconds|60|integer 30...600|preference / none|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|notifications.recoverySeconds|120|integer 60...900|preference / none|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|notifications.cooldownMinutes|60|integer 15...1440|preference / none|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|notifications.quietHoursEnabled|false|boolean|preference / none|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|notifications.quietStart|22:00|HH:mm|preference / none|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|notifications.quietEnd|08:00|HH:mm distinct from quiet start|preference / none|global, profile|Unavailable: R11 notifications and assistance are not implemented.|
|maintenance.mode|off|off, notifyOnly, authorizedCaches|authority / consent|machine-local authority only|Unavailable: A separately accepted machine-local authority workflow is not implemented.|
|maintenance.maxGiB|1|integer 1...5|authority / consent|machine-local authority only|Unavailable: A separately accepted machine-local authority workflow is not implemented.|
|maintenance.maxItems|5|integer 1...20|authority / consent|machine-local authority only|Unavailable: A separately accepted machine-local authority workflow is not implemented.|
|maintenance.deadlineSeconds|60|integer 30...120|authority / consent|machine-local authority only|Unavailable: A separately accepted machine-local authority workflow is not implemented.|
|maintenance.minimumAgeDays|30|integer 30...365|authority / consent|machine-local authority only|Unavailable: A separately accepted machine-local authority workflow is not implemented.|
|maintenance.minimumIntervalHours|24|integer 24...168|authority / consent|machine-local authority only|Unavailable: A separately accepted machine-local authority workflow is not implemented.|
|app.launchAtLogin|false|boolean|authority / consent|machine-local authority only|Unavailable: A separately accepted machine-local authority workflow is not implemented.|
|history.enabled|true|boolean|preference / none|global, profile|Available: Bounded optional completed-run history|
|history.retentionDays|30|integer 1...90|preference / none|global, profile|Available: Bounded optional completed-run history|
|history.maxMiB|10|integer 1...50|preference / none|global, profile|Available: Bounded optional completed-run history|
|ui.density|compact|compact, detailed|preference / none|global, profile|Unavailable: This presentation preference has no application consumer.|
|ui.units|binary|binary, decimal|preference / none|global, profile|Available: Headroom and menu bar presentation|
|ui.cards|[disk, memoryPressure, swap, thermal, power]|ordered subset of disk, memoryPressure, swap, thermal, power|preference / none|global, profile|Available: Headroom and menu bar presentation|
|ui.ecosystemOrder|[apple, android, node, languages, homebrew, docker, ides, models, git, data]|permutation of ecosystem IDs|preference / none|global, profile|Unavailable: This presentation preference has no application consumer.|
|ui.showBadges|true|boolean|preference / none|global, profile|Unavailable: This presentation preference has no application consumer.|
|ui.advancedSettings|false|boolean|preference / none|global, profile|Available: Settings search and advanced-row visibility|
|export.redactDiagnostics|true|boolean|preference / none|global, profile|Unavailable: Diagnostic export is not implemented.|
