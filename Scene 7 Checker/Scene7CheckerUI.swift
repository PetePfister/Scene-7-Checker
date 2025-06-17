import SwiftUI
import UniformTypeIdentifiers

extension Color {
    static let scene7Primary = Color(red: 0.20, green: 0.32, blue: 0.47)
    static let scene7Secondary = Color(red: 0.67, green: 0.23, blue: 0.23)
    static let scene7Accent = Color(red: 0.80, green: 0.62, blue: 0.14)
    static let scene7Background = Color(NSColor.windowBackgroundColor)
    static let scene7CardBg = Color(NSColor.controlBackgroundColor)
    static let scene7Green = Color(red: 0.26, green: 0.50, blue: 0.34)
    static let scene7Orange = Color(red: 0.80, green: 0.53, blue: 0.14)
}

// MARK: - Filter Options

enum FilterOption: String, CaseIterable {
    case all = "All Files"
    case existsOnScene7 = "Already on Scene7"
    case errors = "Has Errors"
    case namingIssues = "Naming Issues"
    case noIssues = "No Issues"
    
    var systemImage: String {
        switch self {
        case .all: return "list.bullet"
        case .existsOnScene7: return "exclamationmark.triangle.fill"
        case .errors: return "xmark.octagon.fill"
        case .namingIssues: return "textformat.abc"
        case .noIssues: return "checkmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .all: return .scene7Primary
        case .existsOnScene7: return .scene7Orange
        case .errors: return .scene7Secondary
        case .namingIssues: return .red
        case .noIssues: return .scene7Green
        }
    }
}

struct Scene7CheckerUI: View {
    @StateObject private var viewModel = Scene7CheckerLogic()
    @State private var showingImporter = false
    @FocusState private var focusedRenameID: UUID?
    @State private var dropIsTargeted: Bool = false
    @State private var selectedFilter: FilterOption = .all
    @State private var showClearConfirmation = false
    @State private var checkingTask: Task<Void, Never>?

    let columns = [
        GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 20)
    ]

    struct Scene7ButtonStyle: ButtonStyle {
        var color: Color = .scene7Primary
        var disabled: Bool = false
        
        func makeBody(configuration: Configuration) -> some View {
            let textColor = disabled ? .gray : color
            let backgroundColor = disabled ? Color.gray.opacity(0.10) : color.opacity(configuration.isPressed ? 0.12 : 0.08)
            let borderColor = disabled ? Color.gray.opacity(0.18) : color.opacity(0.35)
            let scale = configuration.isPressed ? 0.98 : 1.0
            
            return configuration.label
                .foregroundColor(textColor)
                .font(.body.weight(.medium))
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(borderColor, lineWidth: 1.6)
                        )
                )
                .scaleEffect(scale)
        }
    }

    var body: some View {
        ZStack {
            Color.scene7Background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Centered Title
                HStack {
                    Spacer()
                    Text("Scene7 Checker")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.scene7Primary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 24)
                .padding(.bottom, 10)

                // Centered Action Buttons (stylish)
                HStack(spacing: 14) {
                    Spacer()
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import Images", systemImage: "tray.and.arrow.down.fill")
                    }
                    .buttonStyle(Scene7ButtonStyle())

                    if viewModel.isLoading {
                        Button {
                            cancelChecking()
                        } label: {
                            Label("Cancel Check", systemImage: "stop.fill")
                        }
                        .buttonStyle(Scene7ButtonStyle(color: .scene7Secondary))
                    } else {
                        Button {
                            startChecking()
                        } label: {
                            Label("Check Scene7", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(Scene7ButtonStyle(disabled: viewModel.records.isEmpty))
                        .disabled(viewModel.records.isEmpty)
                    }

                    Button {
                        showClearConfirmation = true
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .buttonStyle(Scene7ButtonStyle(color: .scene7Secondary, disabled: viewModel.records.isEmpty))
                    .disabled(viewModel.records.isEmpty)
                    .alert(isPresented: $showClearConfirmation) {
                        Alert(
                            title: Text("Clear All Files?"),
                            message: Text("Are you sure you want to remove all imported files? This cannot be undone."),
                            primaryButton: .destructive(Text("Clear")) {
                                viewModel.clearAllFiles()
                            },
                            secondaryButton: .cancel()
                        )
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .animation(.easeInOut, value: viewModel.records.isEmpty)
                .animation(.easeInOut, value: viewModel.isLoading)

                // Progress bar during checking
                if viewModel.isLoading {
                    VStack(spacing: 8) {
                        ProgressView(value: progressValue)
                            .progressViewStyle(.linear)
                            .tint(.scene7Primary)
                            .frame(maxWidth: .infinity)
                        
                        HStack {
                            Text(progressText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(progressValue * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                    .transition(.opacity)
                }

                // Filter and Stats Section - Now always visible
                HStack {
                    // Filter dropdown menu
                    Menu {
                        ForEach(FilterOption.allCases, id: \.self) { option in
                            Button {
                                selectedFilter = option
                            } label: {
                                HStack {
                                    Image(systemName: option.systemImage)
                                        .foregroundColor(option.color)
                                    Text(option.rawValue)
                                    if selectedFilter == option {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: selectedFilter.systemImage)
                                .foregroundColor(selectedFilter.color)
                                .font(.caption)
                            Text(selectedFilter.rawValue)
                                .foregroundColor(.primary)
                                .font(.caption)
                            Image(systemName: "chevron.down")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.scene7CardBg)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .disabled(viewModel.isLoading)
                    .frame(width: 140) // Fixed smaller width
                    
                    Spacer()
                    
                    // Stats Display - only show when files are loaded
                    if !viewModel.records.isEmpty {
                        HStack(spacing: 16) {
                            if filterCounts.existsOnScene7 > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.scene7Orange)
                                        .font(.caption)
                                    Text("\(filterCounts.existsOnScene7)")
                                        .foregroundColor(.scene7Orange)
                                        .font(.caption.weight(.medium))
                                }
                            }
                            
                            if filterCounts.errors > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.octagon.fill")
                                        .foregroundColor(.scene7Secondary)
                                        .font(.caption)
                                    Text("\(filterCounts.errors)")
                                        .foregroundColor(.scene7Secondary)
                                        .font(.caption.weight(.medium))
                                }
                            }
                            
                            if filterCounts.namingIssues > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "textformat.abc")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                    Text("\(filterCounts.namingIssues)")
                                        .foregroundColor(.red)
                                        .font(.caption.weight(.medium))
                                }
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 4)

                // Main grid or empty dropzone
                if viewModel.records.isEmpty {
                    DropzoneEmptyView(dropIsTargeted: $dropIsTargeted) {
                        viewModel.handleDrop(providers: $0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal)
                    .padding(.top, 24)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(filteredRecordBindings) { $record in
                                RecordCard(
                                    record: $record,
                                    focusedRenameID: $focusedRenameID,
                                    viewModel: viewModel
                                )
                                .transition(.move(edge: .leading).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.2), value: record.status)
                            }
                        }
                        .padding(.top, 14)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 20)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.scene7CardBg.opacity(0.3))
                    )
                    .cornerRadius(16)
                    .padding(.top, 4)
                    .onDrop(
                        of: [UTType.fileURL],
                        isTargeted: $dropIsTargeted
                    ) { providers in
                        viewModel.handleDrop(providers: providers)
                        return true
                    }
                }

                // Error message
                if let error = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.scene7Secondary)
                        Text(error)
                            .foregroundColor(.scene7Secondary)
                            .font(.body)
                    }
                    .padding(8)
                    .background(Color.scene7Secondary.opacity(0.08))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Loading overlay
                if viewModel.isLoading {
                    ZStack {
                        Color.black.opacity(0.08).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView("Checking Scene7 images...")
                                .progressViewStyle(CircularProgressViewStyle(tint: .scene7Primary))
                                .font(.body)
                            if !progressText.isEmpty {
                                Text(progressText)
                                    .foregroundColor(.gray)
                                    .font(.subheadline)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.scene7CardBg).shadow(radius: 8))
                    }
                }
            }
            .padding(.bottom, 10)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.folder, .item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.importFiles(from: urls)
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .frame(minWidth: 700, minHeight: 400)
    }

    // MARK: - Helper Properties

    var anyChecked: Bool {
        viewModel.records.contains { $0.status != .notChecked }
    }

    var filterCounts: (existsOnScene7: Int, errors: Int, namingIssues: Int) {
        let existsOnScene7 = viewModel.records.filter { $0.status == .exists }.count
        let errors = viewModel.records.filter { $0.renameError != nil }.count
        let namingIssues = viewModel.records.filter { $0.namingWarning != nil }.count
        return (existsOnScene7, errors, namingIssues)
    }

    // Simple progress tracking since Scene7CheckerLogic doesn't have built-in progress
    var progressValue: Double {
        guard !viewModel.records.isEmpty else { return 0 }
        let checkedCount = viewModel.records.filter { $0.status != .notChecked }.count
        return Double(checkedCount) / Double(viewModel.records.count)
    }

    var progressText: String {
        if viewModel.isLoading {
            let checkedCount = viewModel.records.filter { $0.status != .notChecked }.count
            return "Checked \(checkedCount) of \(viewModel.records.count) images"
        }
        return ""
    }

    // MARK: - Filtering Logic

    var filteredRecordBindings: [Binding<Scene7ImageRecord>] {
        let editingIDs: Set<UUID> = Set([focusedRenameID].compactMap { $0 })
        
        let filteredRecords = viewModel.records.filter { record in
            // Always show files being edited
            if editingIDs.contains(record.id) {
                return true
            }
            
            switch selectedFilter {
            case .all:
                return true
            case .existsOnScene7:
                return record.status == .exists
            case .errors:
                return record.renameError != nil
            case .namingIssues:
                return record.namingWarning != nil
            case .noIssues:
                return record.status == .unique && record.renameError == nil && record.namingWarning == nil
            }
        }
        
        return filteredRecords.map { record in
            Binding(
                get: { record },
                set: { updated in
                    if let idx = viewModel.records.firstIndex(where: { $0.id == record.id }) {
                        viewModel.records[idx] = updated
                    }
                }
            )
        }
    }

    // MARK: - Helper Methods

    func startChecking() {
        checkingTask = Task {
            viewModel.checkAllImages()
        }
    }

    func cancelChecking() {
        checkingTask?.cancel()
        checkingTask = nil
        viewModel.isLoading = false
    }
}

// MARK: - Dropzone Empty State

struct DropzoneEmptyView: View {
    @Binding var dropIsTargeted: Bool
    var onDrop: ([NSItemProvider]) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "tray.and.arrow.down.fill")
                .resizable()
                .frame(width: 64, height: 64)
                .foregroundColor(.accentColor)
                .opacity(dropIsTargeted ? 1.0 : 0.6)
                .scaleEffect(dropIsTargeted ? 1.1 : 1.0)
                .animation(.easeInOut, value: dropIsTargeted)
            Text("Drag and drop images or folders here to begin")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.scene7CardBg)
        )
        .onDrop(
            of: [UTType.fileURL],
            isTargeted: $dropIsTargeted,
            perform: { providers in
                onDrop(providers)
                return true
            }
        )
    }
}

// MARK: - Record Card (Image Record Display)

struct RecordCard: View {
    @Binding var record: Scene7ImageRecord
    @FocusState.Binding var focusedRenameID: UUID?
    var viewModel: Scene7CheckerLogic
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                if let thumbnail = record.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.10))
                        )
                        .clipped()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.10))
                            .frame(width: 48, height: 48)
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.scene7Primary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.filename)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.scene7Primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if record.status == .exists {
                        Text("Image already exists")
                            .font(.caption)
                            .foregroundColor(.scene7Orange)
                            .padding(.top, 2)
                    }
                }
                Spacer()
                statusBadge(for: record.status)
                    .padding(.trailing, 2)
                // --- Delete Button ---
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.scene7Secondary)
                }
                .buttonStyle(.plain)
                .help("Delete this file from disk and remove from list")
                .alert(isPresented: $showDeleteConfirm) {
                    Alert(
                        title: Text("Delete File?"),
                        message: Text("Are you sure you want to permanently delete this file from disk? This cannot be undone."),
                        primaryButton: .destructive(Text("Delete")) {
                            Task {
                                await viewModel.deleteFileAndRemoveRecord(id: record.id)
                            }
                        },
                        secondaryButton: .cancel()
                    )
                }
            }

            // --- Rename field and action buttons ---
            HStack {
                TextField("Rename", text: $record.proposedName)
                    .focused($focusedRenameID, equals: record.id)
                    .foregroundColor(record.renameError == nil ? .scene7Primary : .red)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(record.renameError == nil ? Color.gray.opacity(0.2) : .red, lineWidth: 1)
                    )
                    .onChange(of: record.proposedName) { newValue in
                        let otherNames = viewModel.records
                            .filter { $0.id != record.id }
                            .map { $0.proposedName.lowercased() }
                        record.renameError = viewModel.validateRename(proposedName: newValue, existingNames: otherNames)
                        viewModel.checkImageForProposedName(recordID: record.id, newProposedName: newValue)
                    }
                Button {
                    record.proposedName = record.originalFilename // Reset to original, not current filename
                    focusedRenameID = nil
                    viewModel.checkImageForProposedName(recordID: record.id, newProposedName: record.originalFilename)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundColor(.scene7Secondary)
                        .opacity(0.7)
                }
                .buttonStyle(.plain)
                .help("Reset to original filename")
                Button {
                    Task {
                        await viewModel.renameFileOnDisk(recordID: record.id)
                    }
                } label: {
                    Label("Rename", systemImage: "arrow.triangle.2.circlepath")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderedProminent)
                .disabled(record.renameError != nil || record.filename == record.proposedName)
                .help("Rename this file on disk")
            }
            if let error = record.renameError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, -2)
                    .transition(.opacity)
            }
            // Only show naming warning when not editing
            if let warning = record.namingWarning, focusedRenameID != record.id {
                Text(warning)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.red)
                    .padding(.top, -2)
                    .transition(.opacity)
            }

            // --- Used and Available detail slots display with FlowLayout ---
            VStack(alignment: .leading, spacing: 8) {
                if let used = record.usedDetailSlots, !used.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Used detail slots:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        FlowLayout(spacing: 4) {
                            ForEach(used, id: \.self) { slot in
                                Text(slot)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.scene7Orange.opacity(0.15))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                
                if let available = record.availableDetailSlots, !available.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Available detail slots (001-008):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        FlowLayout(spacing: 4) {
                            ForEach(available, id: \.self) { slot in
                                Text(slot)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.scene7Green.opacity(0.15))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.scene7CardBg,
                                Color.scene7CardBg.opacity(0.8)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.gray.opacity(0.3),
                                Color.gray.opacity(0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .animation(.easeInOut(duration: 0.2), value: record.status)
    }

    func statusBadge(for status: Scene7ImageStatus) -> some View {
        switch status {
        case .notChecked:
            return Label("Not checked", systemImage: "questionmark.circle")
                .labelStyle(.iconOnly)
                .foregroundColor(.gray)
                .font(.system(size: 20))
                .help("Image has not been checked against Scene7 yet")
        case .exists:
            return Label("Exists", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.iconOnly)
                .foregroundColor(.scene7Orange)
                .font(.system(size: 32, weight: .bold))
                .help("Image already exists on Scene7 - this may cause a conflict")
        case .unique:
            return Label("Unique", systemImage: "checkmark.seal.fill")
                .labelStyle(.iconOnly)
                .foregroundColor(.scene7Green)
                .font(.system(size: 32, weight: .bold))
                .help("Image is unique and ready to upload to Scene7")
        case .error:
            return Label("Error", systemImage: "xmark.octagon.fill")
                .labelStyle(.iconOnly)
                .foregroundColor(.scene7Secondary)
                .font(.system(size: 20))
                .help("Error checking Scene7 image URL - check network connection or filename format")
        }
    }
}

// MARK: - FlowLayout for wrapping slot badges

struct FlowLayout: Layout {
    let spacing: CGFloat
    
    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX,
                                    y: bounds.minY + result.frames[index].minY),
                         proposal: ProposedViewSize(result.frames[index].size))
        }
    }
    
    struct FlowResult {
        let size: CGSize
        let frames: [CGRect]
        
        init(in maxWidth: CGFloat, subviews: LayoutSubviews, spacing: CGFloat) {
            var frames: [CGRect] = []
            var currentRow: [LayoutSubview] = []
            var currentRowWidth: CGFloat = 0
            var totalHeight: CGFloat = 0
            var maxRowHeight: CGFloat = 0
            
            for subview in subviews {
                let subviewSize = subview.sizeThatFits(.unspecified)
                
                if currentRowWidth + subviewSize.width + (currentRow.isEmpty ? 0 : spacing) <= maxWidth {
                    currentRow.append(subview)
                    currentRowWidth += subviewSize.width + (currentRow.count > 1 ? spacing : 0)
                    maxRowHeight = max(maxRowHeight, subviewSize.height)
                } else {
                    // Place current row
                    totalHeight += maxRowHeight
                    var x: CGFloat = 0
                    for (_, rowSubview) in currentRow.enumerated() {
                        let size = rowSubview.sizeThatFits(.unspecified)
                        frames.append(CGRect(x: x, y: totalHeight - maxRowHeight, width: size.width, height: size.height))
                        x += size.width + spacing
                    }
                    
                    // Start new row
                    totalHeight += spacing
                    currentRow = [subview]
                    currentRowWidth = subviewSize.width
                    maxRowHeight = subviewSize.height
                }
            }
            
            // Place final row
            if !currentRow.isEmpty {
                totalHeight += maxRowHeight
                var x: CGFloat = 0
                for rowSubview in currentRow {
                    let size = rowSubview.sizeThatFits(.unspecified)
                    frames.append(CGRect(x: x, y: totalHeight - maxRowHeight, width: size.width, height: size.height))
                    x += size.width + spacing
                }
            }
            
            self.frames = frames
            self.size = CGSize(width: maxWidth, height: totalHeight)
        }
    }
}

struct Scene7CheckerUI_Previews: PreviewProvider {
    static var previews: some View {
        Scene7CheckerUI()
    }
}
