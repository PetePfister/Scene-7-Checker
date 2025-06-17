import Foundation
import AppKit

enum Scene7ImageStatus {
    case notChecked
    case exists
    case unique
    case error
}

struct Scene7ImageRecord: Identifiable {
    let id = UUID()
    var localURL: URL
    var filename: String { localURL.lastPathComponent }
    var proposedName: String
    var scene7URL: URL? = nil
    var status: Scene7ImageStatus = .notChecked
    var md5Hash: String? = nil
    var isDuplicate: Bool = false
    var renameError: String? = nil
    var thumbnail: NSImage? = nil
}
