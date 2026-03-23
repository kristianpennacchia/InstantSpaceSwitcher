import AppKit
import ISS

final class SpacesSettingsViewController: NSViewController {
  private let nicknameStore = SpaceNicknameStore.shared

  private let helperLabel = NSTextField(
    labelWithString: "Nicknames follow each space slot. Leave a field blank to show the number.")
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  private var spaceIndices: [Int] = []

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    setupTableView()
    reloadSpaces()
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    reloadSpaces()
  }

  private func setupTableView() {
    helperLabel.textColor = .secondaryLabelColor
    helperLabel.cell?.wraps = true
    helperLabel.cell?.lineBreakMode = .byWordWrapping
    helperLabel.translatesAutoresizingMaskIntoConstraints = false

    let spaceColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("space"))
    spaceColumn.title = "Space"
    spaceColumn.width = 120
    tableView.addTableColumn(spaceColumn)

    let nicknameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("nickname"))
    nicknameColumn.title = "Nickname"
    nicknameColumn.width = 320
    tableView.addTableColumn(nicknameColumn)

    tableView.delegate = self
    tableView.dataSource = self
    tableView.rowHeight = 30
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.borderType = .bezelBorder
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(helperLabel)
    view.addSubview(scrollView)

    NSLayoutConstraint.activate([
      helperLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
      helperLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      helperLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

      scrollView.topAnchor.constraint(equalTo: helperLabel.bottomAnchor, constant: 12),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
    ])
  }

  private func reloadSpaces() {
    let detectedCount = detectedSpaceCount()
    let highestStored = nicknameStore.highestStoredIndex.map { $0 + 1 } ?? 0
    let count = max(10, detectedCount, highestStored)

    spaceIndices = Array(0..<count)
    tableView.reloadData()
  }

  private func detectedSpaceCount() -> Int {
    var info = ISSSpaceInfo()
    guard iss_get_menubar_space_info(&info) else { return 0 }
    return Int(info.spaceCount)
  }
}

extension SpacesSettingsViewController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    spaceIndices.count
  }
}

extension SpacesSettingsViewController: NSTableViewDelegate {
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let index = spaceIndices[row]

    if tableColumn?.identifier.rawValue == "space" {
      let cellView = NSTableCellView()
      let label = NSTextField(labelWithString: SpaceLabelFormatter.spaceName(for: index))
      label.translatesAutoresizingMaskIntoConstraints = false
      cellView.addSubview(label)

      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
        label.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
        label.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
      ])

      return cellView
    }

    if tableColumn?.identifier.rawValue == "nickname" {
      let cellView = NSTableCellView()
      let field = NSTextField(string: nicknameStore.nickname(for: index) ?? "")
      field.placeholderString = "Optional nickname"
      field.tag = index
      field.delegate = self
      field.target = self
      field.action = #selector(commitNickname(_:))
      field.translatesAutoresizingMaskIntoConstraints = false
      cellView.addSubview(field)

      NSLayoutConstraint.activate([
        field.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
        field.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
        field.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
      ])

      return cellView
    }

    return nil
  }

  @objc private func commitNickname(_ sender: NSTextField) {
    nicknameStore.setNickname(sender.stringValue, for: sender.tag)
    reloadSpaces()
  }
}

extension SpacesSettingsViewController: NSTextFieldDelegate {
  func controlTextDidChange(_ obj: Notification) {
    guard let field = obj.object as? NSTextField else { return }
    nicknameStore.setNickname(field.stringValue, for: field.tag)
  }

  func controlTextDidEndEditing(_ obj: Notification) {
    guard let field = obj.object as? NSTextField else { return }
    nicknameStore.setNickname(field.stringValue, for: field.tag)
    reloadSpaces()
  }
}
