import ISS
import Carbon
import Combine
import AppKit
import ApplicationServices

@main
class InstantSpaceSwitcherApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    private let hotkeyStore = HotkeyStore.shared
    private lazy var preferencesWindowController = PreferencesWindowController()
    private var leftMenuItem: NSMenuItem?
    private var rightMenuItem: NSMenuItem?
    private var spacesMenuItem: NSMenuItem?
    private var cachedSpaceInfo: ISSSpaceInfo?
    private var cancellables = Set<AnyCancellable>()
    private var spaceChangeObserver: Any?
    private var appActivationObserver: Any?
    private var refreshWorkItem: DispatchWorkItem?
    private lazy var baseStatusImage: NSImage? = {
        let image = NSImage(systemSymbolName: "arrow.left.and.right.square", accessibilityDescription: "InstantSpaceSwitcher")
        image?.isTemplate = true
        return image
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureAccessibilityPermission()

        // Initialize the event tap for trusted gesture posting
        if !iss_init() {
            print("Failed to initialize ISS event tap")
        }

        setupMainMenu()
        setupStatusItem()
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

    private func ensureAccessibilityPermission() {
        // TODO: Display menu item and add an alert triangle to menubar icon
        // if we do not have the permission in the current session.
        // If we do not have the permission, re-check for permission
        // after a keyboard shortcut trigger.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self

        let leftItem = NSMenuItem(title: "Switch Left", action: #selector(switchLeft(_:)), keyEquivalent: "")
        leftItem.target = self
        menu.addItem(leftItem)
        leftMenuItem = leftItem

        let rightItem = NSMenuItem(title: "Switch Right", action: #selector(switchRight(_:)), keyEquivalent: "")
        rightItem.target = self
        menu.addItem(rightItem)
        rightMenuItem = rightItem

        menu.addItem(NSMenuItem.separator())

        let spacesItem = NSMenuItem(title: "Spaces", action: nil, keyEquivalent: "")
        let spacesSubmenu = NSMenu(title: "Spaces")
        spacesSubmenu.delegate = self
        spacesSubmenu.autoenablesItems = false
        spacesItem.submenu = spacesSubmenu
        menu.addItem(spacesItem)
        spacesMenuItem = spacesItem

        menu.addItem(NSMenuItem.separator())

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        preferencesItem.keyEquivalentModifierMask = [.command]
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About InstantSpaceSwitcher", action: #selector(openAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit InstantSpaceSwitcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateStatusItemAppearance()
    }

    @objc
    private func switchLeft(_ sender: Any?) {
        if !iss_switch(ISSDirectionLeft) {
            NSSound.beep()
        }
        scheduleRefresh(after: 0.2)
    }

    @objc
    private func switchRight(_ sender: Any?) {
        if !iss_switch(ISSDirectionRight) {
            NSSound.beep()
        }
        scheduleRefresh(after: 0.2)
    }

    private func bindHotkeys() {
        hotkeyStore.$leftHotkey
            .receive(on: RunLoop.main)
            .sink { [weak self] combination in
                self?.registerHotkey(for: .left, combination: combination)
            }
            .store(in: &cancellables)

        hotkeyStore.$rightHotkey
            .receive(on: RunLoop.main)
            .sink { [weak self] combination in
                self?.registerHotkey(for: .right, combination: combination)
            }
            .store(in: &cancellables)
    }

    private func registerHotkey(for identifier: HotkeyIdentifier, combination: HotkeyCombination) {
        applyHotkey(combination, to: identifier == .left ? leftMenuItem : rightMenuItem)

        HotKeyManager.shared.register(identifier: identifier, combination: combination) { [weak self] in
            guard let self else { return }
            switch identifier {
            case .left:
                self.switchLeft(nil)
            case .right:
                self.switchRight(nil)
            }
        }
    }

    private func applyHotkey(_ combination: HotkeyCombination, to menuItem: NSMenuItem?) {
        guard let menuItem else { return }
        menuItem.keyEquivalent = combination.keyEquivalent
        menuItem.keyEquivalentModifierMask = combination.cocoaModifierFlags
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "InstantSpaceSwitcher")
        appMenuItem.submenu = appMenu

        let aboutItem = NSMenuItem(title: "About InstantSpaceSwitcher", action: #selector(openAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        appMenu.addItem(NSMenuItem.separator())

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        preferencesItem.keyEquivalentModifierMask = [.command]
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)

        appMenu.addItem(NSMenuItem.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)

        appMenu.addItem(NSMenuItem.separator())

        let hideItem = NSMenuItem(title: "Hide InstantSpaceSwitcher", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAllItem.target = NSApp
        appMenu.addItem(showAllItem)

        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit InstantSpaceSwitcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        NSApp.mainMenu = mainMenu
    }

    @objc
    private func openPreferences(_ sender: Any?) {
        preferencesWindowController.present()
    }

    @objc
    private func openAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc
    private func switchToSpace(_ sender: NSMenuItem) {
        let targetIndex = UInt32(sender.tag)
        if !iss_switch_to_index(targetIndex) {
            NSSound.beep()
        }
        scheduleRefresh(after: 0.25)
    }

    private func refreshSpaceInfo() {
        var info = ISSSpaceInfo()
        if iss_get_space_info(&info) {
            cachedSpaceInfo = info
        } else {
            cachedSpaceInfo = nil
        }

        updateMenuState()
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        // TODO: this is not optimal, unnecessary refreshes. we should be 
        // hooking events probably
        refreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.refreshSpaceInfo()
        }
        refreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func updateMenuState() {
        if let info = cachedSpaceInfo {
            leftMenuItem?.isEnabled = info.currentIndex > 0
            rightMenuItem?.isEnabled = info.currentIndex + 1 < info.spaceCount
        } else {
            leftMenuItem?.isEnabled = true
            rightMenuItem?.isEnabled = true
        }

        updateSpacesMenuItems()
        updateStatusItemAppearance()
    }

    private func updateSpacesMenuItems() {
        guard let submenu = spacesMenuItem?.submenu else { return }
        submenu.removeAllItems()

        guard let info = cachedSpaceInfo, info.spaceCount > 0 else {
            let item = NSMenuItem(title: "No accessible spaces", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
            return
        }

        let count = Int(info.spaceCount)
        for index in 0..<count {
            let title = "Space \(index + 1)"
            let item = NSMenuItem(title: title, action: #selector(switchToSpace(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            item.state = index == Int(info.currentIndex) ? .on : .off
            submenu.addItem(item)
        }
    }

    private func observeSpaceChanges() {
        stopObservingSpaceChanges()
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.refreshSpaceInfo()
            self.scheduleRefresh(after: 0.2)
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
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.scheduleRefresh(after: 0.1)
        }
    }
    
    private func stopObservingAppActivation() {
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appActivationObserver = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusItem.menu || menu === spacesMenuItem?.submenu {
            scheduleRefresh(after: 0.05)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === statusItem.menu || menu === spacesMenuItem?.submenu {
            scheduleRefresh(after: 0.05)
        }
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }

        button.font = nil
        button.title = ""
        button.imagePosition = .imageOnly

        let icon: NSImage?
        if let info = cachedSpaceInfo {
            icon = makeMenuBarIconImage(info: info, size: button.bounds.size)
        } else {
            icon = nil
        }

        let finalIcon = icon ?? baseStatusImage
        finalIcon?.isTemplate = true
        button.image = finalIcon
    }


    // TODO: extremely inefficient way of rendering the icon
    private func makeMenuBarIconImage(info: ISSSpaceInfo, size: NSSize) -> NSImage? {
        let iconSize: CGFloat = 18
        let cornerRadius: CGFloat = 6
        let displayText = String(Int(info.currentIndex) + 1)
        
        let image = NSImage(size: NSSize(width: iconSize, height: iconSize))
        image.lockFocus()
        
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }
        
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        
        let rect = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.black.setFill()
        path.fill()
        
        context.setBlendMode(.destinationOut)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: iconSize * 0.6, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        
        let textSize = displayText.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (iconSize - textSize.width) / 2,
            y: (iconSize - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        displayText.draw(in: textRect, withAttributes: attributes)
        
        context.endTransparencyLayer()
        
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

class HotKeyManager {
    static let shared = HotKeyManager()

    private struct Registration {
        let id: UInt32
        var reference: EventHotKeyRef?
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var registrations: [HotkeyIdentifier: Registration] = [:]
    private var currentId: UInt32 = 1

    private init() {
        installEventHandler()
    }

    func register(identifier: HotkeyIdentifier, combination: HotkeyCombination, handler: @escaping () -> Void) {
        unregister(identifier: identifier)

        let id = currentId
        currentId &+= 1

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x1111, id: id)
        let status = RegisterEventHotKey(combination.keyCode, combination.modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)

        guard status == noErr else {
            print("Failed to register hotkey for \(identifier) status=\(status)")
            return
        }

        handlers[id] = handler
        registrations[identifier] = Registration(id: id, reference: hotKeyRef)
    }

    func unregister(identifier: HotkeyIdentifier) {
        guard let registration = registrations.removeValue(forKey: identifier) else { return }
        handlers.removeValue(forKey: registration.id)
        if let reference = registration.reference {
            UnregisterEventHotKey(reference)
        }
    }

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetEventDispatcherTarget(), { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

            if let handler = HotKeyManager.shared.handlers[hotKeyID.id] {
                handler()
            }

            return noErr
        }, 1, &eventSpec, nil, nil)
    }
}
