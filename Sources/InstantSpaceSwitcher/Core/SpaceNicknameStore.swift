import AppKit
import Combine

struct SpaceNicknameEntry: Codable, Equatable {
  var nickname: String?
  var symbolName: String?

  var normalized: SpaceNicknameEntry {
    SpaceNicknameEntry(
      nickname: nickname?.trimmedNil,
      symbolName: symbolName?.trimmedNil
    )
  }

  var isEmpty: Bool {
    normalized.nickname == nil && normalized.symbolName == nil
  }
}

final class SpaceNicknameStore: ObservableObject {
  static let shared = SpaceNicknameStore()
  private static let defaultsKey = "spaceNicknames"

  @Published private(set) var entries: [Int: SpaceNicknameEntry]

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    entries = Self.loadEntries(from: defaults, key: Self.defaultsKey)
  }

  func entry(for index: Int) -> SpaceNicknameEntry? {
    entries[index]
  }

  func nickname(for index: Int) -> String? {
    entries[index]?.nickname
  }

  func symbolName(for index: Int) -> String? {
    entries[index]?.symbolName
  }

  var highestStoredIndex: Int? {
    entries.keys.max()
  }

  func setNickname(_ nickname: String, for index: Int) {
    updateEntry(at: index) { entry in
      entry.nickname = nickname
    }
  }

  func setSymbolName(_ symbolName: String, for index: Int) {
    updateEntry(at: index) { entry in
      entry.symbolName = symbolName
    }
  }

  private func updateEntry(at index: Int, update: (inout SpaceNicknameEntry) -> Void) {
    var entry = entries[index] ?? SpaceNicknameEntry()
    update(&entry)
    let normalized = entry.normalized
    var updated = entries

    if normalized.isEmpty {
      updated.removeValue(forKey: index)
    } else {
      updated[index] = normalized
    }

    guard updated != entries else { return }

    entries = updated
    persist()
  }

  private func persist() {
    guard !entries.isEmpty else {
      defaults.removeObject(forKey: Self.defaultsKey)
      return
    }

    if let data = try? JSONEncoder().encode(entries) {
      defaults.set(data, forKey: Self.defaultsKey)
    }
  }

  private static func loadEntries(from defaults: UserDefaults, key: String) -> [Int: SpaceNicknameEntry] {
    guard let data = defaults.data(forKey: key) else {
      return [:]
    }

    if let decoded = try? JSONDecoder().decode([Int: SpaceNicknameEntry].self, from: data) {
      return decoded.reduce(into: [:]) { result, entry in
        let normalized = entry.value.normalized
        guard !normalized.isEmpty else { return }
        result[entry.key] = normalized
      }
    }

    if let legacyNicknames = try? JSONDecoder().decode([Int: String].self, from: data) {
      return legacyNicknames.reduce(into: [:]) { result, entry in
        let normalized = SpaceNicknameEntry(nickname: entry.value, symbolName: nil).normalized
        guard !normalized.isEmpty else { return }
        result[entry.key] = normalized
      }
    }

    return [:]
  }
}

private extension String {
  var trimmedNil: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

enum SpaceLabelFormatter {
  static func number(for index: Int) -> String {
    "\(index + 1)"
  }

  static func spaceName(for index: Int) -> String {
    "Space \(index + 1)"
  }

  static func runtimeLabel(
    for index: Int, nicknameStore: SpaceNicknameStore = .shared
  ) -> String {
    if let nickname = nicknameStore.nickname(for: index) {
      return nickname
    }

    if symbolImage(for: index, nicknameStore: nicknameStore) != nil {
      return ""
    }

    return number(for: index)
  }

  static func menuBarTitle(
    for index: Int, nicknameStore: SpaceNicknameStore = .shared
  ) -> String {
    runtimeLabel(for: index, nicknameStore: nicknameStore)
  }

  static func submenuTitle(
    for index: Int, nicknameStore: SpaceNicknameStore = .shared
  ) -> String {
    nicknameStore.nickname(for: index) ?? spaceName(for: index)
  }

  static func keyboardShortcutActionTitle(
    for index: Int, nicknameStore: SpaceNicknameStore = .shared
  ) -> String {
    guard let nickname = nicknameStore.nickname(for: index) else {
      return "Switch to space \(index + 1)"
    }

    return "Switch to \(nickname) (Space \(index + 1))"
  }

  static func symbolImage(
    for index: Int,
    pointSize: CGFloat = 14,
    weight: NSFont.Weight = .regular,
    nicknameStore: SpaceNicknameStore = .shared
  ) -> NSImage? {
    symbolImage(
      forSymbolName: nicknameStore.symbolName(for: index),
      pointSize: pointSize,
      weight: weight
    )
  }

  static func symbolImage(
    forSymbolName symbolName: String?,
    pointSize: CGFloat = 14,
    weight: NSFont.Weight = .regular
  ) -> NSImage? {
    guard let symbolName = symbolName?.trimmedNil,
      let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    else {
      return nil
    }

    let configured =
      symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
      ?? symbol
    configured.isTemplate = true
    return configured
  }
}

extension HotkeyIdentifier {
  var spaceTargetIndex: Int? {
    switch self {
    case .space1: return 0
    case .space2: return 1
    case .space3: return 2
    case .space4: return 3
    case .space5: return 4
    case .space6: return 5
    case .space7: return 6
    case .space8: return 7
    case .space9: return 8
    case .space10: return 9
    case .left, .right: return nil
    }
  }
}
