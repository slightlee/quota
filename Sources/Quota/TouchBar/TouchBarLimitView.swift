import AppKit

/// Compact two-row quota meter embedded in the Touch Bar item.
final class TouchBarLimitView: NSView {
    private let stack = NSStackView()
    private let rowViews = [LimitRowView(), LimitRowView()]
    private var state: ProviderQuotaState?

    override var intrinsicContentSize: NSSize {
        NSSize(width: 450, height: 26)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(with state: ProviderQuotaState) {
        self.state = state

        // MiMo exposes one monthly Token Plan pool. Render it as one centered
        // row and use the real plan name (e.g. "Lite") as the row title.
        if state.providerID == .mimo, let window = state.windows.first {
            rowViews[0].isHidden = false
            rowViews[1].isHidden = true
            rowViews[0].configureModel(
                text: state.identity.displayName,
                color: .labelColor,
                fontSize: 8
            )
            rowViews[0].update(
                with: window,
                title: state.identity.plan ?? window.localizedTitle
            )
            return
        }

        rowViews.forEach { $0.isHidden = false }
        // Touch Bar is a fixed two-row control; pad missing slots with "--".
        // Menu bar does not pad — it only shows real product windows.
        let rows = state.windowsForCompactDisplay()

        for (index, rowView) in rowViews.enumerated() {
            let window = rows[index]
            if index == 0 {
                rowView.configureModel(
                    text: state.identity.displayName,
                    color: .labelColor,
                    fontSize: 8
                )
            } else {
                rowView.configureModel(
                    text: state.identity.plan ?? "",
                    color: .systemBlue,
                    fontSize: 7
                )
            }
            rowView.update(with: window)
        }
    }

    func reloadLocalizedText() {
        if let state {
            update(with: state)
        } else {
            rowViews.forEach { $0.showPlaceholder(title: "--") }
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        reloadLocalizedText()

        stack.orientation = .vertical
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        rowViews.forEach { stack.addArrangedSubview($0) }
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

// MARK: - Row

private final class LimitRowView: NSView {
    private let modelLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let resetLabel = NSTextField(labelWithString: "")
    private let segments = (0..<20).map { _ in SegmentView() }
    private let segmentStack = NSStackView()

    override var intrinsicContentSize: NSSize {
        NSSize(width: 450, height: 12)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(with window: QuotaWindow, title: String? = nil) {
        guard window.isAvailable else {
            showPlaceholder(title: title ?? window.localizedTitle)
            return
        }
        titleLabel.stringValue = title ?? window.localizedTitle
        percentLabel.stringValue = "\(L.remaining)\(Int(window.remainingPercent.rounded()))%"
        resetLabel.stringValue = window.resetText

        let filledCount = Int((window.remainingPercent / 5).rounded(.toNearestOrAwayFromZero))
        let fill = QuotaColors.status(
            remainingPercent: window.remainingPercent,
            surface: .touchBar,
            role: .fill
        )
        for (index, segment) in segments.enumerated() {
            segment.isFilled = index < filledCount
            segment.fillColor = fill
        }
    }

    func configureModel(text: String, color: NSColor, fontSize: CGFloat) {
        modelLabel.stringValue = text
        modelLabel.font = .systemFont(ofSize: fontSize, weight: .semibold)
        modelLabel.textColor = color
    }

    func showPlaceholder(title: String) {
        titleLabel.stringValue = title
        percentLabel.stringValue = "\(L.remaining)--%"
        resetLabel.stringValue = "\(L.reset) --"
        let placeholderFill = QuotaColors.status(.healthy, surface: .touchBar, role: .fill)
        segments.forEach { segment in
            segment.isFilled = false
            segment.fillColor = placeholderFill
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        modelLabel.alignment = .left

        titleLabel.font = .systemFont(ofSize: 8, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .right

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 8, weight: .semibold)
        percentLabel.textColor = .labelColor
        percentLabel.alignment = .left
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        percentLabel.widthAnchor.constraint(equalToConstant: 50).isActive = true

        resetLabel.font = .monospacedDigitSystemFont(ofSize: 7, weight: .regular)
        resetLabel.textColor = .secondaryLabelColor

        segmentStack.orientation = .horizontal
        segmentStack.distribution = .fillEqually
        segmentStack.spacing = 1
        segments.forEach { segmentStack.addArrangedSubview($0) }

        let rightStack = NSStackView(views: [percentLabel, resetLabel])
        rightStack.orientation = .horizontal
        rightStack.spacing = 1

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: 32).isActive = true

        for view in [spacer, modelLabel, titleLabel, segmentStack, rightStack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            spacer.leadingAnchor.constraint(equalTo: leadingAnchor),
            spacer.centerYAnchor.constraint(equalTo: centerYAnchor),

            modelLabel.leadingAnchor.constraint(equalTo: spacer.leadingAnchor),
            modelLabel.trailingAnchor.constraint(equalTo: spacer.trailingAnchor),
            modelLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: spacer.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 34),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightStack.widthAnchor.constraint(equalToConstant: 106),

            segmentStack.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
            segmentStack.trailingAnchor.constraint(equalTo: rightStack.leadingAnchor, constant: -4),
            segmentStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

}

// MARK: - Segment

private final class SegmentView: NSView {
    var isFilled = false {
        didSet { needsDisplay = true }
    }

    var fillColor = QuotaColors.status(.healthy, surface: .touchBar, role: .fill) {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 1), xRadius: 2, yRadius: 2)
        (isFilled ? fillColor : NSColor.separatorColor.withAlphaComponent(0.35)).setFill()
        path.fill()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 6).isActive = true
    }
}
