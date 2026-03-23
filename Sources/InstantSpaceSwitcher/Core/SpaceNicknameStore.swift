import Foundation
import Combine

final class SpaceNicknameStore: ObservableObject {
  static let shared = SpaceNicknameStore()
  private static let defaultsKey = "spaceNicknames"

  @Published private(set) var nicknames: [Int: String]

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    nicknames = Self.loadNicknames(from: defaults, key: Self.defaultsKey)
  }

  func nickname(for index: Int) -> String? {
    nicknames[index]
  }

  var highestStoredIndex: Int? {
    nicknames.keys.max()
  }

  func setNickname(_ nickname: String, for index: Int) {
    let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    var updated = nicknames

    if trimmed.isEmpty {
      updated.removeValue(forKey: index)
    } else {
      updated[index] = trimmed
    }

    guard updated != nicknames else { return }

    nicknames = updated
    persist()
  }

  private func persist() {
    guard !nicknames.isEmpty else {
      defaults.removeObject(forKey: Self.defaultsKey)
      return
    }

    if let data = try? JSONEncoder().encode(nicknames) {
      defaults.set(data, forKey: Self.defaultsKey)
    }
  }

  private static func loadNicknames(from defaults: UserDefaults, key: String) -> [Int: String] {
    guard let data = defaults.data(forKey: key),
      let decoded = try? JSONDecoder().decode([Int: String].self, from: data)
    else {
      return [:]
    }

    return decoded.reduce(into: [:]) { result, entry in
      let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      result[entry.key] = trimmed
    }
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
    nicknameStore.nickname(for: index) ?? number(for: index)
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
