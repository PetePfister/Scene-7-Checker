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

struct Scene7CheckerUI: View {
    @StateObject private var viewModel = Scene7CheckerLogic()
    @State private var showingImporter = false
    @FocusState private var focusedRenameID: UUID?
    @State private var dropIsTargeted: Bool = false
    @State private var showOnlyExists = false
    @State private var showClearConfirmation = false

    let columns = [
        GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 18)
    ]

    struct Scene7ButtonStyle: ButtonStyle {
        var color: Color = .scene7Primary
        var disabled: Bool = false
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundColor(disabled ? .gray : color)
                .font(.body.weight(.medium))
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(disabled ? Color.gray.opacity(0.10) : color.opacity(configuration.isPressed ? 0.12 : 0.08))
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(disabled ? Color.gray.opacity(0.18) : color.opacity(0.35), lineWidth: 1.6)
                    }
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
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

                    Button {
                        viewModel.checkAllImages()
                    } label: {
                        Label("Check Scene7", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(Scene7ButtonStyle(disabled: viewModel.records.isEmpty || viewModel.isLoading))
                    .disabled(viewModel.records.isEmpty || viewModel.isLoading)

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

                    Button {
                        viewModel.exportCSV()
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(Scene7ButtonStyle(disabled: viewModel.records.isEmpty))
                    .disabled(viewModel.records.isEmpty)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .animation(.easeInOut, value: viewModel.records.isEmpty)
                .animation(.easeInOut, value: viewModel.canExport)

                // Error count only: Show only if there are errors
                if !viewModel.records.isEmpty,
                   viewModel.records.contains(where: { $0.renameError != nil }) {
                    HStack {
                        Text("Errors: \(viewModel.records.filter { $0.renameError != nil }.count)")
                            .foregroundColor(.scene7Secondary)
                        Spacer()
                    }
                    .font(.subheadline)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                    .transition(.opacity)
                }

                // Filter Toggle
                HStack {
                    Toggle("Show only images already on Scene7", isOn: $showOnlyExists)
                        .toggleStyle(SwitchToggleStyle())
                        .disabled(!anyChecked)
                    Spacer()
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
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(recordBindings) { $record in
                                RecordCard(
                                    record: $record,
                                    focusedRenameID: $focusedRenameID,
                                    viewModel: viewModel
                                )
                                .transition(.move(edge: .leading).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.2), value: record.status)
                            }
                        }
                        .padding(.top, 10)
                        .padding(.horizontal, 6)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.scene7CardBg)
                    )
                    .cornerRadius(14)
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
                            Text("Checking your images...")
                                .foregroundColor(.gray)
                                .font(.subheadline)
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

    var anyChecked: Bool {
        viewModel.records.contains { $0.status != .notChecked }
    }

    // --- Filtering logic ---
    var recordBindings: [Binding<Scene7ImageRecord>] {
        let checked = anyChecked
        let editingIDs: Set<UUID> = Set([
            focusedRenameID
        ].compactMap { $0 })
        let source: [Scene7ImageRecord]
        if showOnlyExists && checked {
            source = viewModel.records.filter {
                $0.status == .exists
                || editingIDs.contains($0.id)
                || $0.renameError != nil
                || $0.proposedName != $0.filename // show if renamed
                || $0.namingWarning != nil   // keep files with a naming warning visible!
            }
        } else {
            source = viewModel.records
        }
        return source.map { record in
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
        VStack(spacing: 8) {
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
                    record.proposedName = record.filename
                    focusedRenameID = nil
                    viewModel.checkImageForProposedName(recordID: record.id, newProposedName: record.filename)
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

            // --- Used and Available slots display below the rename field ---
            VStack(alignment: .leading, spacing: 2) {
                if let used = record.usedDetailSlots, !used.isEmpty {
                    HStack(spacing: 4) {
                        Text("Used slots:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(used, id: \.self) { slot in
                            Text(slot)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.scene7Orange.opacity(0.13))
                                .cornerRadius(4)
                        }
                    }
                }
                if let available = record.availableDetailSlots, !available.isEmpty {
                    HStack(spacing: 4) {
                        Text("Available slots:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(available, id: \.self) { slot in
                            Text(slot)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.scene7Green.opacity(0.13))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.scene7CardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.gray.opacity(0.13), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 3, y: 1)
        .animation(.easeInOut(duration: 0.2), value: record.status)
    }

    func statusBadge(for status: Scene7ImageStatus) -> some View {
        switch status {
        case .notChecked:
            return Label("Not checked", systemImage: "questionmark.circle")
                .labelStyle(.iconOnly)
                .foregroundColor(.gray)
                .font(.system(size: 20))
        case .exists:
            return Label("Exists", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.iconOnly)
                .foregroundColor(.scene7Orange)
                .font(.system(size: 32, weight: .bold))
        case .unique:
            return Label("Unique", systemImage: "checkmark.seal.fill")
                .labelStyle(.iconOnly)
                .foregroundColor(.scene7Green)
                .font(.system(size: 32, weight: .bold))
        case .error:
            return Label("Error", systemImage: "xmark.octagon.fill")
                .labelStyle(.iconOnly)
                .foregroundColor(.scene7Secondary)
                .font(.system(size: 20))
        }
    }
}

struct Scene7CheckerUI_Previews: PreviewProvider {
    static var previews: some View {
        Scene7CheckerUI()
    }
}
