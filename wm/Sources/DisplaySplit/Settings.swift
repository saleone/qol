import Foundation
import DisplaySplitCore

/// Settings live in a plain JSON file so they can be kept in a dotfiles repo. The file is read
/// on every access, so edits (by hand, `git pull`, a re-linked symlink) apply immediately.
@MainActor
final class Settings {
    let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/displaysplit/config.json")

    struct Loaded {
        var config: Config
        /// Set when the file exists but can't be used; `config` then holds the defaults.
        var error: String?
    }

    func load() -> Loaded {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return Loaded(config: Config())
        } catch {
            return Loaded(config: Config(), error: error.localizedDescription)
        }
        do {
            return Loaded(config: try Config(json: data))
        } catch {
            return Loaded(config: Config(), error: String(describing: error))
        }
    }

    func save(_ config: Config) throws {
        // Write through a symlink (e.g. into a dotfiles repo) instead of replacing it.
        let target = fileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try config.json().write(to: target, options: .atomic)
    }

    /// Writes the defaults if there is no config file yet, so there is something to edit and commit.
    func createIfMissing() throws {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try save(Config())
    }
}
