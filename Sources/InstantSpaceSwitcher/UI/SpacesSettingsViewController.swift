import AppKit
import ISS

final class SpacesSettingsViewController: NSViewController {
  private enum EditableFieldKind {
    case symbol
    case nickname

    var columnIdentifier: NSUserInterfaceItemIdentifier {
      switch self {
      case .symbol:
        return NSUserInterfaceItemIdentifier("symbol")
      case .nickname:
        return NSUserInterfaceItemIdentifier("nickname")
      }
    }
  }

  private let nicknameStore = SpaceNicknameStore.shared
  private let symbolFieldTagOffset = 10_000

  private let helperLabel = NSTextField(
    labelWithString:
      "Nicknames follow each space slot. Add an SF Symbol name like house.fill, and leave fields blank to fall back to the number."
  )
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

    let symbolColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("symbol"))
    symbolColumn.title = "Symbol"
    symbolColumn.width = 170
    tableView.addTableColumn(symbolColumn)

    let nicknameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("nickname"))
    nicknameColumn.title = "Nickname"
    nicknameColumn.width = 210
    tableView.addTableColumn(nicknameColumn)

    tableView.delegate = self
    tableView.dataSource = self
    tableView.rowHeight = 34
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

    if tableColumn?.identifier.rawValue == "symbol" {
      let cellView = NSTableCellView()
      let imageView = NSImageView()
      imageView.image = SpaceLabelFormatter.symbolImage(
        for: index, pointSize: 14, weight: .regular, nicknameStore: nicknameStore)
      imageView.contentTintColor = .secondaryLabelColor
      imageView.translatesAutoresizingMaskIntoConstraints = false

      let field = NSTextField(string: nicknameStore.symbolName(for: index) ?? "")
      field.placeholderString = "house.fill"
      field.isEditable = true
      field.isSelectable = true
      field.tag = symbolFieldTagOffset + index
      field.delegate = self
      field.target = self
      field.action = #selector(commitSymbol(_:))
      field.translatesAutoresizingMaskIntoConstraints = false

      let stackView = NSStackView(views: [imageView, field])
      stackView.orientation = .horizontal
      stackView.alignment = .centerY
      stackView.spacing = 8
      stackView.translatesAutoresizingMaskIntoConstraints = false
      cellView.addSubview(stackView)

      NSLayoutConstraint.activate([
        imageView.widthAnchor.constraint(equalToConstant: 16),
        imageView.heightAnchor.constraint(equalToConstant: 16),
        stackView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
        stackView.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
        stackView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
      ])

      return cellView
    }

    if tableColumn?.identifier.rawValue == "nickname" {
      let cellView = NSTableCellView()
      let field = NSTextField(string: nicknameStore.nickname(for: index) ?? "")
      field.placeholderString = "Optional nickname"
      field.isEditable = true
      field.isSelectable = true
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
    persistChanges(for: sender)
  }

  @objc private func commitSymbol(_ sender: NSTextField) {
    persistChanges(for: sender)
  }

  private func persistChanges(for field: NSTextField) {
    if field.tag >= symbolFieldTagOffset {
      nicknameStore.setSymbolName(field.stringValue, for: field.tag - symbolFieldTagOffset)
    } else {
      nicknameStore.setNickname(field.stringValue, for: field.tag)
    }
  }

  private func fieldContext(for field: NSTextField) -> (row: Int, kind: EditableFieldKind)? {
    let index = field.tag >= symbolFieldTagOffset ? field.tag - symbolFieldTagOffset : field.tag
    guard let row = spaceIndices.firstIndex(of: index) else { return nil }
    let kind: EditableFieldKind = field.tag >= symbolFieldTagOffset ? .symbol : .nickname
    return (row, kind)
  }

  private func focusEditableField(after field: NSTextField, movingBackward: Bool) {
    guard let context = fieldContext(for: field) else { return }

    let target: (row: Int, kind: EditableFieldKind)?
    switch (context.kind, movingBackward) {
    case (.symbol, false):
      target = (context.row, .nickname)
    case (.nickname, false):
      target = context.row + 1 < spaceIndices.count ? (context.row + 1, .symbol) : nil
    case (.nickname, true):
      target = (context.row, .symbol)
    case (.symbol, true):
      target = context.row > 0 ? (context.row - 1, .nickname) : nil
    }

    guard let target else {
      if movingBackward {
        view.window?.selectPreviousKeyView(field)
      } else {
        view.window?.selectNextKeyView(field)
      }
      return
    }

    focusEditableField(atRow: target.row, kind: target.kind)
  }

  private func focusEditableField(atRow row: Int, kind: EditableFieldKind) {
    guard row >= 0 && row < spaceIndices.count else { return }

    let index = spaceIndices[row]
    let tag = kind == .symbol ? symbolFieldTagOffset + index : index
    let column = tableView.column(withIdentifier: kind.columnIdentifier)
    guard column >= 0 else { return }

    tableView.scrollRowToVisible(row)

    guard
      let cellView = tableView.view(atColumn: column, row: row, makeIfNecessary: true),
      let field = cellView.viewWithTag(tag) as? NSTextField
    else {
      return
    }

    field.selectText(nil)
  }
}

extension SpacesSettingsViewController: NSTextFieldDelegate {
  func controlTextDidChange(_ obj: Notification) {
    guard let field = obj.object as? NSTextField else { return }

    if field.tag >= symbolFieldTagOffset {
      nicknameStore.setSymbolName(field.stringValue, for: field.tag - symbolFieldTagOffset)
      if let stackView = field.superview as? NSStackView,
        let preview = stackView.arrangedSubviews.first as? NSImageView
      {
        preview.image = SpaceLabelFormatter.symbolImage(
          forSymbolName: field.stringValue,
          pointSize: 14,
          weight: .regular
        )
      }
      return
    }

    nicknameStore.setNickname(field.stringValue, for: field.tag)
  }

  func controlTextDidEndEditing(_ obj: Notification) {
    guard let field = obj.object as? NSTextField else { return }
    persistChanges(for: field)
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
    -> Bool
  {
    guard let field = control as? NSTextField else { return false }

    if commandSelector == #selector(NSResponder.insertTab(_:)) {
      persistChanges(for: field)
      focusEditableField(after: field, movingBackward: false)
      return true
    }

    if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
      persistChanges(for: field)
      focusEditableField(after: field, movingBackward: true)
      return true
    }

    return false
  }
}
