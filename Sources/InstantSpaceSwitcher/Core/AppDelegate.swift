import AppKit
import ApplicationServices
import Combine
import ISS

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private enum DirectSpaceSwitchSource {
    case hotkey
    case menu
    case lastSpace
  }

  private let menuBarController = MenuBarController()
  private let hotkeyStore = HotkeyStore.shared
  private let nicknameStore = SpaceNicknameStore.shared
  private lazy var preferencesWindowController = PreferencesWindowController()
  private var cancellables = Set<AnyCancellable>()
  private var spaceChangeObserver: Any?
  private var appActivationObserver: Any?
  private var currentSpaceIndex: UInt32?
  private var previousSpaceIndex: UInt32?

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleReopen),
      forEventClass: kCoreEventClass,
      andEventID: kAEReopenApplication
    )
  }

  @objc private func handleReopen(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
    preferencesWindowController.present()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    ensureAccessibilityPermission()

    if !iss_init() {
      print("Failed to initialize ISS event tap")
      retryIssInit()
    }

    if UserDefaults.standard.bool(forKey: "swipeOverride") {
      iss_set_swipe_override(true)
    }

    let gestureSpeed = UserDefaults.standard.double(forKey: "gestureSpeed")
    if gestureSpeed > 0 {
      iss_set_gesture_speed(gestureSpeed)
    }

    if UserDefaults.standard.object(forKey: "overlayDetectionEnabled") as? Bool ?? true {
      iss_set_overlay_detection_enabled(true)
    }

    iss_set_switch_callback { newSpaceIndex in
      Task { @MainActor in
        (NSApp.delegate as? AppDelegate)?.handleSpaceSwitch(to: newSpaceIndex)
      }
    }

    setupMainMenu()
    menuBarController.delegate = self
    menuBarController.setup()

    if UserDefaults.standard.bool(forKey: "hideMenuBarIcon") {
      menuBarController.setIconVisible(false)
    }

    bindHotkeys()
    observeSpaceChanges()
    observeAppActivation()
    refreshSpaceInfo()
  }

  func applicationWillTerminate(_ notification: Notification) {
    iss_destroy()
    stopObservingSpaceChanges()
    stopObservingAppActivation()
  }

  private func retryIssInit() {
    guard !iss_init() else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.retryIssInit()
    }
  }

  private func ensureAccessibilityPermission() {
    guard !AXIsProcessTrusted() else { return }

    if let bundleId = Bundle.main.bundleIdentifier {
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
      task.arguments = ["reset", "Accessibility", bundleId]
      try? task.run()
      task.waitUntilExit()
    }

    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [promptKey: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  private func setupMainMenu() {
    let mainMenu = NSMenu()

    // App menu
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)

    let appMenu = NSMenu(title: Constants.appName)
    appMenuItem.submenu = appMenu

    let aboutItem = NSMenuItem(
      title: "About", action: #selector(openAbout(_:)), keyEquivalent: "")
    aboutItem.target = self
    aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
    appMenu.addItem(aboutItem)

    appMenu.addItem(NSMenuItem.separator())

    let preferencesItem = NSMenuItem(
      title: "Settings…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
    preferencesItem.target = self
    preferencesItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
    appMenu.addItem(preferencesItem)

    appMenu.addItem(NSMenuItem.separator())

    let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
    let servicesMenu = NSMenu()
    servicesItem.submenu = servicesMenu
    NSApp.servicesMenu = servicesMenu
    appMenu.addItem(servicesItem)

    appMenu.addItem(NSMenuItem.separator())

    let hideItem = NSMenuItem(
      title: "Hide \(Constants.appName)", action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h")
    hideItem.target = NSApp
    appMenu.addItem(hideItem)

    let hideOthersItem = NSMenuItem(
      title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h")
    hideOthersItem.keyEquivalentModifierMask = [.command, .option]
    hideOthersItem.target = NSApp
    appMenu.addItem(hideOthersItem)

    let showAllItem = NSMenuItem(
      title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
      keyEquivalent: "")
    showAllItem.target = NSApp
    appMenu.addItem(showAllItem)

    appMenu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(
      title: "Quit", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    quitItem.target = NSApp
    appMenu.addItem(quitItem)

    // File menu
    let fileMenuItem = NSMenuItem()
    mainMenu.addItem(fileMenuItem)

    let fileMenu = NSMenu(title: "File")
    fileMenuItem.submenu = fileMenu

    let closeItem = NSMenuItem(
      title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    fileMenu.addItem(closeItem)

    // Edit menu
    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)

    let editMenu = NSMenu(title: "Edit")
    editMenuItem.submenu = editMenu

    let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    undoItem.target = nil
    editMenu.addItem(undoItem)

    let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    redoItem.keyEquivalentModifierMask = [.command, .shift]
    redoItem.target = nil
    editMenu.addItem(redoItem)

    editMenu.addItem(NSMenuItem.separator())

    let cutItem = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    cutItem.target = nil
    editMenu.addItem(cutItem)

    let copyItem = NSMenuItem(
      title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    copyItem.target = nil
    editMenu.addItem(copyItem)

    let pasteItem = NSMenuItem(
      title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    pasteItem.target = nil
    editMenu.addItem(pasteItem)

    let deleteItem = NSMenuItem(
      title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
    deleteItem.target = nil
    editMenu.addItem(deleteItem)

    editMenu.addItem(NSMenuItem.separator())

    let selectAllItem = NSMenuItem(
      title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    selectAllItem.target = nil
    editMenu.addItem(selectAllItem)

    NSApp.mainMenu = mainMenu
  }

  @objc private func openPreferences(_ sender: Any?) {
    preferencesWindowController.present()
  }

  @objc private func openAbout(_ sender: Any?) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(sender)
    // Ensure window comes to front if already open
    NSApp.windows.first(where: { $0.title.contains("About") })?.makeKeyAndOrderFront(nil)
  }

  private func bindHotkeys() {
    hotkeyStore.$leftHotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .left, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$rightHotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .right, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space1Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space1, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space2Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space2, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space3Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space3, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space4Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space4, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space5Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space5, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space6Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space6, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space7Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space7, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space8Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space8, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space9Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space9, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space10Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space10, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space11Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space11, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space12Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space12, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space13Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space13, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space14Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space14, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space15Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space15, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space16Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space16, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$spaceLastSpaceHotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .lastSpace, combination: $0)
    }.store(in: &cancellables)

    hotkeyStore.$enabledStates.receive(on: RunLoop.main).sink { [weak self] _ in
      guard let self = self else { return }
      for identifier in HotkeyIdentifier.allCases {
        self.registerHotkey(
          for: identifier, combination: self.hotkeyStore.combination(for: identifier))
      }
    }.store(in: &cancellables)
  }

  func setMenuBarIconVisible(_ visible: Bool) {
    menuBarController.setIconVisible(visible)
  }

  func reregisterAllHotkeys() {
    for identifier in HotkeyIdentifier.allCases {
      let combination = hotkeyStore.combination(for: identifier)
      menuBarController.applyHotkey(combination, to: identifier)
      registerHotkey(for: identifier, combination: combination)
    }
  }

  private func registerHotkey(for identifier: HotkeyIdentifier, combination: HotkeyCombination) {
    menuBarController.applyHotkey(combination, to: identifier)

    guard hotkeyStore.isEnabled(identifier) else {
      HotKeyManager.shared.unregister(identifier: identifier)
      return
    }

    HotKeyManager.shared.register(identifier: identifier, combination: combination) { [weak self] in
      guard let self else { return }
      switch identifier {
      case .left:
        self.performSpaceSwitch(ISSDirectionLeft)
      case .right:
        self.performSpaceSwitch(ISSDirectionRight)
      case .space1:
        self.performSpaceSwitchToIndex(0, source: .hotkey)
      case .space2:
        self.performSpaceSwitchToIndex(1, source: .hotkey)
      case .space3:
        self.performSpaceSwitchToIndex(2, source: .hotkey)
      case .space4:
        self.performSpaceSwitchToIndex(3, source: .hotkey)
      case .space5:
        self.performSpaceSwitchToIndex(4, source: .hotkey)
      case .space6:
        self.performSpaceSwitchToIndex(5, source: .hotkey)
      case .space7:
        self.performSpaceSwitchToIndex(6, source: .hotkey)
      case .space8:
        self.performSpaceSwitchToIndex(7, source: .hotkey)
      case .space9:
        self.performSpaceSwitchToIndex(8, source: .hotkey)
      case .space10:
        self.performSpaceSwitchToIndex(9, source: .hotkey)
      case .space11:
        self.performSpaceSwitchToIndex(10, source: .hotkey)
      case .space12:
        self.performSpaceSwitchToIndex(11, source: .hotkey)
      case .space13:
        self.performSpaceSwitchToIndex(12, source: .hotkey)
      case .space14:
        self.performSpaceSwitchToIndex(13, source: .hotkey)
      case .space15:
        self.performSpaceSwitchToIndex(14, source: .hotkey)
      case .space16:
        self.performSpaceSwitchToIndex(15, source: .hotkey)
      case .lastSpace:
        self.performSpaceLastSpace()
      }
    }
  }

  private func performSpaceSwitch(_ direction: ISSDirection) {
    // ISS reports the (prediction-aware) target via the switch callback, which updates the
    // tracked indices and shows the OSD.
    if !iss_switch(direction) {
      NSSound.beep()
      return
    }
    refreshSpaceInfo()
  }

  private func performSpaceSwitchToIndex(_ requestedIndex: UInt32, source: DirectSpaceSwitchSource) {
    let currentIndex = currentSpaceIndexFromSystem()
    if let currentIndex {
      updateTrackedSpaceIndices(withCurrentIndex: currentIndex)
    }
    let targetIndex = resolvedTargetIndex(
      requestedIndex: requestedIndex,
      currentIndex: currentIndex,
      source: source
    )

    if !iss_switch_to_index(targetIndex) {
      NSSound.beep()
      return
    }
    refreshSpaceInfo()
  }

  private func performSpaceLastSpace() {
    guard let previousSpaceIndex, previousSpaceIndex != currentSpaceIndex else {
      NSSound.beep()
      return
    }

    performSpaceSwitchToIndex(previousSpaceIndex, source: .lastSpace)
  }

  /// Called (via the ISS switch callback) after every successful switch, including trackpad
  /// swipe overrides.
  fileprivate func handleSpaceSwitch(to newSpaceIndex: UInt32) {
    updateTrackedSpaceIndices(withCurrentIndex: newSpaceIndex)
    OSDWindow.shared.show(
      message: SpaceLabelFormatter.runtimeLabel(
        for: Int(newSpaceIndex), nicknameStore: nicknameStore),
      symbolName: nicknameStore.symbolName(for: Int(newSpaceIndex)))
  }

  private func refreshSpaceInfo() {
    var info = ISSSpaceInfo()
    if iss_get_menubar_space_info(&info) {
      updateTrackedSpaceIndices(withCurrentIndex: info.currentIndex)
      menuBarController.updateWithSpaceInfo(info)
    } else {
      if let currentIndex = currentSpaceIndexFromSystem() {
        updateTrackedSpaceIndices(withCurrentIndex: currentIndex)
      }
      menuBarController.updateWithSpaceInfo(nil)
    }
  }

  private func currentSpaceIndexFromSystem() -> UInt32? {
    var info = ISSSpaceInfo()
    guard iss_get_space_info(&info) else { return nil }
    return info.currentIndex
  }

  private func resolvedTargetIndex(
    requestedIndex: UInt32,
    currentIndex: UInt32?,
    source: DirectSpaceSwitchSource
  ) -> UInt32 {
    guard
      source == .hotkey,
      UserDefaults.standard.object(
        forKey: PreferenceKey.repeatDirectSpaceHotkeyReturnsToPreviousSpace
      ) as? Bool ?? false,
      currentIndex == requestedIndex,
      let previousSpaceIndex,
      previousSpaceIndex != requestedIndex
    else {
      return requestedIndex
    }

    return previousSpaceIndex
  }

  private func updateTrackedSpaceIndices(withCurrentIndex newCurrentIndex: UInt32) {
    guard currentSpaceIndex != newCurrentIndex else { return }
    previousSpaceIndex = currentSpaceIndex
    currentSpaceIndex = newCurrentIndex
  }

  private func observeSpaceChanges() {
    stopObservingSpaceChanges()
    spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.refreshSpaceInfo()
        iss_reset_predictions()
        self.menuBarController.scheduleRefresh(after: 0.2)
      }
    }
  }

  private func stopObservingSpaceChanges() {
    if let observer = spaceChangeObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      spaceChangeObserver = nil
    }
  }

  private func observeAppActivation() {
    stopObservingAppActivation()
    appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.menuBarController.scheduleRefresh(after: 0.1)
      }
    }
  }

  private func stopObservingAppActivation() {
    if let observer = appActivationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      appActivationObserver = nil
    }
  }

}

extension AppDelegate: MenuBarControllerDelegate {
  func menuBarControllerDidRequestSwitchLeft(_ controller: MenuBarController) {
    performSpaceSwitch(ISSDirectionLeft)
  }

  func menuBarControllerDidRequestSwitchRight(_ controller: MenuBarController) {
    performSpaceSwitch(ISSDirectionRight)
  }

  func menuBarControllerDidRequestPreferences(_ controller: MenuBarController) {
    preferencesWindowController.present()
  }

  func menuBarController(
    _ controller: MenuBarController, didRequestSwitchToSpaceAtIndex index: UInt32
  ) {
    performSpaceSwitchToIndex(index, source: .menu)
    controller.scheduleRefresh(after: 0.25)
  }

  func menuBarControllerDidRequestRefresh(_ controller: MenuBarController) {
    refreshSpaceInfo()
  }
}
