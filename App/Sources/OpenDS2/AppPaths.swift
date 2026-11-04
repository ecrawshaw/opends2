import Foundation

/// Where OpenDS2 keeps its own files: ~/Library/Application Support/OpenDS2/
/// (coding-backups/, cluster-coding-backups/, history/).
///
/// The app was called "E46 Diagnostics" before it was renamed. On first launch, `migrateFromE46Diag()`
/// moves that app's support folder and settings over, so coding backups are never stranded.
enum AppPaths {
    static let legacyBundleID = "com.ecrawshaw.e46diag"

    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenDS2", isDirectory: true)
    }

    private static var legacySupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("E46Diag", isDirectory: true)
    }

    /// One-time move of the old support folder and UserDefaults. Safe to call on every launch:
    /// it does nothing once the new folder exists or when there is nothing old to move.
    static func migrateFromE46Diag() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: support.path), fm.fileExists(atPath: legacySupport.path) {
            // A move keeps every backup file intact; if it fails, the old folder is left untouched.
            try? fm.moveItem(at: legacySupport, to: support)
        }
        let migratedKey = "migratedFromE46Diag"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        if let old = UserDefaults(suiteName: legacyBundleID)?.persistentDomain(forName: legacyBundleID) {
            for (k, v) in old where defaults.object(forKey: k) == nil { defaults.set(v, forKey: k) }
        }
        defaults.set(true, forKey: migratedKey)
    }
}
