import Foundation
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Array Chunking Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Logic

@MainActor
class Scene7CheckerLogic: ObservableObject {
    @Published var records: [Scene7ImageRecord] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    let placeholderMD5 = "115485ffcdb7a6419a5751a6045b482f"
    let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "tiff", "tif", "bmp", "webp", "heic"]

    // MARK: - Naming Convention Regex Patterns (updated for slot 001-008 only)
    let swatchBlockPattern = #"^[A-Za-z0-9]+(?:_[A-Za-z0-9]+)*(?:_[A-Za-z0-9]+)*[_.]101!?\.((jpg|jpeg|png|gif|tiff|tif|bmp|webp|heic))$"#
    let swatchImagePattern = #"^[A-Za-z0-9]+(?:_[A-Za-z0-9]+)*(?:_[A-Za-z0-9]+)*[_.]102!?\.((jpg|jpeg|png|gif|tiff|tif|bmp|webp|heic))$"#
    let slotPattern = #"^[A-Za-z0-9]+[_.]00[1-8]\.(jpg|jpeg|png|gif|tiff|tif|bmp|webp|heic)$"#

    // MARK: - Naming Convention Check
    func checkNamingConvention(filename: String) -> String? {
        let patterns = [
            (swatchBlockPattern, "Swatch block image (101 or 101!)"),
            (swatchImagePattern, "Swatch image (102 or 102!)"),
            (slotPattern, "Product detail/slot image (_001 to _008 or .001 to .008)")
        ]
        let range = NSRange(location: 0, length: (filename as NSString).length)
        for (pattern, _) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: filename, options: [], range: range) != nil {
                return nil // Valid
            }
        }
        return "Invalid Filename"
    }

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

    // Helper to extract main item number (the part before first _ or .)
    private func extractMainItemNumber(from filename: String) -> String {
        if let range = filename.range(of: "[_.]", options: .regularExpression) {
            return String(filename[..<range.lowerBound])
        }
        return filename
    }

    // Returns .slot(number: Int) or .complex
    enum SortKind {
        case slot(Int)
        case complex
    }

    // Classifies as slot or complex for sort, based on item number
    private func classifySlotOrComplex(_ filename: String, mainItem: String) -> SortKind {
        let base = (filename as NSString).deletingPathExtension
        // Match _NNN or .NNN at end, e.g. A607320_004 or A607320.005
        let slotPattern = #"^(?:\#(mainItem))[_.](\d{3})$"#
        if let regex = try? NSRegularExpression(pattern: slotPattern, options: .caseInsensitive) {
            let nsBase = base as NSString
            let range = NSRange(location: 0, length: nsBase.length)
            if let match = regex.firstMatch(in: base, options: [], range: range), match.numberOfRanges == 3 {
                let slotStr = nsBase.substring(with: match.range(at: 2))
                if let slotNum = Int(slotStr) {
                    return .slot(slotNum)
                }
            }
        }
        return .complex
    }

    func importFiles(from urls: [URL]) {
        Task {
            let allFiles = await Self.collectFileURLs(from: urls)
            let filtered = allFiles.filter { url in
                let ext = url.pathExtension.lowercased()
                return imageExtensions.contains(ext)
            }

            // Extract the base item number (e.g., A607320 from A607320_004.jpg)
            func extractBaseItemNumber(from filename: String) -> String {
                if let range = filename.range(of: "[_.]", options: .regularExpression) {
                    return String(filename[..<range.lowerBound])
                }
                return filename
            }

            // This will help determine sorting priority
            enum FileType {
                case numeric(baseItem: String, separator: String, number: Int)
                case complex(baseItem: String)
            }

            // Classify file by its pattern
            func classifyFile(_ filename: String) -> FileType {
                let base = (filename as NSString).deletingPathExtension
                let baseItem = extractBaseItemNumber(from: filename)
                
                // Pattern for A607320_004 format
                let underscorePattern = #"^(\#(baseItem))_(\d{3})$"#
                // Pattern for A607320.005 format
                let dotPattern = #"^(\#(baseItem))\.(\d{3})$"#
                
                let nsBase = base as NSString
                let range = NSRange(location: 0, length: nsBase.length)
                
                // Try to match underscore pattern
                if let regex = try? NSRegularExpression(pattern: underscorePattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: base, options: [], range: range), match.numberOfRanges == 3 {
                    let slotStr = nsBase.substring(with: match.range(at: 2))
                    if let slotNum = Int(slotStr) {
                        return .numeric(baseItem: baseItem, separator: "_", number: slotNum)
                    }
                }
                
                // Try to match dot pattern
                if let regex = try? NSRegularExpression(pattern: dotPattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: base, options: [], range: range), match.numberOfRanges == 3 {
                    let slotStr = nsBase.substring(with: match.range(at: 2))
                    if let slotNum = Int(slotStr) {
                        return .numeric(baseItem: baseItem, separator: ".", number: slotNum)
                    }
                }
                
                // If no pattern matched, it's complex
                return .complex(baseItem: baseItem)
            }

            // Custom sort function that will produce the exact ordering you want
            func customSort(lhs: URL, rhs: URL) -> Bool {
                let fileA = lhs.lastPathComponent
                let fileB = rhs.lastPathComponent
                
                let typeA = classifyFile(fileA)
                let typeB = classifyFile(fileB)
                
                // First sort by base item number
                switch (typeA, typeB) {
                case let (.numeric(baseItemA, _, _), .numeric(baseItemB, _, _)) where baseItemA != baseItemB:
                    return baseItemA.localizedStandardCompare(baseItemB) == .orderedAscending
                    
                case let (.numeric(baseItemA, _, _), .complex(baseItemB)) where baseItemA != baseItemB:
                    return baseItemA.localizedStandardCompare(baseItemB) == .orderedAscending
                    
                case let (.complex(baseItemA), .numeric(baseItemB, _, _)) where baseItemA != baseItemB:
                    return baseItemA.localizedStandardCompare(baseItemB) == .orderedAscending
                    
                case let (.complex(baseItemA), .complex(baseItemB)) where baseItemA != baseItemB:
                    return baseItemA.localizedStandardCompare(baseItemB) == .orderedAscending
                    
                // For numeric files with the same base, sort by number first
                case let (.numeric(_, _, numA), .numeric(_, _, numB)) where numA != numB:
                    return numA < numB
                    
                // For numeric files with the same base and number, sort by separator (underscore first)
                case let (.numeric(_, sepA, _), .numeric(_, sepB, _)) where sepA != sepB:
                    // Priority: _ (underscore) comes before . (dot)
                    return sepA == "_" && sepB == "."
                    
                // Numeric files come before complex files
                case (.numeric, .complex):
                    return true
                    
                case (.complex, .numeric):
                    return false
                    
                // For complex files with the same base, use standard string comparison
                default:
                    return fileA.localizedStandardCompare(fileB) == .orderedAscending
                }
            }

            let sortedFiles = filtered.sorted(by: customSort)
            let uniqueFiles = Array(Set(sortedFiles))
            let uniqueSortedFiles = uniqueFiles.sorted(by: customSort)

            let imageRecords = uniqueSortedFiles.map { url in
                let filename = url.lastPathComponent
                let normalized = Self.defaultUnderscoreSlotFilename(for: filename)
                let scene7url = Self.scene7URL(for: normalized)
                let warning = self.checkNamingConvention(filename: filename)
                return Scene7ImageRecord(
                    localURL: url,
                    originalFilename: filename, // Store the original filename
                    proposedName: filename,
                    scene7URL: scene7url,
                    status: .notChecked,
                    md5Hash: nil,
                    isDuplicate: false,
                    renameError: nil,
                    namingWarning: warning,
                    thumbnail: Self.thumbnail(for: url),
                    usedDetailSlots: nil,
                    availableDetailSlots: nil,
                    detailSlotChecked: false
                )
            }
            self.records = imageRecords
            self.errorMessage = records.isEmpty ? "No image files found in selection." : nil
        }
    }

    func clearAllFiles() {
        self.records = []
        self.errorMessage = nil
    }

    @MainActor
    func checkAllImages() {
        Task {
            self.isLoading = true
            defer { self.isLoading = false }
            let recordsCopy = self.records

            let maxConcurrent = 10
            let indices = recordsCopy.indices
            // Prepare result slots
            var checkedPairs = Array<(Int, Scene7ImageRecord)?>(repeating: nil, count: recordsCopy.count)

            // Process in chunks for throttle limiting
            let indexChunks = Array(indices).chunked(into: maxConcurrent)
            for chunk in indexChunks {
                await withTaskGroup(of: (Int, Scene7ImageRecord).self) { group in
                    for idx in chunk {
                        let record = recordsCopy[idx]
                        group.addTask {
                            let checkedRecord = await self.checkedImageRecord(for: record)
                            return (idx, checkedRecord)
                        }
                    }
                    for await (idx, checkedRecord) in group {
                        checkedPairs[idx] = (idx, checkedRecord)
                    }
                }
            }

            // Reassemble in original order
            let reassembled = checkedPairs.compactMap { $0?.1 }
            self.records = reassembled
        }
    }

    @MainActor
    func checkImageForProposedName(recordID: UUID, newProposedName: String) {
        guard let idx = records.firstIndex(where: { $0.id == recordID }) else { return }
        var record = records[idx]
        // Always convert slot pattern to default underscore for URL generation
        let normalized = Self.defaultUnderscoreSlotFilename(for: newProposedName)
        record.proposedName = newProposedName
        record.scene7URL = Self.scene7URL(for: normalized)
        record.status = .notChecked
        record.isDuplicate = false
        record.md5Hash = nil
        record.usedDetailSlots = nil
        record.availableDetailSlots = nil
        record.detailSlotChecked = false
        // Duplicate check: get all other proposed names, case insensitive
        let otherNames = records.enumerated()
            .filter { $0.offset != idx }
            .map { $0.element.proposedName.lowercased() }
        record.renameError = validateRename(proposedName: record.proposedName, existingNames: otherNames)
        record.namingWarning = checkNamingConvention(filename: record.proposedName)
        records[idx] = record
    }

    // MARK: - Single-file rename (async, triggers check)
    @MainActor
    func renameFileOnDisk(recordID: UUID) async {
        guard let idx = records.firstIndex(where: { $0.id == recordID }) else { return }
        var record = records[idx]
        let otherNames = records
            .enumerated()
            .filter { $0.offset != idx }
            .map { $0.element.proposedName.lowercased() }
        let error = validateRename(proposedName: record.proposedName, existingNames: otherNames)
        record.renameError = error
        record.namingWarning = checkNamingConvention(filename: record.proposedName)
        if record.filename != record.proposedName && record.renameError == nil {
            let destination = record.localURL.deletingLastPathComponent().appendingPathComponent(record.proposedName)
            do {
                try FileManager.default.moveItem(at: record.localURL, to: destination)
                record.localURL = destination
            } catch {
                record.renameError = "Rename failed: \(error.localizedDescription)"
            }
        }
        records[idx] = record

        if record.renameError == nil {
            let updatedRecord = await self.checkedImageRecord(for: record)
            records[idx] = updatedRecord
        }
    }

    // MARK: - Async check helper - takes/returns value, never inout
    private func checkedImageRecord(for record: Scene7ImageRecord) async -> Scene7ImageRecord {
        var updated = record
        // Always use underscore-style filename for slot checks and URL
        let normalized = Self.defaultUnderscoreSlotFilename(for: updated.proposedName)
        guard let url = Self.scene7URL(for: normalized) else {
            updated.status = .error
            updated.usedDetailSlots = nil
            updated.availableDetailSlots = nil
            updated.detailSlotChecked = false
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

        // --- Detail slot checker for 001...008, always use underscore for filename ---
        let slotNumbers = (1...8).map { String(format: "%03d", $0) }
        var usedSlots: [String] = []
        var availableSlots: [String] = []

        let filenameBase = (normalized as NSString).deletingPathExtension
        let ext = (normalized as NSString).pathExtension
        // Get the "item number" before first _, or whole if no _
        let itemNumber: Substring = filenameBase.split(separator: "_").first ?? Substring(filenameBase)
        for slot in slotNumbers {
            let slotFilename = "\(itemNumber)_\(slot).\(ext)"
            guard let slotURL = Self.scene7URL(for: slotFilename) else { continue }
            let (_, slotHash) = await Self.checkScene7Image(url: slotURL, placeholderMD5: placeholderMD5)
            if let slotHash = slotHash, slotHash == placeholderMD5 {
                availableSlots.append(slot)
            } else {
                usedSlots.append(slot)
            }
        }
        updated.usedDetailSlots = usedSlots
        updated.availableDetailSlots = availableSlots
        updated.detailSlotChecked = true

        return updated
    }

    /// Converts any .NNN.ext or _NNN.ext at the end of a filename to _NNN.ext for canonical slot checking.
    static func defaultUnderscoreSlotFilename(for filename: String) -> String {
        // Handles K12345.001.jpg or K12345_001.jpg => K12345_001.jpg
        let pattern = #"^([a-zA-Z0-9]+)[\._](\d{3})\.(jpg|jpeg|png|gif|tiff|tif|bmp|webp|heic)$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let nsFilename = filename as NSString
        let range = NSRange(location: 0, length: nsFilename.length)
        if let match = regex?.firstMatch(in: filename, options: [], range: range), match.numberOfRanges == 4 {
            let base = nsFilename.substring(with: match.range(at: 1))
            let slot = nsFilename.substring(with: match.range(at: 2))
            let ext = nsFilename.substring(with: match.range(at: 3))
            return "\(base)_\(slot).\(ext)"
        }
        return filename
    }

    // MARK: - Scene7 URL Generation (NO file extension in the URL!)
    static func scene7URL(for filename: String) -> URL? {
        let lowerFilename = filename.lowercased()
        let filenameNoExtension = (lowerFilename as NSString).deletingPathExtension
        // Always convert _NNN at end to .NNN for Scene7 path
        let patternUnderscore = #"_(\d{3})$"#
        let regexUnderscore = try? NSRegularExpression(pattern: patternUnderscore, options: [])
        let rangeUnderscore = NSRange(location: 0, length: filenameNoExtension.utf16.count)
        let converted = regexUnderscore?.stringByReplacingMatches(in: filenameNoExtension, options: [], range: rangeUnderscore, withTemplate: ".$1") ?? filenameNoExtension
        let itemNumber = converted.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: true).first?
            .split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true).first
        guard let item = itemNumber, let first = item.first else { return nil }
        let itemStr = String(item)
        let lastTwo = itemStr.suffix(2)
        // CRITICAL: Do NOT include the file extension in the final URL!
        return URL(string: "https://qvc.scene7.com/is/image/QVC/\(first)/\(lastTwo)/\(converted)")
    }

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

    static func thumbnail(for url: URL) -> NSImage? {
        guard let img = NSImage(contentsOf: url) else { return nil }
        let targetSize = NSSize(width: 40, height: 40)
        return NSImage(size: targetSize, flipped: false) { rect in
            img.draw(in: rect, from: NSRect(origin: .zero, size: img.size),
                     operation: .copy, fraction: 1.0)
            return true
        }
    }

    // MARK: - Rename Logic (duplicate check included)
    func validateRename(proposedName: String, existingNames: [String]) -> String? {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Filename cannot be empty."
        }
        guard imageExtensions.contains((trimmed as NSString).pathExtension.lowercased()) else {
            return "Not a valid image file extension."
        }
        if existingNames.contains(trimmed.lowercased()) {
            return "Duplicate filename in this batch."
        }
        return nil
    }

    var canExport: Bool {
        records.allSatisfy { $0.renameError == nil } && records.contains(where: { $0.filename != $0.proposedName })
    }

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

    @MainActor
    func deleteFileAndRemoveRecord(id: UUID) async {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records[idx]
        do {
            try FileManager.default.trashItem(at: record.localURL, resultingItemURL: nil)
            records.remove(at: idx)
        } catch {
            self.errorMessage = "Failed to delete file: \(error.localizedDescription)"
        }
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
