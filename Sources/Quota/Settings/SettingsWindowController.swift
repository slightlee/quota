import AppKit

// MARK: - Constants

private enum Layout {
    static let windowWidth: CGFloat = 480
    static let windowHeight: CGFloat = 320
    static let padding: CGFloat = 24
    static let labelWidth: CGFloat = 76
    static let rowSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 14
}

// MARK: - SettingsWindowController

final class SettingsWindowController: NSWindowController {
    private let proxyStore: ProxySettingsStore
    private let hotkeyStore: HotkeySettingsStore
    private let languageStore: LanguageSettingsStore
    private let onSave: (ProxyConfiguration, HotkeyConfiguration, AppLanguagePreference) -> Void
    private let rootViewController: SettingsViewController

    init(
        proxyStore: ProxySettingsStore,
        hotkeyStore: HotkeySettingsStore,
        languageStore: LanguageSettingsStore,
        onSave: @escaping (ProxyConfiguration, HotkeyConfiguration, AppLanguagePreference) -> Void
    ) {
        self.proxyStore = proxyStore
        self.hotkeyStore = hotkeyStore
        self.languageStore = languageStore
        self.onSave = onSave
        self.rootViewController = SettingsViewController()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L.settings
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = rootViewController

        super.init(window: window)

        rootViewController.configure(
            proxyConfiguration: proxyStore.configuration,
            hotkeyConfiguration: hotkeyStore.configuration,
            languagePreference: languageStore.preference,
            onSave: { [weak self] proxyConfig, hotkeyConfig, languagePreference in
                guard let self else { return }
                self.proxyStore.configuration = proxyConfig
                self.hotkeyStore.configuration = hotkeyConfig
                self.languageStore.preference = languagePreference
                self.onSave(proxyConfig, hotkeyConfig, languagePreference)
            },
            onCancel: { [weak self] in
                self?.window?.close()
            }
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        rootViewController.loadViewIfNeeded()
        rootViewController.reload(
            proxyConfiguration: proxyStore.configuration,
            hotkeyConfiguration: hotkeyStore.configuration,
            languagePreference: languageStore.preference
        )
        window?.title = L.settings
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SettingsViewController

private final class SettingsViewController: NSViewController {
    // Tab
    private let tabControl = NSSegmentedControl(labels: ["", "", ""], trackingMode: .selectOne, target: nil, action: nil)
    private let proxyContainer = NSView()
    private let hotkeyContainer = NSView()
    private let languageContainer = NSView()
    // Proxy
    private let modeControl = NSSegmentedControl(labels: ["", "", ""], trackingMode: .selectOne, target: nil, action: nil)
    private let proxyURLField = NSTextField(string: "")
    private let helperLabel = NSTextField(labelWithString: "")
    private let proxySubtitleLabel = NSTextField(labelWithString: "")
    private let proxyModeLabel = NSTextField(labelWithString: "")
    private let proxyAddressLabel = NSTextField(labelWithString: "")
    // Hotkey
    private let keyRecorder = KeyRecorderView()
    private let hotkeyToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let hotkeySubtitleLabel = NSTextField(labelWithString: "")
    private let openMenuLabel = NSTextField(labelWithString: "")
    // Language
    private let languagePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let languageSubtitleLabel = NSTextField(labelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    // Buttons
    private let saveButton = NSButton(title: "", target: nil, action: nil)
    private let cancelButton = NSButton(title: "", target: nil, action: nil)

    private var onSave: ((ProxyConfiguration, HotkeyConfiguration, AppLanguagePreference) -> Void)?
    private var onCancel: (() -> Void)?

    private var pendingHotkeyCode: UInt32 = 0
    private var pendingHotkeyModifiers: UInt32 = 0

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.windowHeight))
        setupUI()
    }

    func configure(
        proxyConfiguration: ProxyConfiguration,
        hotkeyConfiguration: HotkeyConfiguration,
        languagePreference: AppLanguagePreference,
        onSave: @escaping (ProxyConfiguration, HotkeyConfiguration, AppLanguagePreference) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onCancel = onCancel
        reload(
            proxyConfiguration: proxyConfiguration,
            hotkeyConfiguration: hotkeyConfiguration,
            languagePreference: languagePreference
        )
    }

    func reload(
        proxyConfiguration: ProxyConfiguration,
        hotkeyConfiguration: HotkeyConfiguration,
        languagePreference: AppLanguagePreference
    ) {
        guard isViewLoaded else { return }
        selectLanguagePreference(languagePreference)

        applyLocalizedText()
        modeControl.selectedSegment = ProxyMode.allCases.firstIndex(of: proxyConfiguration.mode) ?? 0
        proxyURLField.stringValue = proxyConfiguration.proxyURL
        updateVisibility()

        pendingHotkeyCode = hotkeyConfiguration.keyCode
        pendingHotkeyModifiers = hotkeyConfiguration.modifiers
        hotkeyToggle.state = hotkeyConfiguration.isEnabled ? .on : .off
        keyRecorder.configure(displayString: hotkeyConfiguration.displayString)
    }

    // MARK: - UI Construction

    private func setupUI() {
        // ── Tab switcher ──
        tabControl.selectedSegment = 0
        tabControl.target = self
        tabControl.action = #selector(tabChanged)

        // ── Proxy tab content ──
        setupProxyTab()
        proxyContainer.translatesAutoresizingMaskIntoConstraints = false

        // ── Hotkey tab content ──
        setupHotkeyTab()
        hotkeyContainer.translatesAutoresizingMaskIntoConstraints = false
        hotkeyContainer.isHidden = true

        // ── Language tab content ──
        setupLanguageTab()
        languageContainer.translatesAutoresizingMaskIntoConstraints = false
        languageContainer.isHidden = true

        // ── Button row ──
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save)

        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttonRow = NSStackView(views: [spacer, cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY

        // ── Root layout ──
        let rootStack = NSStackView(views: [tabControl, proxyContainer, hotkeyContainer, languageContainer, buttonRow])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = Layout.sectionSpacing
        rootStack.edgeInsets = NSEdgeInsets(
            top: Layout.padding,
            left: Layout.padding,
            bottom: Layout.padding,
            right: Layout.padding
        )

        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            proxyContainer.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor, constant: Layout.padding),
            proxyContainer.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor, constant: -Layout.padding),
            hotkeyContainer.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor, constant: Layout.padding),
            hotkeyContainer.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor, constant: -Layout.padding),
            languageContainer.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor, constant: Layout.padding),
            languageContainer.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor, constant: -Layout.padding),
            tabControl.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor, constant: Layout.padding),
        ])

        applyLocalizedText()
        updateVisibility()
    }

    private func setupProxyTab() {
        proxySubtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        proxySubtitleLabel.textColor = .secondaryLabelColor

        configureLabel(proxyModeLabel)
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        let modeRow = makeRow(label: proxyModeLabel, control: modeControl)

        configureLabel(proxyAddressLabel)
        proxyURLField.placeholderString = "http://127.0.0.1:7890"
        proxyURLField.target = self
        proxyURLField.action = #selector(valueChanged)
        let proxyRow = makeRow(label: proxyAddressLabel, control: proxyURLField)

        helperLabel.font = .systemFont(ofSize: 11, weight: .regular)
        helperLabel.textColor = .secondaryLabelColor
        helperLabel.maximumNumberOfLines = 0
        helperLabel.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [proxySubtitleLabel, modeRow, proxyRow, helperLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Layout.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        proxyContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: proxyContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: proxyContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: proxyContainer.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: proxyContainer.bottomAnchor),
        ])
    }

    private func setupHotkeyTab() {
        hotkeySubtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        hotkeySubtitleLabel.textColor = .secondaryLabelColor

        hotkeyToggle.target = self
        hotkeyToggle.action = #selector(hotkeyToggleChanged)

        keyRecorder.onChange = { [weak self] keyCode, modifiers in
            self?.pendingHotkeyCode = keyCode
            self?.pendingHotkeyModifiers = modifiers
        }
        keyRecorder.onClear = { [weak self] in
            self?.pendingHotkeyCode = 0
            self?.pendingHotkeyModifiers = 0
        }

        configureLabel(openMenuLabel)
        let toggleRow = makeRow(label: openMenuLabel, control: keyRecorder)

        let stack = NSStackView(views: [hotkeySubtitleLabel, hotkeyToggle, toggleRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Layout.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        hotkeyContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: hotkeyContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: hotkeyContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: hotkeyContainer.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: hotkeyContainer.bottomAnchor),
            keyRecorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
    }

    private func setupLanguageTab() {
        languageSubtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        languageSubtitleLabel.textColor = .secondaryLabelColor

        configureLabel(languageLabel)
        languagePopUp.translatesAutoresizingMaskIntoConstraints = false
        let languageRow = makeRow(label: languageLabel, control: languagePopUp)

        let stack = NSStackView(views: [languageSubtitleLabel, languageRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Layout.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        languageContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: languageContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: languageContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: languageContainer.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: languageContainer.bottomAnchor),
            languagePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
    }

    private func configureLabel(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.widthAnchor.constraint(equalToConstant: Layout.labelWidth).isActive = true
        label.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func makeRow(label: NSView, control: NSView) -> NSStackView {
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Layout.rowSpacing
        return row
    }

    // MARK: - Tab Switching

    @objc private func tabChanged() {
        proxyContainer.isHidden = tabControl.selectedSegment != 0
        hotkeyContainer.isHidden = tabControl.selectedSegment != 1
        languageContainer.isHidden = tabControl.selectedSegment != 2
    }

    // MARK: - Logic

    private func currentProxyConfiguration() -> ProxyConfiguration {
        let mode = ProxyMode.allCases[safe: modeControl.selectedSegment] ?? .automatic
        return ProxyConfiguration(mode: mode, proxyURL: proxyURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func currentHotkeyConfiguration() -> HotkeyConfiguration {
        return HotkeyConfiguration(
            keyCode: pendingHotkeyCode,
            modifiers: pendingHotkeyModifiers,
            isEnabled: hotkeyToggle.state == .on
        )
    }

    private func currentLanguagePreference() -> AppLanguagePreference {
        AppLanguagePreference.allCases[safe: languagePopUp.indexOfSelectedItem] ?? .system
    }

    private func applyLocalizedText() {
        tabControl.setLabel(L.proxy, forSegment: 0)
        tabControl.setLabel(L.hotkey, forSegment: 1)
        tabControl.setLabel(L.languageTitle, forSegment: 2)

        for (index, mode) in ProxyMode.allCases.enumerated() {
            modeControl.setLabel(L.proxyModeTitle(mode), forSegment: index)
        }

        reloadLanguageMenu()

        proxySubtitleLabel.stringValue = L.proxySubtitle
        proxyModeLabel.stringValue = L.proxyMode
        proxyAddressLabel.stringValue = L.proxyAddress

        hotkeySubtitleLabel.stringValue = L.hotkeySubtitle
        hotkeyToggle.title = L.enableGlobalHotkey
        openMenuLabel.stringValue = L.openMenu

        languageSubtitleLabel.stringValue = L.languageSubtitle
        languageLabel.stringValue = L.languageTitle

        saveButton.title = L.save
        cancelButton.title = L.cancel
    }

    private func updateVisibility() {
        let configuration = currentProxyConfiguration()
        let isManual = configuration.mode == .manual
        proxyURLField.isEnabled = isManual
        proxyURLField.alphaValue = isManual ? 1.0 : 0.45
        helperLabel.stringValue = isManual
            ? L.proxyManualHelp
            : L.proxyAutomaticHelp
    }

    @objc private func modeChanged() {
        updateVisibility()
    }

    @objc private func valueChanged() {}

    @objc private func hotkeyToggleChanged() {
        let enabled = hotkeyToggle.state == .on
        if enabled && pendingHotkeyCode == 0 {
            view.window?.makeFirstResponder(keyRecorder)
        }
    }

    private func selectLanguagePreference(_ preference: AppLanguagePreference) {
        let index = AppLanguagePreference.allCases.firstIndex(of: preference) ?? 0
        languagePopUp.selectItem(at: index)
    }

    private func reloadLanguageMenu() {
        let selectedPreference = currentLanguagePreference()
        languagePopUp.removeAllItems()
        AppLanguagePreference.allCases.forEach { preference in
            languagePopUp.addItem(withTitle: L.languagePreferenceTitle(preference))
        }
        selectLanguagePreference(selectedPreference)
    }

    @objc private func save() {
        let proxyConfig = currentProxyConfiguration()
        if proxyConfig.mode == .manual {
            guard Self.isValidProxyURL(proxyConfig.proxyURL) else {
                presentValidationError()
                return
            }
        }

        let hotkeyConfig = currentHotkeyConfiguration()
        if hotkeyConfig.isEnabled {
            guard hotkeyConfig.isValid else {
                presentHotkeyValidationError()
                return
            }
        }

        onSave?(proxyConfig, hotkeyConfig, currentLanguagePreference())
        view.window?.close()
    }

    @objc private func cancel() {
        onCancel?()
    }

    private func presentValidationError() {
        let alert = NSAlert()
        alert.messageText = L.invalidProxyTitle
        alert.informativeText = L.invalidProxyMessage
        alert.alertStyle = .warning
        if let window = view.window ?? NSApp.keyWindow {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
        }
    }

    private func presentHotkeyValidationError() {
        let alert = NSAlert()
        alert.messageText = L.invalidHotkeyTitle
        alert.informativeText = L.invalidHotkeyMessage
        alert.alertStyle = .warning
        if let window = view.window ?? NSApp.keyWindow {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
        }
    }

    private static func isValidProxyURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value), let scheme = components.scheme, let host = components.host, !scheme.isEmpty, !host.isEmpty else {
            return false
        }
        return true
    }
}

// MARK: - Utils

private extension Array {
    subscript(safe index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
