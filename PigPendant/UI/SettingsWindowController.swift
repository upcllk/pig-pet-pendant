import AppKit
import Foundation

final class SettingsBackgroundView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath.fill(dirtyRect)
    }
}

final class SettingsWindowController: NSWindowController {
    let model: PendantCoordinator
    let visibility = NSButton(checkboxWithTitle: "显示小猪", target: nil, action: nil)
    let countStepper = NSStepper()
    let countReadout = NSTextField(labelWithString: "")
    let countRow = NSStackView()
    private(set) var ghostOffsetRows: [GhostOffsetRow] = []
    let bambooPositionRow = NSStackView()
    let bambooPositionSlider = NSSlider(value: BambooPigPosition.defaultValue,
                                        minValue: BambooPigPosition.range.lowerBound,
                                        maxValue: BambooPigPosition.range.upperBound,
                                        target: nil, action: nil)
    let bambooPositionReadout = NSTextField(labelWithString: "")
    let modeControl = NSSegmentedControl(labels: DisplayMode.allCases.map(\.title),
                                                trackingMode: .selectOne, target: nil, action: nil)
    let image = NSImageView()
    struct ParameterRow {
        let parameter: ParameterID
        let row: NSStackView
        let label: NSTextField
        let slider: NSSlider
        let readout: NSTextField
    }
    struct GhostOffsetRow {
        let axis: GhostOffsetAxis
        let row: NSStackView
        let slider: NSSlider
        let readout: NSTextField
    }
    private(set) var parameterRows: [ParameterRow] = []
    private(set) var advancedHeading: NSTextField?

    init(model: PendantCoordinator) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 510),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "猪猪挂件设置"
        window.isReleasedWhenClosed = false
        window.contentView = SettingsBackgroundView(frame: NSRect(x: 0, y: 0, width: 480, height: 510))
        super.init(window: window)
        window.center()
        buildContent()
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        image.image = model.displayImage
        image.imageScaling = .scaleProportionallyUpOrDown
        image.setAccessibilityLabel("小猪")
        image.widthAnchor.constraint(equalToConstant: 52).isActive = true
        image.heightAnchor.constraint(equalToConstant: 46).isActive = true
        let title = NSTextField(labelWithString: "猪猪挂件")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        let header = NSStackView(views: [image, title])
        header.spacing = 12
        visibility.target = self
        visibility.action = #selector(toggleVisibility)
        modeControl.target = self
        modeControl.action = #selector(changeDisplayMode)
        modeControl.setAccessibilityLabel("挂件模式")

        let countLabel = NSTextField(labelWithString: "气球数量")
        countLabel.alignment = .right
        countLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true
        countReadout.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        countReadout.widthAnchor.constraint(equalToConstant: 44).isActive = true
        countStepper.minValue = Double(PendantSettings.countRange.lowerBound)
        countStepper.maxValue = Double(PendantSettings.countRange.upperBound)
        countStepper.increment = 1
        countStepper.valueWraps = false
        countStepper.target = self
        countStepper.action = #selector(changeBalloonCount)
        countStepper.setAccessibilityLabel("气球数量，一至八只")
        countStepper.toolTip = "气球数量，一至八只"
        countRow.addArrangedSubview(countLabel)
        countRow.addArrangedSubview(countReadout)
        countRow.addArrangedSubview(countStepper)
        countRow.spacing = 10
        countRow.heightAnchor.constraint(equalToConstant: 28).isActive = true
        var rows: [NSView] = [countRow]
        for axis in GhostOffsetAxis.allCases {
            let label = NSTextField(labelWithString: axis.title)
            label.alignment = .right
            label.widthAnchor.constraint(equalToConstant: 64).isActive = true
            let slider = NSSlider(value: model.settings[axis],
                                  minValue: GhostOffsetAxis.range.lowerBound,
                                  maxValue: GhostOffsetAxis.range.upperBound,
                                  target: self, action: #selector(changeGhostOffset(_:)))
            slider.tag = axis.rawValue
            slider.isContinuous = true
            slider.setAccessibilityLabel(axis.help)
            slider.toolTip = axis.help
            slider.widthAnchor.constraint(equalToConstant: 224).isActive = true
            let readout = NSTextField(labelWithString: "")
            readout.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            readout.alignment = .right
            readout.widthAnchor.constraint(equalToConstant: 78).isActive = true
            let row = NSStackView(views: [label, slider, readout])
            row.spacing = 10
            row.heightAnchor.constraint(equalToConstant: 28).isActive = true
            rows.append(row)
            ghostOffsetRows.append(GhostOffsetRow(axis: axis, row: row, slider: slider, readout: readout))
        }
        for parameter in ParameterID.allCases {
            if parameter == .gravity {
                let advanced = NSTextField(labelWithString: "高级")
                advanced.font = .systemFont(ofSize: 12, weight: .semibold)
                advanced.textColor = .secondaryLabelColor
                rows.append(advanced)
                advancedHeading = advanced
            }
            let label = NSTextField(labelWithString: parameter.title(mode: model.mode))
            label.alignment = .right
            label.widthAnchor.constraint(equalToConstant: 64).isActive = true
            let slider = NSSlider(value: model.settings[parameter], minValue: parameter.range.lowerBound, maxValue: parameter.range.upperBound,
                                  target: self, action: #selector(changeParameter(_:)))
            slider.tag = parameter.rawValue
            slider.isContinuous = true
            slider.setAccessibilityLabel(parameter.help(mode: model.mode))
            slider.toolTip = parameter.help(mode: model.mode)
            slider.widthAnchor.constraint(equalToConstant: 224).isActive = true
            let readout = NSTextField(labelWithString: "")
            readout.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            readout.alignment = .right
            readout.widthAnchor.constraint(equalToConstant: 78).isActive = true
            let row = NSStackView(views: [label, slider, readout])
            row.spacing = 10
            row.heightAnchor.constraint(equalToConstant: 28).isActive = true
            rows.append(row)
            parameterRows.append(ParameterRow(parameter: parameter, row: row,
                                              label: label, slider: slider, readout: readout))
        }
            let bambooPositionLabel = NSTextField(labelWithString: "小猪位置")
            bambooPositionLabel.alignment = .right
            bambooPositionLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true
            bambooPositionSlider.isContinuous = true
            bambooPositionSlider.target = self
            bambooPositionSlider.action = #selector(changeBambooPosition(_:))
            bambooPositionSlider.setAccessibilityLabel("小猪沿竹根到竹梢的位置")
            bambooPositionSlider.toolTip = "沿竹身的位置比例；两端保留小猪接触空间"
            bambooPositionSlider.widthAnchor.constraint(equalToConstant: 224).isActive = true
            bambooPositionReadout.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            bambooPositionReadout.alignment = .right
            bambooPositionReadout.widthAnchor.constraint(equalToConstant: 78).isActive = true
            bambooPositionRow.addArrangedSubview(bambooPositionLabel)
            bambooPositionRow.addArrangedSubview(bambooPositionSlider)
            bambooPositionRow.addArrangedSubview(bambooPositionReadout)
            bambooPositionRow.spacing = 10
            bambooPositionRow.heightAnchor.constraint(equalToConstant: 28).isActive = true
            rows.append(bambooPositionRow)
            let form = NSStackView(views: rows)
        form.orientation = .vertical
        form.detachesHiddenViews = true
        form.alignment = .leading
        form.spacing = 12
        let restore = NSButton(title: "恢复默认", target: self, action: #selector(restoreSettings))
        let done = NSButton(title: "完成", target: self, action: #selector(closeSettings))
        done.keyEquivalent = "\r"
        let spacer = NSView()
        let footer = NSStackView(views: [restore, spacer, done])
        footer.distribution = .fill
        let stack = NSStackView(views: [header, modeControl, visibility, form, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    func refresh() {
        let isBalloon = model.mode == .balloon
        let isBamboo = model.mode == .bamboo
        let isGhost = model.mode == .ghost
        let isRope = model.mode == .rope
        modeControl.selectedSegment = DisplayMode.allCases.firstIndex(of: model.mode) ?? 0
        visibility.title = model.mode.visibilityCheckboxTitle
        image.image = model.displayImage
        for row in parameterRows {
            row.row.isHidden = (isGhost && row.parameter != .size) ||
                (row.parameter == .sway && !isRope)
            row.label.stringValue = row.parameter.title(mode: model.mode)
            let help = row.parameter.help(mode: model.mode)
            row.slider.toolTip = help
            row.slider.setAccessibilityLabel(help)
            let value = model.settings[row.parameter]
            row.slider.doubleValue = value
            row.readout.stringValue = row.parameter.readout(value)
        }
        advancedHeading?.isHidden = isGhost
        countStepper.isEnabled = isBalloon
        countRow.isHidden = !isBalloon
        for row in ghostOffsetRows {
            row.row.isHidden = !isGhost
            let value = model.settings[row.axis]
            row.slider.doubleValue = value
            row.readout.stringValue = row.axis.readout(value)
        }
        bambooPositionRow.isHidden = !isBamboo
        bambooPositionSlider.doubleValue = model.settings.bambooPosition
        bambooPositionReadout.stringValue = String(format: "%.0f%%", model.settings.bambooPosition)
        countReadout.textColor = isBalloon ? .labelColor : .secondaryLabelColor
        countStepper.integerValue = model.balloonCount
        countReadout.stringValue = "\(model.balloonCount) 只"
        visibility.state = model.isVisible ? .on : .off
        if let window = window {
            let height: CGFloat = isBalloon || isBamboo || isRope ? 550 : isGhost ? 390 : 510
            if window.contentView?.frame.height != height {
                let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
                window.setContentSize(NSSize(width: 480, height: height))
                window.setFrameTopLeftPoint(topLeft)
            }
        }
    }

    @objc private func changeDisplayMode() {
        guard DisplayMode.allCases.indices.contains(modeControl.selectedSegment) else { return }
        model.changeMode(DisplayMode.allCases[modeControl.selectedSegment])
        refresh()
    }

    @objc private func changeBalloonCount() {
        model.changeCount(countStepper.integerValue)
        refresh()
    }

    @objc private func changeBambooPosition(_ sender: NSSlider) {
        model.changeBambooPosition(sender.doubleValue.rounded())
        refresh()
    }

    @objc private func changeGhostOffset(_ sender: NSSlider) {
        guard let axis = GhostOffsetAxis(rawValue: sender.tag) else {
            NSLog("Unknown ghost offset control tag=%d", sender.tag)
            return
        }
        model.changeGhostOffset(axis, value: sender.doubleValue.rounded())
        refresh()
    }

    @objc private func changeParameter(_ sender: NSSlider) {
        guard let parameter = ParameterID(rawValue: sender.tag) else {
            NSLog("Unknown settings control tag=%d", sender.tag)
            return
        }
        let value = parameter == .damping ? sender.doubleValue : sender.doubleValue.rounded()
        model.changeParameter(parameter, value: value)
        refresh()
    }

    @objc func toggleVisibility() {
        model.toggleVisible()
        refresh()
    }

    @objc func restoreSettings() {
        model.restoreDefaults()
        refresh()
    }

    @objc private func closeSettings() { close() }
}
