import Foundation
import MillisalaryCore
import Observation

/// The settings, kept in UserDefaults as one value per key of the Electron
/// app's settings.json and always read back through the validator. A
/// change from anywhere, `defaults write` in Terminal included, shows up in
/// `settings`
@Observable
final class SettingsStore {
    private(set) var settings: Settings

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observer: DefaultsObserver?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Self.read(from: defaults)
        observer = DefaultsObserver(defaults: defaults, keys: Settings.Key.allCases.map(\.rawValue)) {
            [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    private func reload() {
        let stored = Self.read(from: defaults)
        if stored != settings {
            settings = stored
        }
    }

    private static func read(from defaults: UserDefaults) -> Settings {
        var stored: [String: Any] = [:]
        for key in Settings.Key.allCases {
            stored[key.rawValue] = defaults.object(forKey: key.rawValue)
        }
        return Settings(sanitizing: stored)
    }
}

/// Key-value observing of UserDefaults keys, which, unlike
/// UserDefaults.didChangeNotification, also reports changes made by other
/// processes. It calls back on whatever thread the change arrives on
private nonisolated final class DefaultsObserver: NSObject {
    private let defaults: UserDefaults
    private let keys: [String]
    private let onChange: @Sendable () -> Void

    init(defaults: UserDefaults, keys: [String], onChange: @escaping @Sendable () -> Void) {
        self.defaults = defaults
        self.keys = keys
        self.onChange = onChange
        super.init()
        for key in keys {
            defaults.addObserver(self, forKeyPath: key, options: [], context: nil)
        }
    }

    deinit {
        for key in keys {
            defaults.removeObserver(self, forKeyPath: key)
        }
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        onChange()
    }
}
