import AppKit

@MainActor
final class HandoffWatcherApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var restartItem: NSMenuItem!
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var state: HandoffWatcherState = .checking
    private var reports: [ServiceReport] = []
    private var lastCheck: Date?
    private var restartFailure: RestartFailure?
    private let engine = ServiceEngine()
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: L10n.text("state.checking"))
    private let subtitle = NSTextField(wrappingLabelWithString: L10n.text("scope"))
    private let timeLabel = NSTextField(labelWithString: L10n.text("state.checking"))
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let restartButton = NSButton(title: L10n.text("action.restart"), target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let noteLabel = NSTextField(labelWithString: L10n.text("clipboard_note"))
    private let quitButton = NSButton(title: L10n.text("action.quit"), target: nil, action: nil)
    private var contentStack: NSStackView!
    #if HANDOFF_WATCHER_QA
    private var previewState: HandoffWatcherState?
    #endif
    private var statusLabels: [NSTextField] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.relay.app").filter { $0.processIdentifier != getpid() }
        if let existing = others.first {
            existing.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }
        createMainMenu()
        createStatusItem()
        createWindow()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        showWindow()
        render()
        refresh()
    }
    private func createMainMenu() {
        let menu = NSMenu()
        let appRoot = NSMenuItem(); menu.addItem(appRoot)
        let appMenu = NSMenu(); appRoot.submenu = appMenu
        let about = appMenu.addItem(withTitle: L10n.text("menu.about"), action: #selector(showAbout), keyEquivalent: ""); about.target = self
        #if HANDOFF_WATCHER_QA
        let qaRoot = NSMenuItem(title: L10n.text("qa.menu"), action: nil, keyEquivalent: "")
        let qa = NSMenu(); qaRoot.submenu = qa
        let choices: [(String, Selector)] = [
            ("qa.light", #selector(qaLight)), ("qa.dark", #selector(qaDark)),
            ("qa.english", #selector(qaEnglish)), ("qa.chinese", #selector(qaChinese)),
            ("qa.healthy", #selector(qaHealthy)), ("qa.checking", #selector(qaChecking)),
            ("qa.restarting", #selector(qaRestarting)), ("qa.error", #selector(qaError)),
            ("qa.reset", #selector(qaReset))
        ]
        for (key, action) in choices {
            let item = qa.addItem(withTitle: L10n.text(key), action: action, keyEquivalent: ""); item.target = self
        }
        appMenu.addItem(qaRoot)
        #endif
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.text("menu.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.text("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let windowRoot = NSMenuItem(); menu.addItem(windowRoot)
        let windowMenu = NSMenu(title: L10n.text("menu.window")); windowRoot.submenu = windowMenu
        windowMenu.addItem(withTitle: L10n.text("menu.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: L10n.text("menu.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let show = windowMenu.addItem(withTitle: L10n.text("menu.show"), action: #selector(showWindow), keyEquivalent: "0"); show.target = self
        NSApp.mainMenu = menu; NSApp.windowsMenu = windowMenu
    }
    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        createLocalizedStatusMenu()
    }
    private func createLocalizedStatusMenu() {
        let menu = NSMenu(); menu.autoenablesItems = false
        restartItem = NSMenuItem(title: L10n.text("action.restart"), action: #selector(restart), keyEquivalent: "")
        restartItem.target = self; restartItem.toolTip = L10n.text("clipboard_note")
        menu.addItem(restartItem)
        menu.addItem(NSMenuItem(title: L10n.text("action.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
    private func createWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 350), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "HandoffWatcher"
        window.isReleasedWhenClosed = false
        // Preserve existing window placement across the app rename.
        window.setFrameAutosaveName("RelayMainWindow")
        window.center()
        let content = window.contentView!
        let root = NSStackView(); contentStack = root; root.orientation = .vertical; root.alignment = .centerX; root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([imageView.widthAnchor.constraint(equalToConstant: 42), imageView.heightAnchor.constraint(equalToConstant: 42)])
        imageView.imageScaling = .scaleProportionallyUpOrDown
        root.addArrangedSubview(imageView)
        titleLabel.font = .systemFont(ofSize: 21, weight: .semibold)
        root.addArrangedSubview(titleLabel)
        subtitle.preferredMaxLayoutWidth = 384
        subtitle.setContentCompressionResistancePriority(.required, for: .vertical)
        subtitle.font = .systemFont(ofSize: 12); subtitle.textColor = .secondaryLabelColor; subtitle.alignment = .center
        root.addArrangedSubview(subtitle)
        subtitle.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let serviceRows = NSStackView(); serviceRows.orientation = .vertical; serviceRows.spacing = 6
        for service in HandoffWatcherService.all {
            let name = NSTextField(labelWithString: service.name); name.font = .monospacedSystemFont(ofSize: 12, weight: .regular); name.textColor = .secondaryLabelColor
            let value = NSTextField(labelWithString: L10n.text("state.checking")); value.font = .systemFont(ofSize: 12); value.alignment = .right
            statusLabels.append(value)
            let row = NSStackView(views: [name, NSView(), value]); row.orientation = .horizontal
            serviceRows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: 280).isActive = true
        }
        root.addArrangedSubview(serviceRows)
        timeLabel.font = .systemFont(ofSize: 11); timeLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(timeLabel)
        errorLabel.font = .systemFont(ofSize: 11); errorLabel.textColor = .systemRed; errorLabel.alignment = .center
        errorLabel.maximumNumberOfLines = 0
        errorLabel.preferredMaxLayoutWidth = 384
        errorLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        root.addArrangedSubview(errorLabel)
        errorLabel.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        errorLabel.isHidden = true
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        restartButton.bezelStyle = .rounded; restartButton.controlSize = .large; restartButton.target = self; restartButton.action = #selector(restart)
        restartButton.keyEquivalent = "\r"
        restartButton.toolTip = L10n.text("clipboard_note")
        quitButton.target = NSApp; quitButton.action = #selector(NSApplication.terminate(_:)); quitButton.bezelStyle = .rounded; quitButton.controlSize = .large
        let actions = NSStackView(views: [restartButton, quitButton]); actions.orientation = .horizontal; actions.spacing = 12
        root.addArrangedSubview(actions)
        root.addArrangedSubview(progress)
        noteLabel.font = .systemFont(ofSize: 11); noteLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(noteLabel)
        window.setContentSize(NSSize(width: 440, height: 350))
    }
    @objc func showWindow() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); task?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "HandoffWatcher", NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): L10n.text("about.description")])
    }
    #if HANDOFF_WATCHER_QA
    @objc private func qaLight() { NSApp.appearance = NSAppearance(named: .aqua) }
    @objc private func qaDark() { NSApp.appearance = NSAppearance(named: .darkAqua) }
    private func qaLanguage(_ language: String) {
        L10n.previewBundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
        createMainMenu()
        createLocalizedStatusMenu()
        render()
    }
    @objc private func qaEnglish() { qaLanguage("en") }
    @objc private func qaChinese() { qaLanguage("zh-Hans") }
    private func preview(_ value: HandoffWatcherState) {
        task?.cancel(); task = nil; previewState = value; state = value
        reports = HandoffWatcherService.all.map { ServiceReport(service: $0, status: .running, pid: nil) }
        restartFailure = nil
        if value == .unhealthy {
            reports = HandoffWatcherService.all.map { ServiceReport(service: $0, status: .failed(.init(reason: .checkTimeout)), pid: nil) }
            restartFailure = RestartFailure(summary: .recoveryTimeout, problems: HandoffWatcherService.all.map { .init(reason: .restartUnconfirmed, service: $0.name) })
        }
        render()
    }
    @objc private func qaHealthy() { preview(.healthy) }
    @objc private func qaChecking() { preview(.checking) }
    @objc private func qaRestarting() { preview(.restarting) }
    @objc private func qaError() { preview(.unhealthy) }
    @objc private func qaReset() { previewState = nil; restartFailure = nil; state = .checking; render(); refresh() }
    #endif
    @objc private func woke() { refresh() }
    private func refresh() {
        #if HANDOFF_WATCHER_QA
        guard previewState == nil else { return }
        #endif
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            let result = await engine.checkAll()
            guard !Task.isCancelled else { return }
            reports = result; lastCheck = Date()
            state = result.allSatisfy(\.healthy) && restartFailure == nil ? .healthy : .unhealthy
            render(); task = nil
        }
    }
    @objc private func restart() {
        #if HANDOFF_WATCHER_QA
        guard previewState == nil else { return }
        #endif
        guard state != .restarting else { return }
        task?.cancel(); task = nil
        state = .restarting; restartFailure = nil; render()
        task = Task { [weak self] in
            guard let self else { return }
            let outcome = await engine.restart()
            guard !Task.isCancelled else { return }
            reports = outcome.reports; restartFailure = outcome.failure; lastCheck = Date()
            state = outcome.failure == nil && reports.allSatisfy(\.healthy) ? .healthy : .unhealthy
            render(); task = nil
        }
    }
    private func render() {
        let title: String
        switch state {
        case .healthy: title = L10n.text("state.healthy")
        case .unhealthy: title = L10n.text("state.unhealthy")
        case .checking: title = L10n.text("state.checking")
        case .restarting: title = L10n.text("state.restarting")
        }
        titleLabel.stringValue = title
        subtitle.stringValue = L10n.text("scope")
        noteLabel.stringValue = L10n.text("clipboard_note")
        quitButton.title = L10n.text("action.quit")
        restartButton.toolTip = L10n.text("clipboard_note")
        restartItem.toolTip = L10n.text("clipboard_note")
        imageView.image = Artwork.status(state, size: 42)
        imageView.contentTintColor = state == .unhealthy ? .systemRed : .controlAccentColor
        imageView.setAccessibilityLabel(title)
        statusItem.button?.image = Artwork.status(state)
        statusItem.button?.setAccessibilityLabel(title)
        let time = lastCheck.map { L10n.time($0) } ?? "—"
        timeLabel.stringValue = L10n.text("last_checked", time)
        for (index, label) in statusLabels.enumerated() {
            let report = reports.first { $0.service.name == HandoffWatcherService.all[index].name }
            label.stringValue = state == .restarting ? L10n.text("state.restarting") : (state == .checking ? L10n.text("state.checking") : (report?.healthy == false ? L10n.text("service.issue") : report?.detail ?? L10n.text("state.checking")))
            label.toolTip = report?.status == .idle ? L10n.text("service.idle_help") : report?.detail
            label.textColor = report?.healthy == false ? .systemRed : .labelColor
        }
        let details = reports.map { L10n.text("service_detail", $0.service.name, $0.detail) }.joined(separator: "\n")
        let error = restartFailure?.localized() ?? reports.filter { !$0.healthy }.map { L10n.text("service_detail", $0.service.name, $0.detail) }.joined(separator: "\n")
        statusItem.button?.toolTip = [title, details, L10n.text("last_checked", time), L10n.text("scope"), error].filter { !$0.isEmpty }.joined(separator: "\n")
        errorLabel.stringValue = error
        errorLabel.toolTip = error
        errorLabel.isHidden = error.isEmpty || state == .restarting
        let busy = state == .restarting
        restartButton.isEnabled = !busy; restartItem.isEnabled = !busy
        restartButton.title = busy ? L10n.text("state.restarting") : L10n.text("action.restart")
        restartItem.title = restartButton.title
        if busy { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        window.contentView?.layoutSubtreeIfNeeded()
        let desiredHeight = max(350, ceil(contentStack.fittingSize.height + 44))
        if window.contentView!.frame.height != desiredHeight { window.setContentSize(NSSize(width: 440, height: desiredHeight)) }
    }
}

@main
struct HandoffWatcherMain {
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--diagnose") || CommandLine.arguments.contains("--restart-services") {
            let engine = ServiceEngine()
            let outcome: RestartOutcome
            if CommandLine.arguments.contains("--restart-services") { outcome = await engine.restart() }
            else { outcome = RestartOutcome(reports: await engine.checkAll(), failure: nil) }
            let data = outcome.json(verbose: CommandLine.arguments.contains("--verbose"))
            if let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) { print(String(decoding: json, as: UTF8.self)) }
            exit(outcome.failure == nil && outcome.reports.allSatisfy(\.healthy) ? 0 : 1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        if CommandLine.arguments.contains("--appearance=dark") { app.appearance = NSAppearance(named: .darkAqua) }
        if CommandLine.arguments.contains("--appearance=light") { app.appearance = NSAppearance(named: .aqua) }
        let delegate = HandoffWatcherApp()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
