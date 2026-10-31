import Foundation
import MillisalaryCore

/// The settings of the Electron Millisalary this app replaces, taken over
/// once: on the first launch, when nothing has been stored here yet. Its
/// settings.json is only read, never changed.
enum ElectronSettingsImport {
    private static let doneKey = "didImportElectronSettings"

    /// Its userData folder: "Millisalary" for the packaged app,
    /// "electron-millisalary" for a dev checkout
    private static let folders = ["Millisalary", "electron-millisalary"]

    static func runIfNeeded(into store: SettingsStore, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        // Asked once, whether or not there was anything to take
        defaults.set(true, forKey: doneKey)
        guard !store.hasStoredSettings, let raw = newestSettingsFile() else { return }

        store.replace(with: Settings(sanitizing: raw))
    }

    /// The most recently saved settings.json, as JSON values
    private static func newestSettingsFile() -> [String: Any]? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let newest = folders
            .map { support.appendingPathComponent($0).appendingPathComponent("settings.json") }
            .compactMap { url -> (url: URL, modified: Date)? in
                let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return modified.map { (url, $0) }
            }
            .max { $0.modified < $1.modified }

        guard let url = newest?.url,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // JSONSerialization hands long decimals over as NSDecimalNumber, whose
        // doubleValue is off in the last bits; its text is exact
        return json.mapValues { value in
            (value as? NSDecimalNumber).flatMap { Double($0.description) } ?? value
        }
    }
}
