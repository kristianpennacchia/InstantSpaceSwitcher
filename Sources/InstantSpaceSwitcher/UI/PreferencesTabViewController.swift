import AppKit

final class PreferencesTabViewController: NSTabViewController {
  override func viewDidLoad() {
    super.viewDidLoad()

    tabStyle = .toolbar

    let generalTab = NSTabViewItem(viewController: GeneralSettingsViewController())
    generalTab.label = "General"
    generalTab.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General")

    let spacesTab = NSTabViewItem(viewController: SpacesSettingsViewController())
    spacesTab.label = "Spaces"
    spacesTab.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Spaces")

    let shortcutsTab = NSTabViewItem(viewController: KeyboardShortcutsViewController())
    shortcutsTab.label = "Keyboard"
    shortcutsTab.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyboard")

    addTabViewItem(generalTab)
    addTabViewItem(spacesTab)
    addTabViewItem(shortcutsTab)
  }
}
