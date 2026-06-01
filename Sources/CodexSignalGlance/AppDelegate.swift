import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let codexBundleIdentifier = "com.openai.codex"
    private let snapshotService = QuotaSnapshotService()
    private let activityService = CodexActivityService()
    private let stateStore = WidgetStateStore()
    private let refreshQueue = DispatchQueue(label: "com.wendy.codex-signal-glance.refresh")

    private lazy var windowController = WidgetWindowController(stateStore: stateStore)

    private var appObservers: [NSObjectProtocol] = []
    private var refreshTimer: Timer?
    private var codexRunning = false
    private var fastRefreshUntil: Date?
    private var lastSnapshot: QuotaSnapshot?
    private var lastActivity: CodexActivitySnapshot = .idle
    private var refreshInFlight = false
    private var language: WidgetLanguage = .systemDefault

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        language = stateStore.load().language ?? .systemDefault
        windowController.onRequestRefresh = { [weak self] in
            self?.refreshState(reason: "manual-refresh", forceSnapshotReload: true)
        }
        windowController.currentLanguage = { [weak self] in
            self?.language ?? .systemDefault
        }
        windowController.onToggleLanguage = { [weak self] in
            self?.toggleLanguage() ?? .systemDefault
        }
        startMonitoringCodex()
        refreshState(reason: "launch")
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        snapshotService.stop()
        let center = NSWorkspace.shared.notificationCenter
        appObservers.forEach(center.removeObserver(_:))
    }

    private func startMonitoringCodex() {
        let center = NSWorkspace.shared.notificationCenter
        let codexBundleIdentifier = codexBundleIdentifier

        let launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier == codexBundleIdentifier
            else {
                return
            }

            Task { @MainActor in
                self?.handleCodexLifecycleEvent(launched: true)
            }
        }

        let terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier == codexBundleIdentifier
            else {
                return
            }

            Task { @MainActor in
                self?.handleCodexLifecycleEvent(launched: false)
            }
        }

        appObservers = [launchObserver, terminateObserver]
    }

    private func handleCodexLifecycleEvent(launched: Bool) {
        if launched {
            fastRefreshUntil = Date().addingTimeInterval(120)
        }
        refreshState(reason: launched ? "codex-launch" : "codex-exit")
    }

    private func scheduleRefreshTimer(cadence: RefreshCadence) {
        if refreshTimer?.timeInterval == cadence.interval {
            return
        }

        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: cadence.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshState(reason: "refresh")
            }
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    private func refreshState(reason: String, forceSnapshotReload: Bool = false) {
        let running = isCodexRunning()

        if running != codexRunning {
            codexRunning = running
            if running {
                fastRefreshUntil = Date().addingTimeInterval(120)
            }
        }

        if !running {
            windowController.hide()
            snapshotService.stop()
            lastSnapshot = nil
            lastActivity = .idle
            scheduleRefreshTimer(cadence: .hidden)
            return
        }

        windowController.show(snapshot: lastSnapshot, activity: lastActivity)
        refreshSnapshot(forceReload: forceSnapshotReload)
        scheduleRefreshTimer(cadence: currentCadence())

        if reason == "refresh", let fastRefreshUntil, fastRefreshUntil < Date() {
            scheduleRefreshTimer(cadence: .normal)
        }
    }

    private func currentCadence() -> RefreshCadence {
        if let fastRefreshUntil, fastRefreshUntil > Date() {
            return .fast
        }
        return .normal
    }

    private func isCodexRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: codexBundleIdentifier).isEmpty
    }

    private func toggleLanguage() -> WidgetLanguage {
        language = language.toggled
        stateStore.update { state in
            state.language = language
        }
        windowController.update(snapshot: lastSnapshot, activity: lastActivity)
        return language
    }

    private func refreshSnapshot(forceReload: Bool) {
        if refreshInFlight {
            return
        }

        refreshInFlight = true
        let snapshotService = snapshotService
        let activityService = activityService
        refreshQueue.async { [weak self, snapshotService, activityService] in
            let snapshot = snapshotService.latestSnapshot(forceReload: forceReload)
            let activity = activityService.latestActivity()

            Task { @MainActor in
                guard let self else { return }
                self.refreshInFlight = false
                guard self.codexRunning else {
                    return
                }

                self.lastSnapshot = snapshot
                self.lastActivity = activity
                self.windowController.show(snapshot: snapshot, activity: activity)
            }
        }
    }
}
