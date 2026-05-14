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

    // Vendor swatch pattern: Item_ColorCode_ColorName_101|102.ext -> incorrect; expected Item_ColorCode_101|102.ext
    let vendorSwatchPattern = #"^[A-Za-z0-9]+_\d{3}_[A-Za-z0-9]+_10[12]\.(jpg|jpeg|png|gif|tiff|tif|bmp|webp|heic)$"#

    // MARK: - Toggle Marked OK
    
    @MainActor
    func toggleMarkedOK(recordID: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[idx].userMarkedOK.toggle()
    }

    // MARK: - Batch Rename to Scene7 Format

    func getBatchRenamePreview() -> (count: Int, examples: [String]) {
        let eligibleRecords = records.filter { record in
            // include regular underscore-to-dot renames, swatch renames, and model size-guide conversions
            canBatchRename(filename: record.proposedName) || canBatchRenameModelSizeGuide(filename: record.proposedName)
        }

        let examples = Array(eligibleRecords.prefix(5)).compactMap { record in
            // prefer model conversion if applicable
            if let modelConverted = convertModelSizeGuideToScene7FormatIfNeeded(filename: record.proposedName) {
                return "\(record.proposedName) → \(modelConverted)"
            } else if canBatchRename(filename: record.proposedName) {
                let newName = convertToScene7Format(filename: record.proposedName)
                return "\(record.proposedName) → \(newName)"
            }
            return nil
        }

        return (count: eligibleRecords.count, examples: examples)
    }

    private func canBatchRename(filename: String) -> Bool {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension.lowercased()

        guard imageExtensions.contains(ext) else { return false }

        // Pattern for regular slots: ItemNumber_001 to ItemNumber_008
        let slotPattern = #"^[A-Za-z0-9]+_00[1-8]$"#

        // Pattern for swatch files: ItemNumber_ABC_101 or ItemNumber_ABC_102
        let swatchPattern = #"^[A-Za-z0-9]+_[A-Za-z0-9]{3}_10[12]$"#

        let slotRegex = try? NSRegularExpression(pattern: slotPattern, options: .caseInsensitive)
        let swatchRegex = try? NSRegularExpression(pattern: swatchPattern, options: .caseInsensitive)

        let range = NSRange(location: 0, length: base.utf16.count)

        return slotRegex?.firstMatch(in: base, options: [], range: range) != nil ||
               swatchRegex?.firstMatch(in: base, options: [], range: range) != nil
    }

    // detect model size-guide files that are eligible for batch rename (end in '!' before extension)
    private func canBatchRenameModelSizeGuide(filename: String) -> Bool {
        let rawBase = (filename as NSString).deletingPathExtension
        guard rawBase.hasSuffix("!") else { return false }
        let withoutBang = String(rawBase.dropLast())
        // two patterns we care about:
        // Item_Color_Size_Model_Slot!
        // Item_Size_Model_Slot!
        let twoNumericPattern = #"^[A-Za-z0-9]+_\d{3}_\d{3}_[A-Za-z0-9]+_\d{3}$"#
        let oneNumericPattern = #"^[A-Za-z0-9]+_\d{3}_[A-Za-z0-9]+_\d{3}$"#
        let range = NSRange(location: 0, length: withoutBang.utf16.count)
        if let regex2 = try? NSRegularExpression(pattern: twoNumericPattern, options: .caseInsensitive),
           regex2.firstMatch(in: withoutBang, options: [], range: range) != nil {
            return true
        }
        if let regex1 = try? NSRegularExpression(pattern: oneNumericPattern, options: .caseInsensitive),
           regex1.firstMatch(in: withoutBang, options: [], range: range) != nil {
            return true
        }
        return false
    }

    private func convertToScene7Format(filename: String) -> String {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        // Convert ItemNumber_001 to ItemNumber.001
        let slotPattern = #"^([A-Za-z0-9]+)_(\d{3})$"#
        let slotRegex = try? NSRegularExpression(pattern: slotPattern, options: .caseInsensitive)
        let slotRange = NSRange(location: 0, length: base.utf16.count)

        if let match = slotRegex?.firstMatch(in: base, options: [], range: slotRange) {
            let nsBase = base as NSString
            let itemNumber = nsBase.substring(with: match.range(at: 1))
            let slotNumber = nsBase.substring(with: match.range(at: 2))
            return "\(itemNumber).\(slotNumber).\(ext)"
        }

        // Convert ItemNumber_ABC_101 to ItemNumber_ABC.101
        let swatchPattern = #"^([A-Za-z0-9]+_[A-Za-z0-9]{3})_(\d{3})$"#
        let swatchRegex = try? NSRegularExpression(pattern: swatchPattern, options: .caseInsensitive)

        if let match = swatchRegex?.firstMatch(in: base, options: [], range: slotRange) {
            let nsBase = base as NSString
            let prefix = nsBase.substring(with: match.range(at: 1))
            let suffix = nsBase.substring(with: match.range(at: 2))
            return "\(prefix).\(suffix).\(ext)"
        }

        return filename // Return unchanged if no pattern matches
    }

    // Converts model size-guide filenames to Scene7 format if needed, returns new filename or nil
    private func convertModelSizeGuideToScene7FormatIfNeeded(filename: String) -> String? {
        let rawBase = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        guard rawBase.hasSuffix("!") else { return nil }
        let withoutBang = String(rawBase.dropLast())
        let cleaned = cleanupFilename(withoutBang)

        // Pattern: Item_ColorCode_SizeCode_Model_Slot -> keep first numeric (color code)
        let twoNumericPattern = #"^([A-Za-z0-9]+)_(\d{3})_(\d{3})_[A-Za-z0-9]+_(\d{3})$"#
        if let regex = try? NSRegularExpression(pattern: twoNumericPattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: cleaned.utf16.count)
            if let match = regex.firstMatch(in: cleaned, options: [], range: range), match.numberOfRanges == 5 {
                let ns = cleaned as NSString
                let item = ns.substring(with: match.range(at: 1))
                let colorCode = ns.substring(with: match.range(at: 2))
                let slot = ns.substring(with: match.range(at: 4))
                // produce Item_ColorCode.Slot.ext
                return "\(item)_\(colorCode).\(slot).\(ext)"
            }
        }

        // Pattern: Item_SizeCode_Model_Slot -> drop the size code
        let oneNumericPattern = #"^([A-Za-z0-9]+)_(\d{3})_[A-Za-z0-9]+_(\d{3})$"#
        if let regex = try? NSRegularExpression(pattern: oneNumericPattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: cleaned.utf16.count)
            if let match = regex.firstMatch(in: cleaned, options: [], range: range), match.numberOfRanges == 4 {
                let ns = cleaned as NSString
                let item = ns.substring(with: match.range(at: 1))
                let slot = ns.substring(with: match.range(at: 3))
                // produce Item.Slot.ext
                return "\(item).\(slot).\(ext)"
            }
        }

        return nil
    }

    @MainActor
    func batchRenameToScene7Format() async -> (success: Int, errors: [String]) {
        var successCount = 0
        var errors: [String] = []

        for (index, record) in records.enumerated() {
            let proposed = record.proposedName

            // First, handle model size-guide conversions if applicable
            if let modelConverted = convertModelSizeGuideToScene7FormatIfNeeded(filename: proposed) {
                let destination = record.localURL.deletingLastPathComponent().appendingPathComponent(modelConverted)
                do {
                    try FileManager.default.moveItem(at: record.localURL, to: destination)

                    // Update the record
                    var updatedRecord = record
                    updatedRecord.localURL = destination
                    updatedRecord.proposedName = modelConverted
                    updatedRecord.scene7URL = Self.scene7URL(for: Self.defaultUnderscoreSlotFilename(for: modelConverted))
                    updatedRecord.status = .notChecked
                    updatedRecord.renameError = nil
                    updatedRecord.namingWarning = checkNamingConvention(filename: modelConverted)

                    records[index] = updatedRecord
                    successCount += 1
                    continue
                } catch {
                    errors.append("Failed to rename \(record.proposedName): \(error.localizedDescription)")
                    continue
                }
            }

            // Otherwise, handle the existing underscore->dot conversions (slots & swatches)
            if canBatchRename(filename: proposed) {
                let newName = convertToScene7Format(filename: proposed)
                let destination = record.localURL.deletingLastPathComponent().appendingPathComponent(newName)

                do {
                    try FileManager.default.moveItem(at: record.localURL, to: destination)

                    // Update the record
                    var updatedRecord = record
                    updatedRecord.localURL = destination
                    updatedRecord.proposedName = newName
                    updatedRecord.scene7URL = Self.scene7URL(for: Self.defaultUnderscoreSlotFilename(for: newName))
                    updatedRecord.status = .notChecked
                    updatedRecord.renameError = nil
                    updatedRecord.namingWarning = checkNamingConvention(filename: newName)

                    records[index] = updatedRecord
                    successCount += 1
                } catch {
                    errors.append("Failed to rename \(record.proposedName): \(error.localizedDescription)")
                }
            }
        }

        return (success: successCount, errors: errors)
    }

    // MARK: - Name Suggestion Logic

    func generateNameSuggestion(for filename: String, availableSlots: [String]?) -> NameSuggestion? {
        let rawBase = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension.lowercased()

        guard imageExtensions.contains(ext) else { return nil }

        // If this is a model size-guide (ends with '!'), do not produce suggestions or warnings in the app UI.
        // The model size-guides are handled by batch rename when the user explicitly requests it.
        if rawBase.hasSuffix("!") {
            return nil
        }

        // Clean up common issues first for other suggestion strategies
        let cleanedBase = cleanupFilename(rawBase)

        // Check vendor-swatch pattern first (Item_ColorCode_ColorName_101/102)
        if let vendorSuggestion = suggestForVendorSwatch(base: cleanedBase, ext: ext) {
            return vendorSuggestion
        }

        // Check if it already matches a valid pattern
        if isValidFilename("\(cleanedBase).\(ext)") {
            return nil // No suggestion needed
        }

        // Try different suggestion strategies
        if let suggestion = suggestForMissingSuffix(base: cleanedBase, ext: ext, availableSlots: availableSlots) {
            return suggestion
        }

        if let suggestion = suggestForInvalidSwatch(base: cleanedBase, ext: ext) {
            return suggestion
        }

        if let suggestion = suggestForInvalidSlot(base: cleanedBase, ext: ext, availableSlots: availableSlots) {
            return suggestion
        }

        if let suggestion = suggestForSwatchWithSlot(base: cleanedBase, ext: ext) {
            return suggestion
        }

        return nil
    }

    private func cleanupFilename(_ base: String) -> String {
        var cleaned = base

        // Remove trailing exclamation marks used to indicate model size guides (we clean them for parsing,
        // but we do not suggest renames for them on import — batch rename will handle conversions)
        cleaned = cleaned.replacingOccurrences(of: "!", with: "")

        // Fix common separator issues
        cleaned = cleaned.replacingOccurrences(of: "-", with: "_")
        cleaned = cleaned.replacingOccurrences(of: " ", with: "_")

        // Fix double underscores
        while cleaned.contains("__") {
            cleaned = cleaned.replacingOccurrences(of: "__", with: "_")
        }

        // Remove trailing underscore
        if cleaned.hasSuffix("_") {
            cleaned = String(cleaned.dropLast())
        }

        return cleaned
    }

    private func isValidFilename(_ filename: String) -> Bool {
        return checkNamingConvention(filename: filename) == nil
    }

    // MARK: - Vendor swatch: Item_ColorCode_ColorName_101|102 -> suggest Item_ColorCode_101|102
    private func suggestForVendorSwatch(base: String, ext: String) -> NameSuggestion? {
        // match: ItemNumber_012_Black_102  -> groups: 1=item,2=code,3=colorName,4=suffix
        let vendorPattern = #"^([A-Za-z0-9]+)_(\d{3})_([A-Za-z0-9]+)_(10[12])$"#
        let regex = try? NSRegularExpression(pattern: vendorPattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: base.utf16.count)

        if let match = regex?.firstMatch(in: base, options: [], range: range) {
            let nsBase = base as NSString
            let itemNumber = nsBase.substring(with: match.range(at: 1))
            let colorCode = nsBase.substring(with: match.range(at: 2))
            let suffix = nsBase.substring(with: match.range(at: 4)) // 101 or 102
            let suggestedName = "\(itemNumber)_\(colorCode)_\(suffix).\(ext)"
            return NameSuggestion(
                originalName: "\(base).\(ext)",
                suggestedName: suggestedName,
                reason: "Vendor swatch includes color name — correct format is Item_ColorCode_101/102"
            )
        }
        return nil
    }

    private func suggestForMissingSuffix(base: String, ext: String, availableSlots: [String]?) -> NameSuggestion? {
        // Pattern: ItemNumber (no suffix)
        let itemPattern = #"^[A-Za-z0-9]+$"#
        let regex = try? NSRegularExpression(pattern: itemPattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: base.utf16.count)

        if regex?.firstMatch(in: base, options: [], range: range) != nil {
            let nextSlot = getNextAvailableSlot(availableSlots: availableSlots)
            let suggestedName = "\(base)_\(nextSlot).\(ext)"
            return NameSuggestion(
                originalName: "\(base).\(ext)",
                suggestedName: suggestedName,
                reason: "Missing slot number"
            )
        }

        return nil
    }

    private func suggestForInvalidSwatch(base: String, ext: String) -> NameSuggestion? {
        // Pattern: ItemNumber_ABC_DEF (where DEF is not 101/102)
        let swatchPattern = #"^([A-Za-z0-9]+)_([A-Za-z0-9]{3})_(.+)$"#
        let regex = try? NSRegularExpression(pattern: swatchPattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: base.utf16.count)

        if let match = regex?.firstMatch(in: base, options: [], range: range) {
            let nsBase = base as NSString
            let itemNumber = nsBase.substring(with: match.range(at: 1))
            let sequence = nsBase.substring(with: match.range(at: 2))
            let suffix = nsBase.substring(with: match.range(at: 3))

            // Check if sequence is exactly 3 alphanumeric characters
            let sequencePattern = #"^[A-Za-z0-9]{3}$"#
            let sequenceRegex = try? NSRegularExpression(pattern: sequencePattern, options: .caseInsensitive)
            let sequenceRange = NSRange(location: 0, length: sequence.utf16.count)

            if sequenceRegex?.firstMatch(in: sequence, options: [], range: sequenceRange) != nil {
                // Valid sequence, fix the suffix
                if suffix != "101" && suffix != "102" {
                    let suggestedName = "\(itemNumber)_\(sequence)_102.\(ext)"
                    return NameSuggestion(
                        originalName: "\(base).\(ext)",
                        suggestedName: suggestedName,
                        reason: "Invalid swatch number, should be 101 or 102"
                    )
                }
            } else {
                // Invalid sequence length
                let suggestedName = "\(itemNumber)_???_102.\(ext)"
                return NameSuggestion(
                    originalName: "\(base).\(ext)",
                    suggestedName: suggestedName,
                    reason: "Swatch sequence must be exactly 3 characters"
                )
            }
        }

        // Pattern: ItemNumber_ABC (missing 101/102)
        let missingSwatchPattern = #"^([A-Za-z0-9]+)_([A-Za-z0-9]{3})$"#
        let missingRegex = try? NSRegularExpression(pattern: missingSwatchPattern, options: .caseInsensitive)

        if let match = missingRegex?.firstMatch(in: base, options: [], range: range) {
            let nsBase = base as NSString
            let itemNumber = nsBase.substring(with: match.range(at: 1))
            let sequence = nsBase.substring(with: match.range(at: 2))

            let suggestedName = "\(itemNumber)_\(sequence)_102.\(ext)"
            return NameSuggestion(
                originalName: "\(base).\(ext)",
                suggestedName: suggestedName,
                reason: "Missing swatch number (101 or 102)"
            )
        }

        return nil
    }

    private func suggestForInvalidSlot(base: String, ext: String, availableSlots: [String]?) -> NameSuggestion? {
        // Pattern: ItemNumber_NNN where NNN is not 001-008, 101, or 102
        let slotPattern = #"^([A-Za-z0-9]+)_(\d{1,3})$"#
        let regex = try? NSRegularExpression(pattern: slotPattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: base.utf16.count)

        if let match = regex?.firstMatch(in: base, options: [], range: range) {
            let nsBase = base as NSString
            let itemNumber = nsBase.substring(with: match.range(at: 1))
            let slotString = nsBase.substring(with: match.range(at: 2))

            if let slotNumber = Int(slotString) {
                // Check if it's a valid slot (001-008, 101, 102)
                let validSlots = (1...8).map { String(format: "%03d", $0) } + ["101", "102"]
                let paddedSlot = String(format: "%03d", slotNumber)

                if !validSlots.contains(paddedSlot) && slotNumber > 20 {
                    // Convert to swatch format if > 020
                    let suggestedName = "\(itemNumber)_\(paddedSlot)_102.\(ext)"
                    return NameSuggestion(
                        originalName: "\(base).\(ext)",
                        suggestedName: suggestedName,
                        reason: "Invalid slot number, converting to swatch format"
                    )
                } else if slotNumber > 8 && slotNumber <= 20 {
                    // Suggest next available slot for 009-020
                    let nextSlot = getNextAvailableSlot(availableSlots: availableSlots)
                    let suggestedName = "\(itemNumber)_\(nextSlot).\(ext)"
                    return NameSuggestion(
                        originalName: "\(base).\(ext)",
                        suggestedName: suggestedName,
                        reason: "Invalid slot number, using next available slot"
                    )
                } else if slotString.count < 3 {
                    // Pad single or double digits
                    let paddedSlot = String(format: "%03d", slotNumber)
                    if (1...8).contains(slotNumber) {
                        let suggestedName = "\(itemNumber)_\(paddedSlot).\(ext)"
                        return NameSuggestion(
                            originalName: "\(base).\(ext)",
                            suggestedName: suggestedName,
                            reason: "Slot number needs zero padding"
                        )
                    }
                }
            }
        }

        // Pattern: ItemNumber_ABC where ABC contains letters (not a valid sequence)
        let letterSlotPattern = #"^([A-Za-z0-9]+)_([A-Za-z0-9]*[A-Za-z][A-Za-z0-9]*)$"#
        let letterRegex = try? NSRegularExpression(pattern: letterSlotPattern, options: .caseInsensitive)

        if let match = letterRegex?.firstMatch(in: base, options: [], range: range) {
            let nsBase = base as NSString
            let itemNumber = nsBase.substring(with: match.range(at: 1))
            let sequence = nsBase.substring(with: match.range(at: 2))

            if sequence.count == 3 {
                // Treat as swatch sequence
                let suggestedName = "\(itemNumber)_\(sequence)_102.\(ext)"
                return NameSuggestion(
                    originalName: "\(base).\(ext)",
                    suggestedName: suggestedName,
                    reason: "Converting to swatch format"
                )
            } else {
                // Invalid sequence length
                let suggestedName = "\(itemNumber)_\(sequence)_102.\(ext)"
                return NameSuggestion(
                    originalName: "\(base).\(ext)",
                    suggestedName: suggestedName,
                    reason: "Converting to swatch format"
                )
            }
        }

        return nil
    }

    private func suggestForSwatchWithSlot(base: String, ext: String) -> NameSuggestion? {
        // Pattern: ItemNumber_ABC_001 (has sequence but slot number instead of 101/102)
        let swatchSlotPattern = #"^([A-Za-z0-9]+)_([A-Za-z0-9]{3})_(\d{3})$"#
        let regex = try? NSRegularExpression(pattern: swatchSlotPattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: base.utf16.count)

        if let match = regex?.firstMatch(in: base, options: [], range: range) {
            let nsBase = base as NSString
            let itemNumber = nsBase.substring(with: match.range(at: 1))
            let sequence = nsBase.substring(with: match.range(at: 2))
            let slot = nsBase.substring(with: match.range(at: 3))

            if slot != "101" && slot != "102" {
                let suggestedName = "\(itemNumber)_\(sequence)_102.\(ext)"
                return NameSuggestion(
                    originalName: "\(base).\(ext)",
                    suggestedName: suggestedName,
                    reason: "Swatch file should end with 101 or 102"
                )
            }
        }

        return nil
    }

    private func getNextAvailableSlot(availableSlots: [String]?) -> String {
        guard let availableSlots = availableSlots, !availableSlots.isEmpty else {
            return "001" // Default to 001 if no slot info available
        }

        // Find the lowest available slot
        for i in 1...8 {
            let slot = String(format: "%03d", i)
            if availableSlots.contains(slot) {
                return slot
            }
        }

        return "001" // Fallback to 001
    }

    // MARK: - Naming Convention Check
    func checkNamingConvention(filename: String) -> String? {
        // If it's a model size-guide (ends with '!'), consider it valid in the app (no naming warning).
        // We only perform transformations on explicit user action (batch rename).
        let rawBase = (filename as NSString).deletingPathExtension
        if rawBase.hasSuffix("!") {
            return nil
        }

        // Check vendor swatch pattern first (flag it as incorrect)
        if let regexVendor = try? NSRegularExpression(pattern: vendorSwatchPattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: (filename as NSString).length)
            if regexVendor.firstMatch(in: filename, options: [], range: range) != nil {
                return "Incorrect swatch format (contains color name). Expected Item_ColorCode_101/102"
            }
        }

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

                // Generate name suggestion immediately (no slots yet)
                let suggestion = self.generateNameSuggestion(for: filename, availableSlots: nil)

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
                    detailSlotChecked: false,
                    nameSuggestion: suggestion
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

        // Update name suggestion based on new proposed name and any known available slots
        let suggestion = generateNameSuggestion(for: newProposedName, availableSlots: record.availableDetailSlots)
        record.nameSuggestion = suggestion

        records[idx] = record
    }

    // MARK: - Apply Name Suggestion
    @MainActor
    func applyNameSuggestion(recordID: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == recordID }) else { return }
        var record = records[idx]

        if let suggestion = record.nameSuggestion {
            record.proposedName = suggestion.suggestedName
            record.nameSuggestion = nil // Clear suggestion after applying

            // Update Scene7 URL and validation
            let normalized = Self.defaultUnderscoreSlotFilename(for: suggestion.suggestedName)
            record.scene7URL = Self.scene7URL(for: normalized)
            record.status = .notChecked
            record.isDuplicate = false
            record.md5Hash = nil
            record.usedDetailSlots = nil
            record.availableDetailSlots = nil
            record.detailSlotChecked = false

            // Validate the suggestion
            let otherNames = records.enumerated()
                .filter { $0.offset != idx }
                .map { $0.element.proposedName.lowercased() }
            record.renameError = validateRename(proposedName: record.proposedName, existingNames: otherNames)
            record.namingWarning = checkNamingConvention(filename: record.proposedName)

            records[idx] = record
        }
    }

    // MARK: - Reject Name Suggestion
    @MainActor
    func rejectNameSuggestion(recordID: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == recordID }) else { return }
        var record = records[idx]
        record.nameSuggestion = nil
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

        // Update name suggestion with available slots information
        if updated.nameSuggestion != nil {
            let suggestion = generateNameSuggestion(for: updated.proposedName, availableSlots: availableSlots)
            updated.nameSuggestion = suggestion
        }

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

    // MARK: - CSV Export

    func generateCSV() -> String {
        func csvField(_ s: String) -> String {
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }

        let header = [
            csvField("Filename"),
            csvField("Proposed Name"),
            csvField("Scene7 URL"),
            csvField("Status"),
            csvField("Duplicate"),
            csvField("Naming Warning")
        ].joined(separator: ",")

        var lines: [String] = [header]
        for record in records {
            let statusStr: String
            switch record.status {
            case .exists:     statusStr = "Already Loaded"
            case .unique:     statusStr = "Not Loaded"
            case .notChecked: statusStr = "Not Checked"
            case .error:      statusStr = "Error"
            }

            let row = [
                csvField(record.filename),
                csvField(record.proposedName),
                csvField(record.scene7URL?.absoluteString ?? ""),
                csvField(statusStr),
                csvField(record.isDuplicate ? "Yes" : "No"),
                csvField(record.namingWarning ?? "")
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    func exportCSV() {
        let csvString = generateCSV()
        let panel = NSSavePanel()
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.commaSeparatedText]
        } else {
            panel.allowedFileTypes = ["csv"]
        }
        panel.nameFieldStringValue = "Scene7-Results.csv"
        panel.title = "Export CSV"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try csvString.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self.errorMessage = "Failed to save CSV: \(error.localizedDescription)"
            }
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
