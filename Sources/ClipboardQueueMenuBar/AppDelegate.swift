import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let wordsPerMinuteDefaultsKey = "ClipboardQueueMenuBar.wordsPerMinute"

    private static let toolbarIdentifier = NSToolbar.Identifier("ClipboardTyperToolbar")
    private static let toolbarStop = NSToolbarItem.Identifier("ct.stop")
    private static let toolbarClear = NSToolbarItem.Identifier("ct.clear")

    private let queue = ClipboardQueue()
    private let typer: Typer
    private let barItem = NSStatusBar.system.statusItem(withLength: 38)
    private let menu = NSMenu()
    private let controlsPanel = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
        styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
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
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    private let panelStatusLabel = NSTextField(labelWithString: "Ready")
    private let panelQueueSection = SectionView(title: "Queue")
    private let panelQueueCountBadge = NSTextField(labelWithString: "0")
    private let panelQueueEmptyLabel = NSTextField(labelWithString: "No items queued")
    private let panelQueueScrollView = NSScrollView()
    private let panelQueueTableView = QueueTableView()
    private let panelQueueContainer = NSView()
    private let panelSpeedSection = SectionView(title: "Typing speed")
    private let panelSpeedValueLabel = NSTextField(labelWithString: "160 WPM")
    private let panelSpeedSlider = NSSlider(
        value: TypingSpeed.defaultWordsPerMinute,
        minValue: TypingSpeed.minimumWordsPerMinute,
        maxValue: TypingSpeed.maximumWordsPerMinute,
        target: nil,
        action: nil
    )
    private let panelAccessibilityBanner = SectionView(title: nil)
    private let panelAccessibilityButton = NSButton(title: "Open System Settings", target: nil, action: nil)
    private let panelShortcutsLabel = NSTextField(labelWithString: "")

    private var toolbarStopItem: NSToolbarItem?
    private var toolbarClearItem: NSToolbarItem?

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
        configureMainMenu()
        configureStatusItem()
        configureMenu()
        configureControlsPanel()
        registerHotKeys()
        updateMenu()
        showControlsPanel()
    }

    private func configureMainMenu() {
        let appName = "Clipboard Typer"
        let mainMenu = NSMenu()

        // Application menu — gives us ⌘Q, ⌘H, About, etc.
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(NSMenuItem(
            title: "About \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "Hide \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ))
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        // Edit menu — wired to first responder so the speed slider, text fields,
        // and the queue table get standard editing shortcuts (cut/copy/paste/⌘A).
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        ))

        // Window menu — gives us ⌘W close, ⌘M minimize, etc.
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu

        windowMenu.addItem(NSMenuItem(
            title: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))
        windowMenu.addItem(NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        windowMenu.addItem(NSMenuItem(
            title: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        ))

        // Help menu — completes the standard App / Edit / Window / Help layout.
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu

        helpMenu.addItem(NSMenuItem(
            title: "\(appName) Help",
            action: #selector(showShortcutsHelp),
            keyEquivalent: "?"
        ))

        NSApplication.shared.mainMenu = mainMenu
        NSApplication.shared.windowsMenu = windowMenu
        NSApplication.shared.helpMenu = helpMenu
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
            let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Clipboard Typer")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.title = " 0"
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
        addActionItem(launchAtLoginItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Clipboard Typer", action: #selector(quitFromMenu), keyEquivalent: "q")
        addActionItem(quitItem)
    }

    private func configureControlsPanel() {
        controlsPanel.title = "Clipboard Typer"
        controlsPanel.isReleasedWhenClosed = false
        controlsPanel.titlebarAppearsTransparent = true
        controlsPanel.titleVisibility = .visible
        controlsPanel.toolbarStyle = .unified
        controlsPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        controlsPanel.contentMinSize = NSSize(width: 540, height: 400)
        // Remember window position across launches via NSUserDefaults under this key.
        controlsPanel.setFrameAutosaveName("ClipboardTyperControls")
        if controlsPanel.frame.origin == .zero {
            controlsPanel.center()
        }

        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        controlsPanel.toolbar = toolbar

        // Translucent window so Liquid Glass surfaces (toolbar + cards) can
        // refract the desktop and other content showing through.
        controlsPanel.isOpaque = false
        controlsPanel.backgroundColor = .clear

        let backdrop = NSVisualEffectView()
        backdrop.material = .menu
        backdrop.blendingMode = .behindWindow
        backdrop.state = .followsWindowActiveState
        controlsPanel.contentView = backdrop
        let contentView = backdrop

        configureQueueSection()
        configureSpeedSection()
        configureAccessibilityBanner()
        configureFooter()

        let bodyContent = NSStackView(views: [
            panelQueueSection,
            panelSpeedSection,
            panelAccessibilityBanner,
        ])
        bodyContent.orientation = .vertical
        bodyContent.alignment = .leading
        bodyContent.spacing = 14
        bodyContent.translatesAutoresizingMaskIntoConstraints = false

        // Group the cards in a glass effect container so multiple Liquid Glass
        // surfaces share a single rendering pass and meld together as they move.
        let glassContainer: NSView
        if #available(macOS 26.0, *) {
            let container = NSGlassEffectContainerView()
            container.spacing = 14
            container.contentView = bodyContent
            container.translatesAutoresizingMaskIntoConstraints = false
            glassContainer = container
        } else {
            glassContainer = bodyContent
        }

        let stack = NSStackView(views: [
            glassContainer,
            panelStatusLabel,
            panelShortcutsLabel,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(16, after: glassContainer)
        stack.setCustomSpacing(4, after: panelStatusLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)

        let safeArea = contentView.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: safeArea.bottomAnchor, constant: -14),

            glassContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bodyContent.widthAnchor.constraint(equalTo: glassContainer.widthAnchor),

            panelQueueSection.widthAnchor.constraint(equalTo: bodyContent.widthAnchor),
            panelSpeedSection.widthAnchor.constraint(equalTo: bodyContent.widthAnchor),
            panelAccessibilityBanner.widthAnchor.constraint(equalTo: bodyContent.widthAnchor),

            panelStatusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            panelShortcutsLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),

            panelQueueScrollView.heightAnchor.constraint(equalToConstant: 132),
            panelSpeedSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])
    }

    private func configureQueueSection() {
        panelQueueCountBadge.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .medium
        )
        panelQueueCountBadge.textColor = .secondaryLabelColor
        panelQueueSection.accessoryView = panelQueueCountBadge

        panelQueueTableView.style = .inset
        panelQueueTableView.headerView = nil
        panelQueueTableView.allowsMultipleSelection = false
        panelQueueTableView.usesAutomaticRowHeights = true
        panelQueueTableView.rowSizeStyle = .default
        panelQueueTableView.intercellSpacing = NSSize(width: 0, height: 2)
        panelQueueTableView.backgroundColor = .clear
        panelQueueTableView.dataSource = self
        panelQueueTableView.delegate = self
        panelQueueTableView.menu = makeQueueRowMenu()
        panelQueueTableView.onDelete = { [weak self] row in
            self?.removeQueueItem(at: row)
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("preview"))
        column.title = "Item"
        column.resizingMask = [.autoresizingMask]
        panelQueueTableView.addTableColumn(column)

        panelQueueScrollView.documentView = panelQueueTableView
        panelQueueScrollView.hasVerticalScroller = true
        panelQueueScrollView.hasHorizontalScroller = false
        panelQueueScrollView.borderType = .noBorder
        panelQueueScrollView.drawsBackground = false
        panelQueueScrollView.scrollerStyle = .overlay
        panelQueueScrollView.translatesAutoresizingMaskIntoConstraints = false

        panelQueueEmptyLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        panelQueueEmptyLabel.textColor = .secondaryLabelColor
        panelQueueEmptyLabel.alignment = .center
        panelQueueEmptyLabel.translatesAutoresizingMaskIntoConstraints = false

        panelQueueContainer.translatesAutoresizingMaskIntoConstraints = false
        panelQueueContainer.addSubview(panelQueueScrollView)
        panelQueueContainer.addSubview(panelQueueEmptyLabel)

        NSLayoutConstraint.activate([
            panelQueueScrollView.leadingAnchor.constraint(equalTo: panelQueueContainer.leadingAnchor),
            panelQueueScrollView.trailingAnchor.constraint(equalTo: panelQueueContainer.trailingAnchor),
            panelQueueScrollView.topAnchor.constraint(equalTo: panelQueueContainer.topAnchor),
            panelQueueScrollView.bottomAnchor.constraint(equalTo: panelQueueContainer.bottomAnchor),

            panelQueueEmptyLabel.centerXAnchor.constraint(equalTo: panelQueueContainer.centerXAnchor),
            panelQueueEmptyLabel.centerYAnchor.constraint(equalTo: panelQueueContainer.centerYAnchor),
            panelQueueEmptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: panelQueueContainer.leadingAnchor, constant: 8),
            panelQueueEmptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: panelQueueContainer.trailingAnchor, constant: -8),
        ])

        panelQueueSection.contentView = panelQueueContainer
    }

    private func configureSpeedSection() {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let slowImage = NSImage(systemSymbolName: "tortoise.fill", accessibilityDescription: "Slower")?
            .withSymbolConfiguration(symbolConfig)
        let fastImage = NSImage(systemSymbolName: "hare.fill", accessibilityDescription: "Faster")?
            .withSymbolConfiguration(symbolConfig)
        let slowIcon = NSImageView(image: slowImage ?? NSImage())
        slowIcon.contentTintColor = .secondaryLabelColor
        let fastIcon = NSImageView(image: fastImage ?? NSImage())
        fastIcon.contentTintColor = .secondaryLabelColor

        panelSpeedSlider.target = self
        panelSpeedSlider.action = #selector(typingSpeedSliderChanged(_:))
        panelSpeedSlider.isContinuous = true
        panelSpeedSlider.numberOfTickMarks = 0
        panelSpeedSlider.doubleValue = typer.wordsPerMinute
        panelSpeedSlider.translatesAutoresizingMaskIntoConstraints = false
        panelSpeedSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)

        panelSpeedValueLabel.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .regular
        )
        panelSpeedValueLabel.textColor = .secondaryLabelColor
        panelSpeedValueLabel.alignment = .right
        panelSpeedValueLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let sliderRow = NSStackView(views: [slowIcon, panelSpeedSlider, fastIcon])
        sliderRow.orientation = .horizontal
        sliderRow.alignment = .centerY
        sliderRow.spacing = 8

        let speedStack = NSStackView(views: [sliderRow, panelSpeedValueLabel])
        speedStack.orientation = .vertical
        speedStack.alignment = .trailing
        speedStack.spacing = 6
        sliderRow.translatesAutoresizingMaskIntoConstraints = false
        sliderRow.widthAnchor.constraint(equalTo: speedStack.widthAnchor).isActive = true

        panelSpeedSection.contentView = speedStack
    }

    private func configureAccessibilityBanner() {
        let icon = NSImageView(
            image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
                ?? NSImage()
        )
        icon.contentTintColor = .systemYellow
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)

        let title = NSTextField(labelWithString: "Accessibility permission required")
        title.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)

        let detail = NSTextField(wrappingLabelWithString:
            "Clipboard Typer needs Accessibility access to type into other apps."
        )
        detail.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor

        panelAccessibilityButton.target = self
        panelAccessibilityButton.action = #selector(requestAccessibilityFromMenu)
        panelAccessibilityButton.bezelStyle = .rounded
        panelAccessibilityButton.controlSize = .small

        let textStack = NSStackView(views: [title, detail])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let row = NSStackView(views: [icon, textStack, NSView(), panelAccessibilityButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.distribution = .fill

        panelAccessibilityBanner.tintColor = .systemYellow
        panelAccessibilityBanner.contentView = row
    }

    private func configureFooter() {
        panelStatusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        panelStatusLabel.textColor = .secondaryLabelColor
        panelStatusLabel.lineBreakMode = .byTruncatingTail
        panelStatusLabel.maximumNumberOfLines = 2
        panelStatusLabel.cell?.wraps = true
        panelStatusLabel.alignment = .center

        panelShortcutsLabel.stringValue = "⌃⌥⌘O Show controls   ⌃⌥⌘C Enqueue   ⌃⌥⌘V Type next"
        panelShortcutsLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        panelShortcutsLabel.textColor = .tertiaryLabelColor
        panelShortcutsLabel.alignment = .center
    }

    private func makeQueueRowMenu() -> NSMenu {
        let menu = NSMenu()
        let removeItem = NSMenuItem(title: "Remove", action: #selector(removeSelectedQueueRow), keyEquivalent: "")
        removeItem.target = self
        menu.addItem(removeItem)
        return menu
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

    private func removeQueueItem(at index: Int) {
        guard index >= 0, index < queue.count else {
            return
        }

        queue.remove(at: index)
        setStatus("Removed item from queue.")
    }

    private func showControlsPanel(anchorToStatusItem: Bool = false) {
        if anchorToStatusItem {
            positionControlsPanelNearStatusItem()
        } else if !controlsPanel.isVisible {
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
        let isTyping = typer.isTyping
        let queueCount = queue.count
        let queueIsEmpty = queue.isEmpty
        let accessibilityGranted = AXIsProcessTrusted()

        if let button = barItem.button {
            button.title = isTyping ? " …" : " \(queueCount)"
            button.toolTip = "Clipboard Typer - Queue: \(queueCount), Speed: \(Int(round(typer.wordsPerMinute))) WPM"
        }

        NSApp.dockTile.badgeLabel = queueCount > 0 ? "\(queueCount)" : nil

        let launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        launchAtLoginItem.state = launchAtLoginEnabled ? .on : .off

        statusMessageItem.title = "Status: \(statusMessage)"
        queueCountItem.title = "Queue: \(queueCount)"
        nextPreviewItem.title = "Next: \(queue.nextPreview() ?? "Empty")"
        typingStatusItem.title = "Typing: \(currentlyTypingPreview ?? "Idle")"

        enqueueItem.isEnabled = !isTyping
        typeNextItem.isEnabled = !queueIsEmpty && !isTyping
        stopTypingItem.isEnabled = isTyping
        clearQueueItem.isEnabled = !queueIsEmpty

        panelStatusLabel.stringValue = statusMessage
        panelQueueCountBadge.stringValue = "\(queueCount)"
        panelQueueEmptyLabel.isHidden = !queueIsEmpty
        panelQueueScrollView.isHidden = queueIsEmpty
        panelQueueTableView.reloadData()

        panelSpeedSlider.doubleValue = typer.wordsPerMinute
        panelSpeedValueLabel.stringValue = "\(Int(round(typer.wordsPerMinute))) WPM"

        panelAccessibilityBanner.isHidden = accessibilityGranted

        toolbarStopItem?.isEnabled = isTyping
        toolbarClearItem?.isEnabled = !queueIsEmpty

        accessibilityItem.title = accessibilityGranted
            ? "Accessibility Permission: Granted"
            : "Grant Accessibility Permission..."
        accessibilityItem.isEnabled = !accessibilityGranted
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

    @objc private func removeSelectedQueueRow() {
        let row = panelQueueTableView.clickedRow >= 0
            ? panelQueueTableView.clickedRow
            : panelQueueTableView.selectedRow
        guard row >= 0 else { return }
        removeQueueItem(at: row)
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
        updateMenu()
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                setStatus("Disabled launch at login.")
            } else {
                try service.register()
                setStatus("Enabled launch at login.")
            }
        } catch {
            setStatus("Could not change launch-at-login: \(error.localizedDescription)")
        }
    }

    @objc private func showShortcutsHelp() {
        let alert = NSAlert()
        alert.messageText = "Clipboard Typer Shortcuts"
        alert.informativeText = """
            ⌃⌥⌘O — Show controls window
            ⌃⌥⌘C — Enqueue clipboard text
            ⌃⌥⌘V — Type the next queued message

            Inside the controls window:
            • Delete or Backspace removes the selected queue item
            • Right-click a queue item for the Remove menu
            • The slider sets typing speed (100–500 WPM)

            Toolbar Stop cancels the in-flight typing task.
            Toolbar Clear empties the queue without typing.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - NSToolbarDelegate

extension AppDelegate: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.toolbarStop,
            Self.toolbarClear,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.toolbarStop,
            Self.toolbarClear,
            .flexibleSpace,
            .space,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.toolbarStop:
            let item = makeToolbarItem(
                identifier: itemIdentifier,
                label: "Stop",
                symbolName: "stop.fill",
                action: #selector(stopTypingFromMenu)
            )
            toolbarStopItem = item
            return item
        case Self.toolbarClear:
            let item = makeToolbarItem(
                identifier: itemIdentifier,
                label: "Clear",
                symbolName: "trash",
                action: #selector(clearQueueFromMenu)
            )
            toolbarClearItem = item
            return item
        default:
            return nil
        }
    }

    private func makeToolbarItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.target = self
        item.action = action
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        item.isBordered = true
        return item
    }
}

// MARK: - NSTableViewDataSource & NSTableViewDelegate

extension AppDelegate: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        queue.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("QueueRowCell")

        let cell: NSTableCellView
        if let recycled = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = recycled
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let label = NSTextField(wrappingLabelWithString: "")
            label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            label.textColor = .labelColor
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false

            cell.addSubview(label)
            cell.textField = label

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
                label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4),
            ])
        }

        let messages = queue.allMessages()
        if row < messages.count {
            cell.textField?.stringValue = ClipboardQueue.preview(messages[row], limit: 96)
        }

        return cell
    }
}

// MARK: - QueueTableView (delete-key support)

final class QueueTableView: NSTableView {
    var onDelete: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        // 51 = delete (backspace), 117 = forward delete
        if (event.keyCode == 51 || event.keyCode == 117), selectedRow >= 0 {
            onDelete?(selectedRow)
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - SectionView (Liquid Glass card with optional title + accessory)

/// A Tahoe-style rounded card. On macOS 26+ it renders inside an NSGlassEffectView
/// (real Liquid Glass material). Older systems fall back to a subtle rounded card
/// using `controlBackgroundColor`.
final class SectionView: NSView {
    private let titleLabel: NSTextField?
    private let card = NSView()
    private let separator = NSBox()
    private let glassWrapper: NSView
    private let headerStack = NSStackView()
    private var headerAccessoryView: NSView?

    var contentView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()

            guard let contentView else {
                return
            }

            contentView.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(contentView)

            let topAnchor: NSLayoutYAxisAnchor
            let topInset: CGFloat
            if titleLabel != nil {
                topAnchor = separator.bottomAnchor
                topInset = 12
            } else {
                topAnchor = card.topAnchor
                topInset = 14
            }

            NSLayoutConstraint.activate([
                contentView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
                contentView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
                contentView.topAnchor.constraint(equalTo: topAnchor, constant: topInset),
                contentView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            ])
        }
    }

    var accessoryView: NSView? {
        didSet {
            if let oldValue {
                headerStack.removeArrangedSubview(oldValue)
                oldValue.removeFromSuperview()
            }
            if let accessoryView {
                headerStack.addArrangedSubview(accessoryView)
            }
            headerAccessoryView = accessoryView
        }
    }

    /// On macOS 26+ tints the underlying Liquid Glass material. On older systems
    /// it tints the fallback card background.
    var tintColor: NSColor? {
        didSet {
            if #available(macOS 26.0, *), let glass = glassWrapper as? NSGlassEffectView {
                glass.tintColor = tintColor
            } else {
                card.layer?.backgroundColor = (tintColor?.withAlphaComponent(0.18)
                    ?? NSColor.controlBackgroundColor).cgColor
            }
        }
    }

    init(title: String?) {
        if let title {
            let label = NSTextField(labelWithString: title)
            label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            label.textColor = .labelColor
            titleLabel = label
        } else {
            titleLabel = nil
        }

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 16
            glassWrapper = glass
        } else {
            let fallback = NSView()
            fallback.wantsLayer = true
            fallback.layer?.cornerRadius = 12
            fallback.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            fallback.layer?.borderColor = NSColor.separatorColor.cgColor
            fallback.layer?.borderWidth = 0.5
            glassWrapper = fallback
        }

        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        glassWrapper.translatesAutoresizingMaskIntoConstraints = false
        card.translatesAutoresizingMaskIntoConstraints = false

        addSubview(glassWrapper)

        if #available(macOS 26.0, *), let glass = glassWrapper as? NSGlassEffectView {
            glass.contentView = card
        } else {
            glassWrapper.addSubview(card)
            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: glassWrapper.leadingAnchor),
                card.trailingAnchor.constraint(equalTo: glassWrapper.trailingAnchor),
                card.topAnchor.constraint(equalTo: glassWrapper.topAnchor),
                card.bottomAnchor.constraint(equalTo: glassWrapper.bottomAnchor),
            ])
        }

        if let titleLabel {
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false

            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

            headerStack.orientation = .horizontal
            headerStack.alignment = .firstBaseline
            headerStack.spacing = 8
            headerStack.translatesAutoresizingMaskIntoConstraints = false
            headerStack.addArrangedSubview(titleLabel)
            headerStack.addArrangedSubview(spacer)

            card.addSubview(headerStack)
            card.addSubview(separator)

            NSLayoutConstraint.activate([
                headerStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
                headerStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
                headerStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),

                separator.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                separator.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                separator.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 10),
                separator.heightAnchor.constraint(equalToConstant: 1),
            ])
        }

        NSLayoutConstraint.activate([
            glassWrapper.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassWrapper.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassWrapper.topAnchor.constraint(equalTo: topAnchor),
            glassWrapper.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
