import AppKit

final class OSDWindow {
  static let shared = OSDWindow()

  private var window: NSWindow?
  private var label: NSTextField?
  private var visualEffect: NSVisualEffectView?
  private var hideTimer: Timer?

  private init() {}

  func show(message: String) {
    guard UserDefaults.standard.bool(forKey: "showOSD") else { return }

    hideTimer?.invalidate()
    hideTimer = nil

    if window == nil {
      createWindow()
    }

    guard let window = window, let label = label else { return }

    label.stringValue = message
    label.font = font(for: message)
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

    visualEffect.addSubview(label)
    window.contentView = visualEffect

    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(greaterThanOrEqualTo: visualEffect.leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(
        lessThanOrEqualTo: visualEffect.trailingAnchor, constant: -24),
      label.topAnchor.constraint(greaterThanOrEqualTo: visualEffect.topAnchor, constant: 20),
      label.bottomAnchor.constraint(lessThanOrEqualTo: visualEffect.bottomAnchor, constant: -20),
      label.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
    ])

    self.window = window
    self.label = label
    self.visualEffect = visualEffect
  }

  private func hide() {
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.2
      window?.animator().alphaValue = 0.0
    })
  }

  private func resizeWindow(for message: String) {
    guard let window else { return }

    let minimumSize: NSSize = message.count <= 2
      ? NSSize(width: 140, height: 140)
      : NSSize(width: 180, height: 100)
    let attributes: [NSAttributedString.Key: Any] = [.font: font(for: message)]
    let textSize = (message as NSString).size(withAttributes: attributes)
    let contentSize = NSSize(
      width: max(minimumSize.width, ceil(textSize.width) + 48),
      height: max(minimumSize.height, ceil(textSize.height) + 40)
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
}
