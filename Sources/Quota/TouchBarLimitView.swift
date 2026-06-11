import AppKit

final class TouchBarLimitView: NSView {
    private let stack = NSStackView()
    private let fiveHourRow = LimitRowView()
    private let weeklyRow = LimitRowView()

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

    func update(with state: RateLimitDisplayState) {
        fiveHourRow.update(with: state.fiveHour)
        weeklyRow.update(with: state.weekly)
    }

    func configureModel(_ model: String, plan: String) {
        fiveHourRow.configureModel(text: model, color: .labelColor, fontSize: 8)
        weeklyRow.configureModel(text: plan, color: .systemBlue, fontSize: 7)
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        fiveHourRow.showPlaceholder(title: "5小时")
        weeklyRow.showPlaceholder(title: "周限额")

        stack.orientation = .vertical
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(fiveHourRow)
        stack.addArrangedSubview(weeklyRow)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

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

    func update(with window: LimitWindowDisplay) {
        titleLabel.stringValue = window.title
        percentLabel.stringValue = "剩余\(Int(window.remainingPercent.rounded()))%"
        resetLabel.stringValue = window.resetText

        let filledCount = Int((window.remainingPercent / 5).rounded(.toNearestOrAwayFromZero))
        for (index, segment) in segments.enumerated() {
            segment.isFilled = index < filledCount
            segment.fillColor = color(for: window.remainingPercent)
        }
    }

    func configureModel(text: String, color: NSColor, fontSize: CGFloat) {
        modelLabel.stringValue = text
        modelLabel.font = .systemFont(ofSize: fontSize, weight: .semibold)
        modelLabel.textColor = color
    }

    func showPlaceholder(title: String) {
        titleLabel.stringValue = title
        percentLabel.stringValue = "剩余--%"
        resetLabel.stringValue = "重置 --"
        segments.forEach { segment in
            segment.isFilled = false
            segment.fillColor = .systemGreen
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 12).isActive = true

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

        for v in [spacer, modelLabel, titleLabel, segmentStack, rightStack] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
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
            segmentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func color(for remainingPercent: Double) -> NSColor {
        switch remainingPercent {
        case 0..<20:
            return .systemRed
        case 20..<45:
            return .systemOrange
        default:
            return .systemGreen
        }
    }
}

private final class SegmentView: NSView {
    var isFilled = false {
        didSet { needsDisplay = true }
    }

    var fillColor = NSColor.systemGreen {
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
