import Cocoa

// Optional price overlay for Macs with a physical display notch.
@MainActor
final class NotchOverlay {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let view = NotchView()
    weak var owner: AppDelegate?
    var screen: NSScreen?
    var notchWidth: CGFloat = 180
    var topHeight: CGFloat = 32
    let compactWidth: CGFloat = 96
    var expanded = false
    var visible = false
    var closeWork: DispatchWorkItem?
    var screenObserver: NSObjectProtocol?
    var supported: Bool { notchWidth > 0 && screen?.auxiliaryTopLeftArea != nil && screen?.auxiliaryTopRightArea != nil }

    init(owner: AppDelegate) {
        self.owner = owner
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        view.overlay = self
        view.settings.target = self
        view.settings.action = #selector(settings)
        view.restore.target = self
        view.restore.action = #selector(restore)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.position() }
        }
        position()
    }
    func setVisible(_ enabled: Bool) {
        visible = enabled && supported
        closeWork?.cancel()
        expanded = false
        if visible { position(); if supported { panel.orderFrontRegardless() } else { visible = false; panel.orderOut(nil) } }
        else { panel.orderOut(nil) }
    }
    func position() {
        screen = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil }) ?? NSScreen.main
        guard let screen else { panel.orderOut(nil); return }
        var center = screen.frame.midX
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = max(0, right.minX - left.maxX)
            center = (left.maxX + right.minX) / 2
            topHeight = max(28, screen.safeAreaInsets.top)
            owner?.notchCheckbox.isEnabled = notchWidth > 0
        } else {
            let shouldRestoreMenuBar = visible
            notchWidth = 0
            topHeight = 30
            panel.orderOut(nil)
            owner?.notchCheckbox.isEnabled = false
            if shouldRestoreMenuBar { visible = false; owner?.setNotchEnabled(false) }
            return
        }
        let width = expanded ? min(screen.frame.width - 24, max(410, notchWidth + 310)) : notchWidth + compactWidth
        // In compact mode the extra width sits to the left of the physical notch.
        let originX = expanded ? center - width / 2 : center - notchWidth / 2 - compactWidth
        let height = expanded ? topHeight + 206 : topHeight
        view.notchWidth = notchWidth
        view.topHeight = topHeight
        panel.setFrame(NSRect(x: originX, y: screen.frame.maxY - height, width: width, height: height), display: true)
        view.settings.isHidden = !expanded
        view.restore.isHidden = !expanded
        view.settings.frame = NSRect(x: 18, y: height - 44, width: 166, height: 28)
        view.restore.frame = NSRect(x: width - 210, y: height - 44, width: 192, height: 28)
        update()
    }
    func update() {
        guard let owner else { return }
        view.stock = owner.selected?.displayName ?? L("주식")
        view.price = owner.status.button?.title ?? "—"
        view.compactPrice = (owner.lastQuote?.formatted ?? "—") + (owner.quoteFailed ? " ⚠" : "")
        view.summary = owner.status.button?.toolTip ?? L("종목을 검색하고 선택하세요")
        view.settings.title = AppLanguage.code == "ko" ? "종목 · 표시 설정" : "Stock & display settings"
        view.restore.title = AppLanguage.code == "ko" ? "메뉴바에 표시" : "Show in menu bar"
        view.toolTip = view.summary
        view.needsDisplay = true
    }
    func enter() {
        closeWork?.cancel()
        guard visible, !expanded else { return }
        expanded = true
        position()
    }
    func leave() {
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.visible, self.owner?.popover.isShown != true, !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.expanded = false
            self.position()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    @objc func settings() { owner?.toggle() }
    @objc func restore() { owner?.setNotchEnabled(false) }
    func stop() {
        closeWork?.cancel()
        if let observer = screenObserver { NotificationCenter.default.removeObserver(observer) }
        screenObserver = nil
        panel.orderOut(nil)
    }
    func smoke() {
        let wasEnabled = owner?.notchEnabled ?? true
        owner?.setNotchEnabled(true)
        enter()
        precondition(panel.isVisible && panel.frame.width > notchWidth)
        precondition(view.settings.frame.maxY <= view.bounds.height)
        precondition(panel.frame.maxY == screen?.frame.maxY)
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { preconditionFailure() }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/smtm-notch-preview.png"))
        print("NOTCH_OK: notch=\(notchWidth), top=\(topHeight), panel=\(panel.frame)")
        owner?.toggle()
        precondition(owner?.popover.isShown == true, "Settings should open from the notch")
        owner?.popover.performClose(nil)
        expanded = false
        position()
        precondition(panel.frame.height == topHeight)
        precondition(view.compactPrice == (owner?.lastQuote?.formatted ?? "—") + (owner?.quoteFailed == true ? " ⚠" : ""))
        precondition(view.compactPriceRect.maxX <= view.bounds.width - notchWidth, "Compact price must stay left of the notch")
        if let compact = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: compact)
            try? compact.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/smtm-notch-compact.png"))
        }
        owner?.setNotchEnabled(false)
        precondition(!panel.isVisible && owner?.status.isVisible == true)
        owner?.toggle()
        precondition(owner?.popover.isShown == true, "Menu bar settings should reopen")
        owner?.popover.performClose(nil)
        owner?.setNotchEnabled(true)
        precondition(panel.isVisible && owner?.status.isVisible == false)
        owner?.setNotchEnabled(wasEnabled)
        print("MODE_OK: price-only notch and two-way menu bar switching")
        NSApp.terminate(nil)
    }
}

@MainActor
final class NotchView: NSView {
    weak var overlay: NotchOverlay?
    var notchWidth: CGFloat = 180
    var topHeight: CGFloat = 32
    var stock = ""
    var price = "—"
    var compactPrice = "—"
    var summary = ""
    let settings = NSButton(title: "", target: nil, action: nil)
    let restore = NSButton(title: "", target: nil, action: nil)
    var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .darkAqua)
        for button in [settings, restore] {
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 11)
            addSubview(button)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) { overlay?.enter() }
    override func mouseExited(with event: NSEvent) { overlay?.leave() }
    override func mouseDown(with event: NSEvent) { overlay?.settings() }
    override func draw(_ dirtyRect: NSRect) {
        if overlay?.expanded == true {
            NSColor.black.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
            NSRect(x: 0, y: 0, width: bounds.width, height: 12).fill()
        }
        func text(_ value: String, _ rect: NSRect, size: CGFloat, color: NSColor, alignment: NSTextAlignment = .left) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = .byTruncatingTail
            (value as NSString).draw(in: rect, withAttributes: [.font:NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium), .foregroundColor:color, .paragraphStyle:paragraph])
        }
        let compactColor = overlay?.expanded == true ? NSColor.white : NSColor(calibratedWhite: 0.76, alpha: 0.92)
        text(compactPrice, compactPriceRect, size: overlay?.expanded == true ? 11 : 10, color: compactColor, alignment: .right)
        guard overlay?.expanded == true else { return }
        text(stock,
             NSRect(x: 18, y: topHeight + 12, width: bounds.width - 36, height: 18), size: 10, color: .gray)
        text(price, NSRect(x: 18, y: topHeight + 37, width: bounds.width - 36, height: 34), size: 23, color: .white)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        (summary as NSString).draw(in: NSRect(x: 18, y: topHeight + 79, width: bounds.width - 36, height: 79), withAttributes: [.font:NSFont.systemFont(ofSize: 10), .foregroundColor:NSColor.lightGray, .paragraphStyle:paragraph])
    }
    var compactPriceRect: NSRect {
        let notchLeft = overlay?.expanded == true ? (bounds.width - notchWidth) / 2 : bounds.width - notchWidth
        let left = max(6, notchLeft - 90)
        return NSRect(x: left, y: (topHeight - 14) / 2, width: max(0, notchLeft - left - 6), height: 16)
    }
}
