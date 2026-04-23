import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let wordsPerMinuteDefaultsKey = "ClipboardQueueMenuBar.wordsPerMinute"

    private let queue = ClipboardQueue()
    private let typer: Typer
    private let barItem = NSStatusBar.system.statusItem(withLength: 38)
    private let menu = NSMenu()
    private let controlsPanel = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 440, height: 430),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )

    private let statusMessageItem = NSMenuItem(title: "Status: Ready", action: nil, keyEquivalent: "")
    private let queueCountItem = NSMenuItem(title: "Queue: 0", action: nil, keyEquivalent: "")
    private let nextPreviewItem = NSMenuItem(title: "Next: Empty", action: nil, keyEquivalent: "")
    private let typingStatusItem = NSMenuItem(title: "Typing: Idle", action: nil, keyEquivalent: "")
    private let showControlsItem = NSMenuItem(title: "Show Clipboard Typer", action: #selector(showControlsFromMenu), keyEquivalent: "")
    private let enqueueItem = NSMenuItem(title: "Enqueue Clipboard (Ctrl-Opt-Cmd-C)", action: #selector(enqueueClipboardFromMenu), keyEquivalent: "")
    private let typeNextItem = NSMenuItem(title: "Type Next (Ctrl-Opt-Cmd-V)", action: #selector(typeNextFromMenu), keyEquivalent: "")
    private let stopTypingItem = NSMenuItem(title: "Stop Typing", action: #selector(stopTypingFromMenu), keyEquivalent: "")
    private let clearQueueItem = NSMenuItem(title: "Clear Queue", action: #selector(clearQueueFromMenu), keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Grant Accessibility Permission...", action: #selector(requestAccessibilityFromMenu), keyEquivalent: "")

    private let panelStatusLabel = NSTextField(wrappingLabelWithString: "Status: Ready")
    private let panelQueueCountLabel = NSTextField(labelWithString: "Queue: 0")
    private let panelNextLabel = NSTextField(wrappingLabelWithString: "Next: Empty")
    private let panelQueueListLabel = NSTextField(wrappingLabelWithString: "Queue is empty.")
    private let panelSpeedValueLabel = NSTextField(labelWithString: "Typing speed: 160 WPM")
    private let panelSpeedSlider = NSSlider(
        value: TypingSpeed.defaultWordsPerMinute,
        minValue: TypingSpeed.minimumWordsPerMinute,
        maxValue: TypingSpeed.maximumWordsPerMinute,
        target: nil,
        action: nil
    )
    private let panelEnqueueButton = NSButton(title: "Enqueue Clipboard", target: nil, action: nil)
    private let panelTypeNextButton = NSButton(title: "Type Next", target: nil, action: nil)
    private let panelStopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let panelClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let panelAccessibilityButton = NSButton(title: "Grant Accessibility", target: nil, action: nil)
    private let panelQuitButton = NSButton(title: "Quit", target: nil, action: nil)

    private lazy var hotKeyController = HotKeyController { [weak self] action in
        self?.handleHotKey(action)
    }

    private var statusMessage = "Ready"
    private var currentlyTypingPreview: String?

    override init() {
        let savedWordsPerMinute = UserDefaults.standard.object(forKey: Self.wordsPerMinuteDefaultsKey) as? Double
        typer = Typer(wordsPerMinute: TypingSpeed.savedValue(savedWordsPerMinute))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureMenu()
        configureControlsPanel()
        registerHotKeys()
        updateMenu()
        showControlsPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        typer.cancel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControlsPanel()
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenu()
    }

    private func configureStatusItem() {
        if let button = barItem.button {
            button.image = nil
            button.title = "⌨0"
            button.font = NSFont.menuBarFont(ofSize: 0)
            button.toolTip = "Clipboard Typer - click for queue and speed controls"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func configureMenu() {
        menu.delegate = self

        [statusMessageItem, queueCountItem, nextPreviewItem, typingStatusItem].forEach {
            $0.isEnabled = false
            menu.addItem($0)
        }

        menu.addItem(.separator())
        addActionItem(showControlsItem)
        addActionItem(enqueueItem)
        addActionItem(typeNextItem)
        addActionItem(stopTypingItem)
        addActionItem(clearQueueItem)

        menu.addItem(.separator())
        addActionItem(accessibilityItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Clipboard Typer", action: #selector(quitFromMenu), keyEquivalent: "q")
        addActionItem(quitItem)
    }

    private func configureControlsPanel() {
        controlsPanel.title = "Clipboard Typer"
        controlsPanel.isReleasedWhenClosed = false
        controlsPanel.titlebarAppearsTransparent = true
        controlsPanel.isMovableByWindowBackground = true
        controlsPanel.backgroundColor = .clear
        controlsPanel.isOpaque = false
        controlsPanel.level = .normal
        controlsPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        controlsPanel.center()

        let contentView = NSVisualEffectView()
        contentView.material = .hudWindow
        contentView.blendingMode = .behindWindow
        contentView.state = .active
        controlsPanel.contentView = contentView

        let titleLabel = NSTextField(labelWithString: "Clipboard Typer")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 24)
        titleLabel.textColor = .labelColor

        panelStatusLabel.font = NSFont.systemFont(ofSize: 12)
        panelStatusLabel.textColor = .secondaryLabelColor
        panelQueueCountLabel.font = NSFont.boldSystemFont(ofSize: 13)
        panelNextLabel.maximumNumberOfLines = 3
        panelQueueListLabel.maximumNumberOfLines = 6
        panelQueueListLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        panelQueueListLabel.textColor = .labelColor

        panelSpeedValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        panelSpeedSlider.target = self
        panelSpeedSlider.action = #selector(typingSpeedSliderChanged(_:))
        panelSpeedSlider.isContinuous = true
        panelSpeedSlider.numberOfTickMarks = 11
        panelSpeedSlider.allowsTickMarkValuesOnly = false
        panelSpeedSlider.doubleValue = typer.wordsPerMinute
        panelSpeedSlider.translatesAutoresizingMaskIntoConstraints = false

        panelEnqueueButton.target = self
        panelEnqueueButton.action = #selector(enqueueClipboardFromMenu)
        panelTypeNextButton.target = self
        panelTypeNextButton.action = #selector(typeNextFromMenu)
        panelStopButton.target = self
        panelStopButton.action = #selector(stopTypingFromMenu)
        panelClearButton.target = self
        panelClearButton.action = #selector(clearQueueFromMenu)
        panelAccessibilityButton.target = self
        panelAccessibilityButton.action = #selector(requestAccessibilityFromMenu)
        panelQuitButton.target = self
        panelQuitButton.action = #selector(quitFromMenu)

        let speedLabel = NSTextField(labelWithString: "Typing speed")
        speedLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let shortcutsLabel = NSTextField(wrappingLabelWithString: "Shortcuts: Ctrl-Opt-Cmd-O opens controls, Ctrl-Opt-Cmd-C queues clipboard, Ctrl-Opt-Cmd-V types next.")
        shortcutsLabel.font = NSFont.systemFont(ofSize: 11)
        shortcutsLabel.textColor = .secondaryLabelColor

        [panelEnqueueButton, panelTypeNextButton, panelStopButton, panelClearButton, panelAccessibilityButton, panelQuitButton].forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .large
        }

        let buttonRow = NSStackView(views: [
            panelEnqueueButton,
            panelTypeNextButton,
            panelStopButton,
            panelClearButton,
        ])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fillEqually

        let utilityRow = NSStackView(views: [
            panelAccessibilityButton,
            panelQuitButton,
        ])
        utilityRow.orientation = .horizontal
        utilityRow.spacing = 8
        utilityRow.distribution = .fillEqually

        let queueCard = makeGlassCard(containing: NSStackView(views: [
            panelQueueCountLabel,
            panelNextLabel,
            panelQueueListLabel,
        ]))

        let speedCard = makeGlassCard(containing: NSStackView(views: [
            speedLabel,
            panelSpeedValueLabel,
            panelSpeedSlider,
        ]))

        let stack = NSStackView(views: [
            titleLabel,
            panelStatusLabel,
            queueCard,
            speedCard,
            buttonRow,
            utilityRow,
            shortcutsLabel,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 46),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22),
            queueCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            speedCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            panelSpeedSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            utilityRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func makeGlassCard(containing stack: NSStackView) -> NSView {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let card = NSVisualEffectView()
        card.material = .popover
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 18
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 96),
        ])

        return card
    }

    private func addActionItem(_ item: NSMenuItem) {
        item.target = self
        menu.addItem(item)
    }

    private func registerHotKeys() {
        do {
            try hotKeyController.registerDefaultHotKeys()
            setStatus("Ready. Hotkeys registered.")
        } catch {
            setStatus(error.localizedDescription)
        }
    }

    private func handleHotKey(_ action: HotKeyAction) {
        switch action {
        case .enqueueClipboard:
            enqueueClipboard()
        case .typeNext:
            typeNextQueuedMessage()
        case .showControls:
            showControlsPanel()
        }
    }

    private func enqueueClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            setStatus("Clipboard does not contain text.")
            return
        }

        switch queue.enqueue(text) {
        case .queued(let count):
            setStatus("Queued clipboard text. Queue: \(count).")
        case .empty:
            setStatus("Clipboard text is empty.")
        case .duplicate:
            setStatus("Clipboard text is already next in queue.")
        }
    }

    private func typeNextQueuedMessage() {
        guard !typer.isTyping else {
            setStatus("Already typing.")
            return
        }

        guard isAccessibilityTrusted(prompt: true) else {
            setStatus("Accessibility permission is required before typing.")
            return
        }

        guard let message = queue.dequeue() else {
            setStatus("Queue is empty.")
            return
        }

        currentlyTypingPreview = ClipboardQueue.preview(message)
        setStatus("Typing next message.")

        let started = typer.startTyping(message) { [weak self] result in
            self?.handleTypingCompletion(result)
        }

        if !started {
            queue.putBackAtFront(message)
            currentlyTypingPreview = nil
            setStatus("Already typing.")
        }
    }

    private func handleTypingCompletion(_ result: TypingResult) {
        currentlyTypingPreview = nil

        switch result {
        case .completed:
            setStatus("Typed message.")
        case .cancelled:
            setStatus("Typing stopped.")
        case .failed(let message):
            setStatus(message)
        }
    }

    private func stopTyping() {
        guard typer.isTyping else {
            setStatus("Nothing is typing.")
            return
        }

        typer.cancel()
        setStatus("Stopping typing...")
    }

    private func clearQueue() {
        queue.clear()
        setStatus("Queue cleared.")
    }

    private func showControlsPanel(anchorToStatusItem: Bool = false) {
        if anchorToStatusItem {
            positionControlsPanelNearStatusItem()
        } else {
            controlsPanel.center()
        }
        controlsPanel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func positionControlsPanelNearStatusItem() {
        guard let button = barItem.button,
              let statusWindow = button.window
        else {
            controlsPanel.center()
            return
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameInScreen = statusWindow.convertToScreen(buttonFrameInWindow)
        let panelFrame = controlsPanel.frame
        let visibleFrame = statusWindow.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)

        let minX = visibleFrame.minX + 8
        let maxX = visibleFrame.maxX - panelFrame.width - 8
        let preferredX = buttonFrameInScreen.midX - (panelFrame.width / 2)
        let originX = min(max(preferredX, minX), maxX)
        let originY = max(
            visibleFrame.minY + 8,
            buttonFrameInScreen.minY - panelFrame.height - 8
        )

        controlsPanel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt,
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }

    private func updateMenu() {
        if let button = barItem.button {
            button.title = typer.isTyping ? "⌨…" : "⌨\(queue.count)"
            button.toolTip = "Clipboard Typer - Queue: \(queue.count), Speed: \(Int(round(typer.wordsPerMinute))) WPM"
        }

        statusMessageItem.title = "Status: \(statusMessage)"
        queueCountItem.title = "Queue: \(queue.count)"
        nextPreviewItem.title = "Next: \(queue.nextPreview() ?? "Empty")"
        typingStatusItem.title = "Typing: \(currentlyTypingPreview ?? "Idle")"

        enqueueItem.isEnabled = !typer.isTyping
        typeNextItem.isEnabled = !queue.isEmpty && !typer.isTyping
        stopTypingItem.isEnabled = typer.isTyping
        clearQueueItem.isEnabled = !queue.isEmpty

        panelStatusLabel.stringValue = "Status: \(statusMessage)"
        panelQueueCountLabel.stringValue = "Queue: \(queue.count)"
        panelNextLabel.stringValue = "Next: \(queue.nextPreview() ?? "Empty")"
        let queuePreviews = queue.previews()
        panelQueueListLabel.stringValue = queuePreviews.isEmpty ? "Queue is empty." : queuePreviews.joined(separator: "\n")
        panelEnqueueButton.isEnabled = !typer.isTyping
        panelTypeNextButton.isEnabled = !queue.isEmpty && !typer.isTyping
        panelStopButton.isEnabled = typer.isTyping
        panelClearButton.isEnabled = !queue.isEmpty
        panelSpeedSlider.doubleValue = typer.wordsPerMinute
        panelSpeedValueLabel.stringValue = "Typing speed: \(Int(round(typer.wordsPerMinute))) WPM"
        panelAccessibilityButton.title = AXIsProcessTrusted()
            ? "Accessibility Granted"
            : "Grant Accessibility"
        panelAccessibilityButton.isEnabled = !AXIsProcessTrusted()

        accessibilityItem.title = AXIsProcessTrusted()
            ? "Accessibility Permission: Granted"
            : "Grant Accessibility Permission..."
        accessibilityItem.isEnabled = !AXIsProcessTrusted()
    }

    private func setStatus(_ message: String) {
        statusMessage = message
        updateMenu()
    }

    @objc private func enqueueClipboardFromMenu() {
        enqueueClipboard()
    }

    @objc private func statusItemClicked() {
        showControlsPanel(anchorToStatusItem: true)
    }

    @objc private func showControlsFromMenu() {
        showControlsPanel(anchorToStatusItem: true)
    }

    @objc private func typeNextFromMenu() {
        typeNextQueuedMessage()
    }

    @objc private func stopTypingFromMenu() {
        stopTyping()
    }

    @objc private func clearQueueFromMenu() {
        clearQueue()
    }

    @objc private func requestAccessibilityFromMenu() {
        if isAccessibilityTrusted(prompt: true) {
            setStatus("Accessibility permission is granted.")
        } else {
            setStatus("Approve Accessibility permission in System Settings.")
        }

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func typingSpeedSliderChanged(_ sender: NSSlider) {
        let wordsPerMinute = round(sender.doubleValue)
        typer.wordsPerMinute = wordsPerMinute
        UserDefaults.standard.set(wordsPerMinute, forKey: Self.wordsPerMinuteDefaultsKey)
        setStatus("Typing speed set to \(Int(wordsPerMinute)) WPM.")
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }
}
