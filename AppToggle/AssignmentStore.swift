import Foundation

struct AssignmentStore {
    let url: URL

    init(url: URL = URL.applicationSupportDirectory.appending(path: "AppToggle/assignments.json")) {
        self.url = url
    }

    func load() throws -> [Assignment] {
        do {
            let data: Data
            do { data = try Data(contentsOf: url) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
            let assignments = try JSONDecoder().decode([Assignment].self, from: data)
            var ids = Set<UUID>()
            var shortcuts = Set<String>()
            for assignment in assignments {
                try assignment.shortcut.validate()
                guard ids.insert(assignment.id).inserted,
                      shortcuts.insert("\(assignment.shortcut.keyCode):\(assignment.shortcut.modifiers)").inserted,
                      assignment.app.url.isFileURL,
                      !assignment.app.url.path.isEmpty,
                      !assignment.app.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !assignment.app.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AppToggleError("The saved assignments contain invalid or duplicate values.")
                }
            }
            return assignments
        } catch {
            throw AppToggleError("Cannot read assignments at \(url.path): \(error.localizedDescription) Restore or repair this file, then reload assignments.")
        }
    }

    func save(_ assignments: [Assignment]) throws {
        do {
            let data = try JSONEncoder().encode(assignments)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw AppToggleError("Cannot save assignments at \(url.path): \(error.localizedDescription)")
        }
    }
}
