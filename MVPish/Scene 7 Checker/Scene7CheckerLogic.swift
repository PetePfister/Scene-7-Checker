import Foundation
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Model & Enums

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

    // Used/available slots for detail images
    var usedDetailSlots: [String]? = nil
    var availableDetailSlots: [String]? = nil
    var detailSlotChecked: Bool = false
}

// MARK: - Logic

@MainActor
class Scene7CheckerLogic: ObservableObject {
    @Published var records: [Scene7ImageRecord] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var lastExportURL: URL? = nil

    let placeholderMD5 = "115485ffcdb7a6419a5751a6045b482f"
    let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "tiff", "tif", "bmp", "webp", "heic"]

    // MARK: - Import files/folders (recursive for dropped folders)
    static func collectFileURLs(from urls: [URL]) async -> [URL] {
        var allFiles: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if exists {
                if isDir.boolValue {
                    if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                        for case let fileURL as URL in enumerator {
                            var isFileDir: ObjCBool = false
                            let subExists = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isFileDir)
                            if subExists && !isFileDir.boolValue {
                                allFiles.append(fileURL)
                            }
                        }
                    }
                } else {
                    allFiles.append(url)
                }
            }
        }
        return allFiles
    }

    func importFiles(from urls: [URL]) {
        Task {
            let allFiles = await Self.collectFileURLs(from: urls)
            let filtered = allFiles.filter { url in
                let ext = url.pathExtension.lowercased()
                return imageExtensions.contains(ext)
            }
            let uniqueFiles = Array(Set(filtered))
            let imageRecords = uniqueFiles.map { url in
                let filename = url.lastPathComponent
                let scene7url = Self.scene7URL(for: filename)
                return Scene7ImageRecord(
                    localURL: url,
                    proposedName: filename,
                    scene7URL: scene7url,
                    thumbnail: Self.thumbnail(for: url)
                )
            }
            self.records = imageRecords
            self.errorMessage = records.isEmpty ? "No image files found in selection." : nil
        }
    }

    // MARK: - Scene7 Check (actor-safe, checks detail slots)
    @MainActor
    func checkAllImages() {
        Task {
            self.isLoading = true
            defer { self.isLoading = false }
            var updatedRecords = self.records
            for idx in updatedRecords.indices {
                let record = updatedRecords[idx]
                let checkedRecord = await self.checkedImageRecord(for: record)
                updatedRecords[idx] = checkedRecord
            }
            self.records = updatedRecords
        }
    }

    // MARK: - Re-check a record when the user renames it (called from UI)
    @MainActor
    func checkImageForProposedName(recordID: UUID, newProposedName: String) {
        guard let idx = records.firstIndex(where: { $0.id == recordID }) else { return }
        var record = records[idx]
        record.proposedName = newProposedName
        record.scene7URL = Self.scene7URL(for: newProposedName)
        record.status = .notChecked
        record.isDuplicate = false
        record.md5Hash = nil
        record.usedDetailSlots = nil
        record.availableDetailSlots = nil
        record.detailSlotChecked = false
        records[idx] = record
        Task {
            let checkedRecord = await self.checkedImageRecord(for: record)
            if let idx2 = self.records.firstIndex(where: { $0.id == checkedRecord.id }) {
                self.records[idx2] = checkedRecord
            }
        }
    }

    // MARK: - Async check helper - takes/returns value, never inout
    private func checkedImageRecord(for record: Scene7ImageRecord) async -> Scene7ImageRecord {
        var updated = record
        guard let url = Self.scene7URL(for: updated.proposedName) else {
            updated.status = .error
            return updated
        }
        let (exists, hash) = await Self.checkScene7Image(url: url, placeholderMD5: placeholderMD5)
        if let exists = exists {
            updated.status = exists ? .exists : .unique
            updated.isDuplicate = exists
        } else {
            updated.status = .error
        }
        updated.md5Hash = hash
        if let result = await scanDetailImageSlots(for: updated.proposedName) {
            updated.usedDetailSlots = result.used
            updated.availableDetailSlots = result.available
            updated.detailSlotChecked = true
        }
        return updated
    }

    // MARK: - Scene7 URL Generation
    static func scene7URL(for filename: String) -> URL? {
        let lowerFilename = filename.lowercased()
        let filenameNoExtension = (lowerFilename as NSString).deletingPathExtension
        let pattern = #"_(\d{3})$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: filenameNoExtension.utf16.count)
        let converted = regex?.stringByReplacingMatches(in: filenameNoExtension, options: [], range: range, withTemplate: ".$1") ?? filenameNoExtension
        let itemNumber = converted.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: true).first?
            .split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true).first
        guard let item = itemNumber, let first = item.first else { return nil }
        let itemStr = String(item)
        let lastTwo = itemStr.suffix(2)
        return URL(string: "https://qvc.scene7.com/is/image/QVC/\(first)/\(lastTwo)/\(converted)")
    }

    // MARK: - Scene7 Existence & Placeholder Checker
    static func checkScene7Image(url: URL, placeholderMD5: String) async -> (Bool?, String?) {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let digest = Insecure.MD5.hash(data: data)
            let hash = digest.map { String(format: "%02hhx", $0) }.joined()
            let isReal = (hash != placeholderMD5)
            return (isReal, hash)
        } catch {
            return (nil, nil)
        }
    }

    // MARK: - Thumbnail Generation
    static func thumbnail(for url: URL) -> NSImage? {
        guard let img = NSImage(contentsOf: url) else { return nil }
        let targetSize = NSSize(width: 40, height: 40)
        return NSImage(size: targetSize, flipped: false) { rect in
            img.draw(in: rect, from: NSRect(origin: .zero, size: img.size),
                    operation: .copy, fraction: 1.0)
            return true
        }
    }

    // MARK: - Rename Logic (no inout, no actor isolation violation)
    func validateRename(_ record: Scene7ImageRecord, existingNames: [String]) -> Scene7ImageRecord {
        var record = record
        let trimmed = record.proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            record.renameError = "Filename cannot be empty."
            return record
        }
        guard imageExtensions.contains((trimmed as NSString).pathExtension.lowercased()) else {
            record.renameError = "Not a valid image file extension."
            return record
        }
        if existingNames.contains(trimmed.lowercased()) {
            record.renameError = "Duplicate filename in this batch."
            return record
        }
        record.renameError = nil
        return record
    }

    // Rename files on disk (never uses inout, never accesses records in a way that triggers actor isolation error)
    @MainActor
    func renameOnDisk() {
        let fileManager = FileManager.default
        var updatedRecords = records
        for idx in updatedRecords.indices {
            let otherNames = updatedRecords.enumerated()
                .filter { $0.offset != idx }
                .map { $0.element.proposedName.lowercased() }
            var record = updatedRecords[idx]
            record = validateRename(record, existingNames: otherNames)
            if record.filename != record.proposedName && record.renameError == nil {
                let destination = record.localURL.deletingLastPathComponent().appendingPathComponent(record.proposedName)
                do {
                    try fileManager.moveItem(at: record.localURL, to: destination)
                    record.localURL = destination
                } catch {
                    record.renameError = "Rename failed: \(error.localizedDescription)"
                }
            }
            updatedRecords[idx] = record
        }
        records = updatedRecords
    }

    // Can Export/Rename?
    var canExport: Bool {
        records.contains(where: { $0.filename != $0.proposedName })
    }

    // Drag and Drop (Swift 6 Safe)
    func handleDrop(providers: [NSItemProvider]) {
        let providerCount = providers.count
        guard providerCount > 0 else { return }
        let dispatchGroup = DispatchGroup()
        let collector = URLCollector()

        for provider in providers {
            dispatchGroup.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    Task {
                        await collector.append(url)
                        dispatchGroup.leave()
                    }
                } else {
                    dispatchGroup.leave()
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            Task {
                let urls = await collector.collected()
                self.importFiles(from: urls)
            }
        }
    }

    // MARK: - Detail Slot Scan Logic
    /// Returns both used and available slots for detail images named like K382610_003.jpg or K382610.003.jpg (slots 001-008)
    func scanDetailImageSlots(for filename: String) async -> (used: [String], available: [String])? {
        // Accepts both _003 and .003 patterns, always checks dot format for Scene7 compatibility
        guard let regex = try? NSRegularExpression(pattern: #"^([a-zA-Z0-9]+)(?:[_\.])(\d{3})\.(jpg|jpeg|png|gif|tiff|tif|bmp|webp|heic)$"#, options: .caseInsensitive) else {
            return nil
        }
        let nsFilename = filename as NSString
        let matches = regex.matches(in: filename, options: [], range: NSRange(location: 0, length: nsFilename.length))
        guard let match = matches.first, match.numberOfRanges >= 4 else { return nil }
        let base = nsFilename.substring(with: match.range(at: 1))
        let ext = nsFilename.substring(with: match.range(at: 3))

        var used: [String] = []
        var available: [String] = []
        for i in 1...8 {
            let slotNum = String(format: "%03d", i)
            let candidate = "\(base).\(slotNum).\(ext)"
            guard let url = Self.scene7URL(for: candidate) else { continue }
            let (exists, _) = await Self.checkScene7Image(url: url, placeholderMD5: placeholderMD5)
            if exists == true {
                used.append(slotNum)
            } else {
                available.append(slotNum)
            }
        }
        return (used, available)
    }
}

// Thread-Safe Collector for Drag & Drop (Swift 6)
actor URLCollector {
    var list: [URL] = []
    func append(_ url: URL) {
        list.append(url)
    }
    func collected() -> [URL] {
        list
    }
}
