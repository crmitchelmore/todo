import Foundation

/// Persists the user's configured global hotkey to UserDefaults.
/// Adapted from the justspeaktoit SpeakHotKeys HotKeyStore.
@MainActor
final class HotKeyStore: ObservableObject {
    private static let defaultsKey = "captureGlobalHotKey"

    @Published var hotKey: HotKey {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(HotKey.self, from: data) {
            hotKey = decoded
        } else {
            hotKey = .default
        }
    }

    func resetToDefault() {
        hotKey = .default
    }

    private func save() {
        if let data = try? JSONEncoder().encode(hotKey) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
