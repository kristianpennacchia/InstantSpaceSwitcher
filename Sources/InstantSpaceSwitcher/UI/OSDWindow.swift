import AppKit

final class OSDWindow {
  static let shared = OSDWindow()

  private var window: NSWindow?
  private var label: NSTextField?
  private var symbolView: NSImageView?
  private var symbolWidthConstraint: NSLayoutConstraint?
  private var symbolHeightConstraint: NSLayoutConstraint?
  private var contentStack: NSStackView?
  private var visualEffect: NSVisualEffectView?
  private var hideTimer: Timer?

  private init() {}

  func show(message: String, symbolName: String? = nil) {
    guard UserDefaults.standard.bool(forKey: "showOSD") else { return }

    hideTimer?.invalidate()
    hideTimer = nil

    if window == nil {
      createWindow()
    }

    guard let window = window, let label = label, let symbolView = symbolView else { return }

    let labelFont = font(for: message)
    label.stringValue = message
    label.font = labelFont

    let symbolDimension = symbolDimension(for: labelFont)
    symbolWidthConstraint?.constant = symbolDimension
    symbolHeightConstraint?.constant = symbolDimension
    symbolView.image = SpaceLabelFormatter.symbolImage(
      forSymbolName: symbolName,
      pointSize: symbolDimension,
      weight: .semibold
    )
    symbolView.isHidden = symbolView.image == nil
    resizeWindow(for: message)

    // Position on cursor's screen
    let mouseLocation = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
    if let screen = screen {
      let screenFrame = screen.visibleFrame
      let windowFrame = window.frame
      let x = screenFrame.midX - windowFrame.width / 2
      let y = screenFrame.midY - windowFrame.height / 2
      window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    window.alphaValue = 1.0
    window.orderFrontRegardless()

    let durationMs = UserDefaults.standard.object(forKey: "osdDurationMs") as? Int ?? 500
    let duration = Double(durationMs) / 1000.0
    hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
      self?.hide()
    }
  }

  private func createWindow() {
    let defaultSize = NSSize(width: 140, height: 140)

    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: defaultSize),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.level = .statusBar
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]
    window.ignoresMouseEvents = true
    window.hidesOnDeactivate = false

    // Use vibrancy for native macOS look
    let visualEffect = NSVisualEffectView(frame: NSRect(origin: .zero, size: defaultSize))
    visualEffect.material = .hudWindow
    visualEffect.state = .active
    visualEffect.autoresizingMask = [.width, .height]
    visualEffect.wantsLayer = true
    visualEffect.layer?.cornerRadius = 18
    visualEffect.layer?.masksToBounds = true

    let label = NSTextField(labelWithString: "")
    label.font = font(for: "")
    label.textColor = .labelColor
    label.alignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    label.drawsBackground = false
    label.isBordered = false
    label.isEditable = false
    label.cell?.lineBreakMode = .byTruncatingTail

    let symbolView = NSImageView()
    symbolView.contentTintColor = .labelColor
    symbolView.imageScaling = .scaleProportionallyUpOrDown
    symbolView.translatesAutoresizingMaskIntoConstraints = false
    symbolView.isHidden = true

    let contentStack = NSStackView(views: [symbolView, label])
    contentStack.orientation = .horizontal
    contentStack.alignment = .centerY
    contentStack.spacing = 12
    contentStack.translatesAutoresizingMaskIntoConstraints = false

    visualEffect.addSubview(contentStack)
    window.contentView = visualEffect

    let symbolWidthConstraint = symbolView.widthAnchor.constraint(equalToConstant: 30)
    let symbolHeightConstraint = symbolView.heightAnchor.constraint(equalToConstant: 30)

    NSLayoutConstraint.activate([
      symbolWidthConstraint,
      symbolHeightConstraint,
      contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: visualEffect.leadingAnchor, constant: 24),
      contentStack.trailingAnchor.constraint(
        lessThanOrEqualTo: visualEffect.trailingAnchor, constant: -24),
      contentStack.topAnchor.constraint(greaterThanOrEqualTo: visualEffect.topAnchor, constant: 20),
      contentStack.bottomAnchor.constraint(
        lessThanOrEqualTo: visualEffect.bottomAnchor, constant: -20),
      contentStack.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
      contentStack.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
    ])

    self.window = window
    self.label = label
    self.symbolView = symbolView
    self.symbolWidthConstraint = symbolWidthConstraint
    self.symbolHeightConstraint = symbolHeightConstraint
    self.contentStack = contentStack
    self.visualEffect = visualEffect
  }

  private func hide() {
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.2
      window?.animator().alphaValue = 0.0
    })
  }

  private func resizeWindow(for message: String) {
    guard let window, let contentStack else { return }

    let minimumSize: NSSize = message.count <= 2
      ? NSSize(width: 140, height: 140)
      : NSSize(width: 180, height: 100)
    contentStack.layoutSubtreeIfNeeded()
    let stackSize = contentStack.fittingSize
    let contentSize = NSSize(
      width: max(minimumSize.width, ceil(stackSize.width) + 48),
      height: max(minimumSize.height, ceil(stackSize.height) + 40)
    )

    window.setContentSize(contentSize)
    visualEffect?.frame = NSRect(origin: .zero, size: contentSize)
  }

  private func font(for message: String) -> NSFont {
    switch message.count {
    case ...2:
      return NSFont.systemFont(ofSize: 48, weight: .medium)
    case ...10:
      return NSFont.systemFont(ofSize: 28, weight: .semibold)
    default:
      return NSFont.systemFont(ofSize: 22, weight: .semibold)
    }
  }

  private func symbolDimension(for font: NSFont) -> CGFloat {
    max(28, ceil(font.pointSize * 1.1))
  }
}
