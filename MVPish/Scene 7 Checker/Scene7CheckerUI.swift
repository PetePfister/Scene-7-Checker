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
    @State private var showRenameConfirmation = false
    @State private var showOnlyExists = false

    let columns = [
        GridItem(.adaptive(minimum: 320), spacing: 14)
    ]

    var body: some View {
        ZStack {
            Color.scene7Background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("Scene7 Bulk Checker")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.scene7Primary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 24)
                .padding(.bottom, 10)

                // Top action buttons
                HStack(spacing: 14) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import Images", systemImage: "tray.and.arrow.down.fill")
                            .font(.body)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    }
                    Button {
                        viewModel.checkAllImages()
                    } label: {
                        Label("Check Scene7", systemImage: "magnifyingglass")
                            .font(.body)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .disabled(viewModel.records.isEmpty || viewModel.isLoading)
                    if viewModel.canExport {
                        Button {
                            showRenameConfirmation = true
                        } label: {
                            Label("Rename Files on Disk", systemImage: "arrow.triangle.2.circlepath")
                                .font(.body)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .alert(isPresented: $showRenameConfirmation) {
                            Alert(
                                title: Text("Rename Files on Disk?"),
                                message: Text("This will rename your original files on disk. Are you sure you want to proceed?"),
                                primaryButton: .destructive(Text("Rename")) {
                                    viewModel.renameOnDisk()
                                },
                                secondaryButton: .cancel()
                            )
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                // Drag & Drop hint
                Text("Drag and drop images or folders below.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.bottom, 4)

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

                // Filter Toggle
                HStack {
                    Toggle("Show only images already on Scene7", isOn: $showOnlyExists)
                        .toggleStyle(SwitchToggleStyle())
                        .disabled(!anyChecked)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 4)

                // Main grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(recordBindings) { $record in
                            RecordCard(
                                record: $record,
                                focusedRenameID: $focusedRenameID,
                                viewModel: viewModel
                            )
                            .animation(.easeInOut(duration: 0.2), value: record.status)
                        }
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 6)
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(dropIsTargeted ? Color.accentColor : Color.gray.opacity(0.1), lineWidth: dropIsTargeted ? 2 : 1)
                        .background(Color.scene7CardBg)
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
    }

    // Indicates if any record has been checked
    var anyChecked: Bool {
        viewModel.records.contains { $0.status != .notChecked }
    }

    // Record bindings with improved filtering:
    // - When the toggle is on, show .exists images
    // - Always also show any record being edited (rename field focused) or with an error
    var recordBindings: [Binding<Scene7ImageRecord>] {
        let checked = anyChecked
        let editingIDs: Set<UUID> = Set([
            focusedRenameID
        ].compactMap { $0 })
        let source: [Scene7ImageRecord]
        if showOnlyExists && checked {
            // Show .exists, but also any record with .renameError or that is currently being edited
            source = viewModel.records.filter {
                $0.status == .exists
                || editingIDs.contains($0.id)
                || $0.renameError != nil
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

// MARK: - Record Card (Image Record Display)
struct RecordCard: View {
    @Binding var record: Scene7ImageRecord
    @FocusState.Binding var focusedRenameID: UUID?
    var viewModel: Scene7CheckerLogic

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.10))
                        .frame(width: 44, height: 44)
                    if let thumbnail = record.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundColor(.scene7Primary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.filename)
                        .font(.body)
                        .foregroundColor(.scene7Primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let url = record.scene7URL {
                        Text(url.absoluteString)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                statusIcon(for: record.status)
                    .font(.system(size: 20))
                    .padding(.trailing, 2)
            }
            // Always show rename for all
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
            }
            if let error = record.renameError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, -2)
                    .transition(.opacity)
            }
            // USED/AVAILABLE SLOTS UI
            if record.detailSlotChecked {
                VStack(alignment: .leading, spacing: 2) {
                    if let used = record.usedDetailSlots, !used.isEmpty {
                        Text("Used slots: \(used.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundColor(.scene7Orange)
                    } else {
                        Text("No slots currently used.")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    if let available = record.availableDetailSlots, !available.isEmpty {
                        Text("Available slots: \(available.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundColor(.scene7Green)
                    } else {
                        Text("No slots available.")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top, 2)
            }
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

    func statusIcon(for status: Scene7ImageStatus) -> some View {
        switch status {
        case .notChecked:
            return Image(systemName: "questionmark.circle").foregroundColor(.gray)
        case .exists:
            return Image(systemName: "exclamationmark.triangle").foregroundColor(.scene7Orange)
        case .unique:
            return Image(systemName: "checkmark.seal").foregroundColor(.scene7Green)
        case .error:
            return Image(systemName: "xmark.octagon").foregroundColor(.scene7Secondary)
        }
    }
}

struct Scene7CheckerUI_Previews: PreviewProvider {
    static var previews: some View {
        Scene7CheckerUI()
    }
}
