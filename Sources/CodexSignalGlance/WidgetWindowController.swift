import AppKit

@MainActor
final class WidgetWindowController: NSObject, NSWindowDelegate {
    let window: NSPanel
    var onRequestRefresh: (() -> Void)?
    var onToggleLanguage: (() -> WidgetLanguage)?
    var currentLanguage: (() -> WidgetLanguage)?

    private let stateStore: WidgetStateStore
    private let contentView = WidgetContentView()
    private var isExpanded = false
    private var hasPlacedWindow = false
    private var isActivityCollapsed = true
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    init(stateStore: WidgetStateStore) {
        self.stateStore = stateStore
        self.window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 174, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()

        setupWindow()
        setupContent()
        restoreInitialPlacement()
    }

    func show(snapshot: QuotaSnapshot?, activity: CodexActivitySnapshot) {
        update(snapshot: snapshot, activity: activity)
        if !hasPlacedWindow {
            restoreInitialPlacement()
        }
        if !window.isVisible {
            window.orderFrontRegardless()
        }
    }

    func hide() {
        window.orderOut(nil)
    }

    func toggleExpanded() {
        isExpanded.toggle()
        applySize()
    }

    func update(snapshot: QuotaSnapshot?, activity: CodexActivitySnapshot) {
        let collapsed = activity.shouldCollapseToGreenOnly
        let sizeNeedsUpdate = collapsed != isActivityCollapsed
        isActivityCollapsed = collapsed
        contentView.render(snapshot: snapshot, activity: activity)
        if sizeNeedsUpdate {
            applySize()
        }
    }

    func windowDidMove(_ notification: Notification) {
        let frame = window.frame
        stateStore.save(WidgetState(originX: frame.origin.x, originY: frame.origin.y))
    }

    private func setupWindow() {
        window.delegate = self
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func setupContent() {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.onToggleExpanded = { [weak self] in
            self?.toggleExpanded()
        }
        contentView.onRequestRefresh = { [weak self] in
            self?.onRequestRefresh?()
        }
        contentView.onToggleLanguage = { [weak self] in
            self?.onToggleLanguage?() ?? .english
        }
        contentView.currentLanguage = { [weak self] in
            self?.currentLanguage?() ?? .english
        }
        window.contentView = contentView

        widthConstraint = contentView.widthAnchor.constraint(equalToConstant: currentSize.width)
        heightConstraint = contentView.heightAnchor.constraint(equalToConstant: currentSize.height)
        widthConstraint?.isActive = true
        heightConstraint?.isActive = true

        applySize()
    }

    private func restoreInitialPlacement() {
        let state = stateStore.load()
        if let x = state.originX, let y = state.originY {
            window.setFrameOrigin(clampedOrigin(for: NSPoint(x: x, y: y), size: currentSize))
        } else {
            let frame = defaultFrame(for: currentSize)
            window.setFrame(frame, display: false)
        }
        hasPlacedWindow = true
    }

    private var currentSize: NSSize {
        if isExpanded {
            return NSSize(width: 286, height: 138)
        }
        return isActivityCollapsed ? NSSize(width: 174, height: 34) : NSSize(width: 250, height: 34)
    }

    private func applySize() {
        contentView.setExpanded(isExpanded)
        let newSize = currentSize
        widthConstraint?.constant = newSize.width
        heightConstraint?.constant = newSize.height
        var frame = window.frame
        let deltaHeight = newSize.height - frame.size.height
        frame.origin.y -= deltaHeight
        frame.size = newSize
        frame.origin = clampedOrigin(for: frame.origin, size: frame.size)
        window.setFrame(frame, display: true, animate: true)
    }

    private func defaultFrame(for size: NSSize) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        let x = visible.maxX - size.width - 18
        let y = visible.maxY - size.height - 26
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func clampedOrigin(for origin: NSPoint, size: NSSize) -> NSPoint {
        let screen = screenContaining(point: origin) ?? NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame

        let minX = visible.minX + 8
        let maxX = visible.maxX - size.width - 8
        let minY = visible.minY + 8
        let maxY = visible.maxY - size.height - 8

        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    private func screenContaining(point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}

private final class WidgetContentView: NSView {
    var onToggleExpanded: (() -> Void)?
    var onRequestRefresh: (() -> Void)?
    var onToggleLanguage: (() -> WidgetLanguage)?
    var currentLanguage: (() -> WidgetLanguage)?
    private var mouseDownWindowOrigin: NSPoint?
    private var suppressNextMouseUp = false

    private let summaryStack = NSStackView()
    private let primarySummaryView = SummaryQuotaView(title: "5h")
    private let secondarySummaryView = SummaryQuotaView(title: "7d")
    private let activitySummaryView = TrafficLightStatusView()
    private let summarySeparator = SeparatorView()
    private var activityWidthConstraint: NSLayoutConstraint?
    private var primaryWidthConstraint: NSLayoutConstraint?
    private var secondaryWidthConstraint: NSLayoutConstraint?
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var summaryCenterYConstraint: NSLayoutConstraint?
    private let detailStack = NSStackView()
    private let fiveHourLabel = NSTextField(labelWithString: "5h: --")
    private let sevenDayLabel = NSTextField(labelWithString: "7d: --")
    private let activityLabel = NSTextField(labelWithString: "状态: --")
    private let resetLabel = NSTextField(labelWithString: "重置: --")
    private let freshnessLabel = NSTextField(labelWithString: "最新日志: --")
    private let planLabel = NSTextField(labelWithString: "套餐: --")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    func render(snapshot: QuotaSnapshot?, activity: CodexActivitySnapshot) {
        layer?.backgroundColor = WidgetColors.backgroundColor.cgColor
        activitySummaryView.render(activity: activity)
        activitySummaryView.toolTip = WidgetFormatter.activityTooltip(activity.status)
        activityLabel.stringValue = "状态: \(activity.status.chineseTitle)"
        updateCollapsedLayout(collapsed: activity.shouldCollapseToGreenOnly)

        if let snapshot {
            let windows = normalizedWindows(from: snapshot)
            let fiveHour = windows.fiveHour
            let sevenDay = windows.sevenDay

            primarySummaryView.render(
                label: "5h",
                remainingPercent: fiveHour.map { Int($0.remainingPercent.rounded()) },
                color: WidgetColors.color(for: fiveHour?.remainingPercent)
            )
            primarySummaryView.toolTip = fiveHour.map {
                "5h: 剩余 \(Int($0.remainingPercent.rounded()))%"
            } ?? "5h: 当前日志未提供"

            secondarySummaryView.render(
                label: "7d",
                remainingPercent: sevenDay.map { Int($0.remainingPercent.rounded()) },
                color: WidgetColors.color(for: sevenDay?.remainingPercent)
            )
            secondarySummaryView.toolTip = sevenDay.map {
                "7d: 剩余 \(Int($0.remainingPercent.rounded()))%"
            } ?? "7d: 当前日志未提供"

            if let fiveHour {
                fiveHourLabel.stringValue = "5h: 剩余 \(Int(fiveHour.remainingPercent.rounded()))% · 已用 \(Int(fiveHour.usedPercent.rounded()))%"
            } else {
                fiveHourLabel.stringValue = "5h: 当前日志未提供"
            }

            if let sevenDay {
                sevenDayLabel.stringValue = "7d: 剩余 \(Int(sevenDay.remainingPercent.rounded()))% · 已用 \(Int(sevenDay.usedPercent.rounded()))%"
            } else {
                sevenDayLabel.stringValue = "7d: 当前日志未提供"
            }

            let fiveHourReset = WidgetFormatter.timeUntilReset(fiveHour?.resetsAt)
            let sevenDayReset = WidgetFormatter.timeUntilReset(sevenDay?.resetsAt)
            resetLabel.stringValue = "重置: 5h \(fiveHourReset) · 7d \(sevenDayReset)"
            freshnessLabel.stringValue = "最新日志: \(snapshot.sourceFileName) · \(WidgetFormatter.relativeAge(snapshot.eventTimestamp))"
            planLabel.stringValue = "套餐: \(snapshot.planType ?? "unknown")"
        } else {
            primarySummaryView.render(label: "5h", remainingPercent: nil, color: WidgetColors.mutedColor)
            secondarySummaryView.render(label: "7d", remainingPercent: nil, color: WidgetColors.mutedColor)
            fiveHourLabel.stringValue = "5h: 等 Codex 写入额度数据"
            sevenDayLabel.stringValue = "7d: 等 Codex 写入额度数据"
            activityLabel.stringValue = "状态: \(activity.status.chineseTitle)"
            resetLabel.stringValue = "重置: --"
            freshnessLabel.stringValue = "最新日志: 暂无"
            planLabel.stringValue = "套餐: --"
        }
    }

    func setExpanded(_ expanded: Bool) {
        detailStack.isHidden = !expanded
        summaryCenterYConstraint?.isActive = !expanded
    }

    private func setupViews() {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .centerX
        container.spacing = 7
        container.translatesAutoresizingMaskIntoConstraints = false

        summaryStack.orientation = .horizontal
        summaryStack.alignment = .centerY
        summaryStack.distribution = .fill
        summaryStack.spacing = 7
        summaryStack.translatesAutoresizingMaskIntoConstraints = false
        summaryStack.addArrangedSubview(activitySummaryView)
        summaryStack.addArrangedSubview(summarySeparator)
        summaryStack.addArrangedSubview(primarySummaryView)
        summaryStack.addArrangedSubview(secondarySummaryView)
        primarySummaryView.translatesAutoresizingMaskIntoConstraints = false
        secondarySummaryView.translatesAutoresizingMaskIntoConstraints = false
        activitySummaryView.translatesAutoresizingMaskIntoConstraints = false
        summarySeparator.translatesAutoresizingMaskIntoConstraints = false
        activityWidthConstraint = activitySummaryView.widthAnchor.constraint(equalToConstant: 15)
        activityWidthConstraint?.isActive = true
        primaryWidthConstraint = primarySummaryView.widthAnchor.constraint(equalToConstant: 60)
        secondaryWidthConstraint = secondarySummaryView.widthAnchor.constraint(equalToConstant: 60)
        primaryWidthConstraint?.isActive = true
        secondaryWidthConstraint?.isActive = true
        NSLayoutConstraint.activate([
            summarySeparator.widthAnchor.constraint(equalToConstant: 1),
            summarySeparator.heightAnchor.constraint(equalToConstant: 15),
        ])

        [fiveHourLabel, sevenDayLabel, activityLabel, resetLabel, freshnessLabel, planLabel].forEach { label in
            label.font = .systemFont(ofSize: 11, weight: .regular)
            label.textColor = NSColor.white.withAlphaComponent(0.9)
            label.lineBreakMode = .byTruncatingTail
            detailStack.addArrangedSubview(label)
        }
        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 4
        detailStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 2)
        detailStack.isHidden = true

        container.addArrangedSubview(summaryStack)
        container.addArrangedSubview(detailStack)
        addSubview(container)

        leadingConstraint = container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10)
        trailingConstraint = container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        summaryCenterYConstraint = summaryStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        summaryCenterYConstraint?.isActive = true

        NSLayoutConstraint.activate([
            leadingConstraint!,
            trailingConstraint!,
            container.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    private func updateCollapsedLayout(collapsed: Bool) {
        let targetWidth: CGFloat = collapsed ? 15 : 62
        let targetQuotaWidth: CGFloat = collapsed ? 60 : 66
        let targetInset: CGFloat = collapsed ? 6 : 16
        let targetSpacing: CGFloat = collapsed ? 5 : 7
        let changed = activityWidthConstraint?.constant != targetWidth
            || primaryWidthConstraint?.constant != targetQuotaWidth
            || secondaryWidthConstraint?.constant != targetQuotaWidth
            || leadingConstraint?.constant != targetInset
            || trailingConstraint?.constant != -targetInset
            || summaryStack.spacing != targetSpacing

        guard changed else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            activityWidthConstraint?.animator().constant = targetWidth
            primaryWidthConstraint?.animator().constant = targetQuotaWidth
            secondaryWidthConstraint?.animator().constant = targetQuotaWidth
            leadingConstraint?.animator().constant = targetInset
            trailingConstraint?.animator().constant = -targetInset
            summaryStack.animator().spacing = targetSpacing
            layoutSubtreeIfNeeded()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            suppressNextMouseUp = true
            showContextMenu(with: event)
            return
        }

        mouseDownWindowOrigin = window?.frame.origin
    }

    override func mouseUp(with event: NSEvent) {
        if suppressNextMouseUp {
            suppressNextMouseUp = false
            return
        }

        guard isClickWithoutDrag() else {
            return
        }

        if event.clickCount >= 2 {
            onRequestRefresh?()
            return
        }

        onToggleExpanded?()
    }

    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(with: event)
    }

    private func isClickWithoutDrag() -> Bool {
        guard
            let downOrigin = mouseDownWindowOrigin,
            let currentOrigin = window?.frame.origin
        else {
            return true
        }
        return abs(currentOrigin.x - downOrigin.x) < 1 && abs(currentOrigin.y - downOrigin.y) < 1
    }

    private func showContextMenu(with event: NSEvent) {
        let menu = NSMenu()
        let expanded = !detailStack.isHidden

        let toggleItem = NSMenuItem(
            title: expanded ? "收起详情" : "展开详情",
            action: #selector(handleContextToggle),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let refreshItem = NSMenuItem(
            title: "立即更新",
            action: #selector(handleContextRefresh),
            keyEquivalent: ""
        )
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let languageItem = NSMenuItem(
            title: currentLanguage?().menuTitle ?? WidgetLanguage.english.menuTitle,
            action: #selector(handleContextToggleLanguage),
            keyEquivalent: ""
        )
        languageItem.target = self
        menu.addItem(languageItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc
    private func handleContextToggle() {
        onToggleExpanded?()
    }

    @objc
    private func handleContextRefresh() {
        onRequestRefresh?()
    }

    @objc
    private func handleContextToggleLanguage() {
        _ = onToggleLanguage?()
    }

    private func normalizedWindows(from snapshot: QuotaSnapshot) -> (fiveHour: WindowQuota?, sevenDay: WindowQuota?) {
        let windows = [snapshot.primary, snapshot.secondary].compactMap { $0 }
        let fiveHour = windows.first { $0.label == "5h" }
        let sevenDay = windows.first { $0.label == "7d" }
        return (fiveHour, sevenDay)
    }
}

enum WidgetColors {
    static let backgroundColor = NSColor(calibratedRed: 0.07, green: 0.1, blue: 0.15, alpha: 0.94)
    static let mutedColor = NSColor.white.withAlphaComponent(0.45)

    static func color(for remainingPercent: Double?) -> NSColor {
        let value = remainingPercent ?? 0
        switch value {
        case 60...:
            return NSColor(calibratedRed: 0.23, green: 0.79, blue: 0.39, alpha: 1)
        case 30...:
            return NSColor(calibratedRed: 0.97, green: 0.72, blue: 0.22, alpha: 1)
        default:
            return NSColor(calibratedRed: 0.96, green: 0.4, blue: 0.36, alpha: 1)
        }
    }

    static func activityColor(for status: CodexActivityStatus) -> NSColor {
        switch status {
        case .answering:
            return NSColor(calibratedRed: 0.96, green: 0.31, blue: 0.28, alpha: 1)
        case .waitingForUser:
            return NSColor(calibratedRed: 0.98, green: 0.74, blue: 0.2, alpha: 1)
        case .finished:
            return NSColor(calibratedRed: 0.23, green: 0.79, blue: 0.39, alpha: 1)
        case .unknown:
            return mutedColor
        }
    }
}

private final class SummaryQuotaView: NSView {
    private let colorDot = DotView()
    private let valueLabel = NSTextField(labelWithString: "--")

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = false
        setupViews()
        render(label: title, remainingPercent: nil, color: WidgetColors.mutedColor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(label: String, remainingPercent: Int?, color: NSColor) {
        colorDot.fillColor = color
        let percentText: String
        if let remainingPercent {
            percentText = String(format: "%3d%%", remainingPercent)
        } else {
            percentText = " --%"
        }
        valueLabel.stringValue = "\(label) \(percentText)"
    }

    private func setupViews() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.alignment = .center
        valueLabel.lineBreakMode = .byClipping
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        stack.addArrangedSubview(colorDot)
        stack.addArrangedSubview(valueLabel)
        addSubview(stack)

        NSLayoutConstraint.activate([
            colorDot.widthAnchor.constraint(equalToConstant: 6),
            colorDot.heightAnchor.constraint(equalToConstant: 6),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }
}

final class TrafficLightStatusView: NSView {
    private let redLight = TrafficLightDotView(color: WidgetColors.activityColor(for: .answering))
    private let yellowLight = TrafficLightDotView(color: WidgetColors.activityColor(for: .waitingForUser))
    private let greenLight = TrafficLightDotView(color: WidgetColors.activityColor(for: .finished))
    private var isCollapsed = true
    private var lastStatus: CodexActivityStatus = .finished
    private var finishTransitionUntil: Date?
    private var finishTransitionTimer: Timer?
    private var wakeGreenUntil: Date?
    private var wakeGreenTimer: Timer?
    private var latestActivity: CodexActivitySnapshot?

    private enum DisplayStage {
        case active(CodexActivityStatus, needsHumanAttention: Bool)
        case finishing
        case breathingDone
        case idleCollapsed
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        render(activity: .idle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(activity: CodexActivitySnapshot) {
        latestActivity = activity
        let collapsed = activity.shouldCollapseToGreenOnly
        let wasCollapsed = isCollapsed
        if collapsed != isCollapsed {
            setCollapsed(collapsed)
        }
        isCollapsed = collapsed
        if wasCollapsed && !collapsed && activity.status != .finished {
            startWakeGreenTransition()
        }

        let stage = displayStage(for: activity, collapsed: collapsed)
        apply(stage)
        lastStatus = activity.status
    }

    private func displayStage(for activity: CodexActivitySnapshot, collapsed: Bool) -> DisplayStage {
        if activity.status != .finished || collapsed {
            stopFinishTransition()
        }

        if collapsed {
            stopWakeGreenTransition()
            return .idleCollapsed
        }

        if activity.status == .finished {
            stopWakeGreenTransition()
        }

        if wakeGreenUntil.map({ Date() < $0 }) ?? false {
            return .active(.finished, needsHumanAttention: false)
        }

        if lastStatus == .answering && activity.status == .finished && finishTransitionUntil == nil {
            startFinishTransition()
        }

        if finishTransitionUntil.map({ Date() < $0 }) ?? false {
            return .finishing
        }

        if activity.shouldBreatheBeforeCollapse {
            return .breathingDone
        }

        return .active(activity.status, needsHumanAttention: activity.needsHumanAttention)
    }

    private func apply(_ stage: DisplayStage) {
        switch stage {
        case .active(let status, let needsHumanAttention):
            setLights(
                red: status == .answering,
                yellow: status == .waitingForUser,
                green: status == .finished,
                greenBreathing: false,
                yellowBlinking: status == .waitingForUser && needsHumanAttention
            )

        case .finishing:
            setLights(
                red: false,
                yellow: false,
                green: false,
                greenBreathing: false,
                yellowBlinking: false,
                animated: true,
                cancelRedDimming: false
            )

        case .breathingDone:
            setLights(red: false, yellow: false, green: true, greenBreathing: true, yellowBlinking: false)

        case .idleCollapsed:
            setLights(red: false, yellow: false, green: false, greenBreathing: false, yellowBlinking: false)
        }
    }

    private func setLights(
        red: Bool,
        yellow: Bool,
        green: Bool,
        greenBreathing: Bool,
        yellowBlinking: Bool,
        animated: Bool = true,
        cancelRedDimming: Bool = true
    ) {
        if !red && cancelRedDimming {
            redLight.cancelDimming()
        }
        redLight.setActive(red, animated: animated)
        yellowLight.setActive(yellow, animated: animated)
        greenLight.setActive(green, animated: animated)
        redLight.setBreathing(false)
        yellowLight.setBreathing(false)
        greenLight.setBreathing(greenBreathing)
        redLight.setBlinking(false)
        yellowLight.setBlinking(yellow && yellowBlinking)
        greenLight.setBlinking(false)
    }

    private func setupViews() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8.5
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(redLight)
        stack.addArrangedSubview(yellowLight)
        stack.addArrangedSubview(greenLight)
        addSubview(stack)

        NSLayoutConstraint.activate([
            redLight.widthAnchor.constraint(equalToConstant: 15),
            redLight.heightAnchor.constraint(equalToConstant: 15),
            yellowLight.widthAnchor.constraint(equalToConstant: 15),
            yellowLight.heightAnchor.constraint(equalToConstant: 15),
            greenLight.widthAnchor.constraint(equalToConstant: 15),
            greenLight.heightAnchor.constraint(equalToConstant: 15),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])

        redLight.isHidden = true
        yellowLight.isHidden = true
        redLight.alphaValue = 0
        yellowLight.alphaValue = 0
    }

    private func setCollapsed(_ collapsed: Bool) {
        if !collapsed {
            redLight.isHidden = false
            yellowLight.isHidden = false
            redLight.alphaValue = 0
            yellowLight.alphaValue = 0
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            redLight.animator().alphaValue = collapsed ? 0 : 1
            yellowLight.animator().alphaValue = collapsed ? 0 : 1
            layoutSubtreeIfNeeded()
        } completionHandler: { [weak redLight, weak yellowLight] in
            guard collapsed else { return }
            redLight?.isHidden = true
            yellowLight?.isHidden = true
        }
    }

    private func startFinishTransition() {
        finishTransitionUntil = Date().addingTimeInterval(0.5)
        finishTransitionTimer?.invalidate()
        redLight.dimToInactive(duration: 0.5)
        finishTransitionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.finishTransitionUntil = nil
            self.redLight.setBreathing(false)
            self.redLight.setActive(false, animated: true)
            self.yellowLight.setActive(false, animated: true)
            self.yellowLight.setBlinking(false)
            self.greenLight.setActive(true, animated: true)
            self.greenLight.setBreathing(false)
            self.greenLight.setBlinking(false)
        }
        if let finishTransitionTimer {
            RunLoop.main.add(finishTransitionTimer, forMode: .common)
        }
    }

    private func stopFinishTransition() {
        finishTransitionUntil = nil
        finishTransitionTimer?.invalidate()
        finishTransitionTimer = nil
        redLight.cancelDimming()
    }

    private func startWakeGreenTransition() {
        guard wakeGreenUntil == nil else {
            return
        }
        wakeGreenUntil = Date().addingTimeInterval(1.5)
        wakeGreenTimer?.invalidate()
        wakeGreenTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.wakeGreenUntil = nil
            self.wakeGreenTimer = nil
            if let latestActivity = self.latestActivity {
                self.render(activity: latestActivity)
            }
        }
        if let wakeGreenTimer {
            RunLoop.main.add(wakeGreenTimer, forMode: .common)
        }
    }

    private func stopWakeGreenTransition() {
        wakeGreenUntil = nil
        wakeGreenTimer?.invalidate()
        wakeGreenTimer = nil
    }

    deinit {
        finishTransitionTimer?.invalidate()
        wakeGreenTimer?.invalidate()
    }
}

private final class TrafficLightDotView: NSView {
    let baseColor: NSColor
    private var isActive = false
    private var isBreathing = false
    private var isBlinking = false
    private var breathPhase: CGFloat = 0
    private var blinkPhase: CGFloat = CGFloat.pi / 2
    private var breathTimer: Timer?
    private var blinkTimer: Timer?
    private var activeLevel: CGFloat = 0
    private var activeLevelTimer: Timer?

    init(color: NSColor) {
        self.baseColor = color
        super.init(frame: .zero)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setActive(_ active: Bool, animated: Bool) {
        let target: CGFloat = active ? 1 : 0
        guard active != isActive || abs(activeLevel - target) > 0.001 else {
            return
        }
        isActive = active
        if animated {
            animateActiveLevel(to: target, duration: 0.35)
        } else {
            activeLevelTimer?.invalidate()
            activeLevelTimer = nil
            activeLevel = target
            needsDisplay = true
        }
    }

    func dimToInactive(duration: TimeInterval) {
        breathTimer?.invalidate()
        breathTimer = nil
        isBreathing = false
        stopBlinking()
        isBlinking = false
        isActive = false
        animateActiveLevel(to: 0, duration: duration)
    }

    func cancelDimming() {
        activeLevelTimer?.invalidate()
        activeLevelTimer = nil
        needsDisplay = true
    }

    func setBreathing(_ breathing: Bool) {
        guard breathing != isBreathing else {
            return
        }

        isBreathing = breathing
        if breathing {
            stopBlinking()
            isBlinking = false
            startBreathing()
        } else {
            stopBreathing()
        }
        needsDisplay = true
    }

    func setBlinking(_ blinking: Bool) {
        guard blinking != isBlinking else {
            return
        }

        isBlinking = blinking
        if blinking {
            stopBreathing()
            isBreathing = false
            startBlinking()
        } else {
            stopBlinking()
        }
        needsDisplay = true
    }

    private func startBreathing() {
        breathTimer?.invalidate()
        breathTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.breathPhase += 0.085
            self.needsDisplay = true
        }
        if let breathTimer {
            RunLoop.main.add(breathTimer, forMode: .common)
        }
    }

    private func stopBreathing() {
        breathTimer?.invalidate()
        breathTimer = nil
        breathPhase = 0
    }

    private func startBlinking() {
        blinkTimer?.invalidate()
        blinkPhase = CGFloat.pi / 2
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.blinkPhase += CGFloat.pi / 15
            self.needsDisplay = true
        }
        if let blinkTimer {
            RunLoop.main.add(blinkTimer, forMode: .common)
        }
    }

    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        blinkPhase = CGFloat.pi / 2
    }

    private func animateActiveLevel(to target: CGFloat, duration: TimeInterval) {
        activeLevelTimer?.invalidate()
        let start = activeLevel
        let startedAt = Date()
        activeLevelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(startedAt)
            let rawProgress = min(1, max(0, CGFloat(elapsed / duration)))
            let easedProgress = rawProgress * rawProgress * (3 - 2 * rawProgress)
            self.activeLevel = start + (target - start) * easedProgress
            self.needsDisplay = true

            if rawProgress >= 1 {
                timer.invalidate()
                self.activeLevelTimer = nil
                self.activeLevel = target
                self.needsDisplay = true
            }
        }
        if let activeLevelTimer {
            RunLoop.main.add(activeLevelTimer, forMode: .common)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let dotRect = bounds.insetBy(dx: 1, dy: 1)
        if activeLevel > 0 {
            let pulse = isBreathing ? (sin(breathPhase) + 1) / 2 : 1
            let blinkLevel = isBlinking ? (0.18 + 0.82 * ((sin(blinkPhase) + 1) / 2)) : 1
            let glowPulse = (isBreathing ? (0.68 + 0.32 * pulse) : 1) * activeLevel * blinkLevel
            for step in 0..<5 {
                let spread = CGFloat(5 - step) * 1.45 * glowPulse
                let alpha = CGFloat(step + 1) * 0.055 * glowPulse
                baseColor.withAlphaComponent(alpha).setFill()
                NSBezierPath(ovalIn: dotRect.insetBy(dx: -spread, dy: -spread)).fill()
            }

            let activeDotAlpha: CGFloat = isBreathing ? (0.55 + 0.45 * pulse) : 1
            let dotAlpha = 0.34 + (activeDotAlpha * blinkLevel - 0.34) * activeLevel
            baseColor.withAlphaComponent(dotAlpha).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return
        }

        baseColor.withAlphaComponent(0.34).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    deinit {
        breathTimer?.invalidate()
        blinkTimer?.invalidate()
        activeLevelTimer?.invalidate()
    }
}

private final class SeparatorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.white.withAlphaComponent(0.22).setFill()
        bounds.fill()
    }
}

final class DotView: NSView {
    var fillColor: NSColor = .white {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        fillColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

private enum WidgetFormatter {
    static func activityTooltip(_ status: CodexActivityStatus) -> String {
        switch status {
        case .answering:
            return "红灯: Codex 正在回答"
        case .waitingForUser:
            return "黄灯: 等待人来授权或选择执行"
        case .finished:
            return "绿灯: Codex 回答完毕"
        case .unknown:
            return "暂未读取到 Codex 状态"
        }
    }

    static func timeUntilReset(_ date: Date?) -> String {
        guard let date else { return "--" }
        let delta = Int(date.timeIntervalSinceNow)
        guard delta > 0 else { return "已重置" }

        let hours = delta / 3600
        let minutes = (delta % 3600) / 60

        if hours >= 24 {
            return "\(hours / 24)d \(hours % 24)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    static func relativeAge(_ date: Date?) -> String {
        guard let date else { return "未知" }
        let delta = max(0, Int(-date.timeIntervalSinceNow))
        if delta < 60 {
            return "\(delta)s 前"
        }
        let minutes = delta / 60
        if minutes < 60 {
            return "\(minutes)m 前"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h 前"
        }
        return "\(hours / 24)d 前"
    }
}
