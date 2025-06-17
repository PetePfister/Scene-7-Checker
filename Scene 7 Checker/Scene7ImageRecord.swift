import Foundation
import AppKit

enum Scene7ImageStatus: String {
    case notChecked
    case exists
    case unique
    case error
}

struct NameSuggestion {
    let originalName: String
    let suggestedName: String
    let reason: String
}

struct Scene7ImageRecord: Identifiable, Equatable {
    let id: UUID
    var localURL: URL
    var filename: String { localURL.lastPathComponent }
    var originalFilename: String // Add this to store the original filename
    var proposedName: String
    var scene7URL: URL?
    var status: Scene7ImageStatus
    var md5Hash: String?
    var isDuplicate: Bool
    var renameError: String?
    var namingWarning: String?
    var thumbnail: NSImage?
    var usedDetailSlots: [String]?
    var availableDetailSlots: [String]?
    var detailSlotChecked: Bool
    var userMarkedOK: Bool
    var nameSuggestion: NameSuggestion?

    init(
        id: UUID = UUID(),
        localURL: URL,
        originalFilename: String? = nil,
        proposedName: String? = nil,
        scene7URL: URL? = nil,
        status: Scene7ImageStatus = .notChecked,
        md5Hash: String? = nil,
        isDuplicate: Bool = false,
        renameError: String? = nil,
        namingWarning: String? = nil,
        thumbnail: NSImage? = nil,
        usedDetailSlots: [String]? = nil,
        availableDetailSlots: [String]? = nil,
        detailSlotChecked: Bool = false,
        userMarkedOK: Bool = false,
        nameSuggestion: NameSuggestion? = nil
    ) {
        self.id = id
        self.localURL = localURL
        self.originalFilename = originalFilename ?? localURL.lastPathComponent
        self.proposedName = proposedName ?? localURL.lastPathComponent
        self.scene7URL = scene7URL
        self.status = status
        self.md5Hash = md5Hash
        self.isDuplicate = isDuplicate
        self.renameError = renameError
        self.namingWarning = namingWarning
        self.thumbnail = thumbnail
        self.usedDetailSlots = usedDetailSlots
        self.availableDetailSlots = availableDetailSlots
        self.detailSlotChecked = detailSlotChecked
        self.userMarkedOK = userMarkedOK
        self.nameSuggestion = nameSuggestion
    }
    
    static func == (lhs: Scene7ImageRecord, rhs: Scene7ImageRecord) -> Bool {
        return lhs.id == rhs.id
    }
}
