//
//  LabelBrowserView.swift
//  NailVitals
//
//  Label mode's list of saved captures (testing builds). Shows only the
//  photos -- never the app's markers or results -- and which ones this
//  labeler has done. Each labeler's points go in their own file
//  (label-<initials>.json), so a second person can label the same photos
//  for a person-vs-person comparison.
//

import SwiftUI
import ImageIO

struct LabelBrowserView: View {
    @AppStorage("labelerInitials") private var initials = ""
    @State private var folders: [URL] = []
    @State private var labeled: Set<String> = []

    private var labeler: String { HumanLabelStore.sanitized(initials) }

    var body: some View {
        List {
            Section {
                TextField("Your initials", text: $initials)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } footer: {
                Text(labeler.isEmpty
                     ? "Enter your initials to start. Each person's labels are kept separately."
                     : "\(labeled.count) of \(folders.count) photos labeled by \(labeler).")
            }

            Section("Saved photos") {
                if folders.isEmpty {
                    Text("No saved captures yet.")
                        .foregroundColor(.secondary)
                }
                ForEach(folders, id: \.self) { folder in
                    NavigationLink {
                        LabelingView(folder: folder, labeler: labeler)
                    } label: {
                        HStack(spacing: 12) {
                            CaptureThumbnail(url: folder.appendingPathComponent("photo.jpg"))
                                .frame(width: 44, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(folder.lastPathComponent)
                                .font(.system(size: 15, weight: .medium))
                                .monospacedDigit()
                            Spacer()
                            if labeled.contains(folder.lastPathComponent) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Theme.aligned)
                            }
                        }
                    }
                    .disabled(labeler.isEmpty)
                }
            }
        }
        .navigationTitle("Label photos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onChange(of: initials) { _, _ in reload() }
    }

    private func reload() {
        folders = HumanLabelStore.captureFolders()
        labeled = Set(folders.filter { HumanLabelStore.load(in: $0, labeler: labeler) != nil }.map(\.lastPathComponent))
    }
}

/// Small thumbnail of a capture photo, decoded off the main thread.
private struct CaptureThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .task(id: url) {
            image = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceThumbnailMaxPixelSize: 160,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: cg)
            }.value
        }
    }
}

/// Reading and writing labels in capture folders.
enum HumanLabelStore {
    static var capturesRoot: URL? {
        try? FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("Captures", isDirectory: true)
    }

    static func captureFolders() -> [URL] {
        guard let root = capturesRoot,
              let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return items
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("photo.jpg").path) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Zips the whole Captures folder (photos, results, labels) into a
    /// temporary file for the share sheet. The system's file coordinator
    /// makes the zip ("for uploading"); it only lives inside the block, so
    /// it is copied out.
    static func zipAllCaptures() async -> URL? {
        guard let root = capturesRoot else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> URL? in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmm"
            let device = UIDevice.current.name.filter { $0.isLetter || $0.isNumber }
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("NailVitals-\(device)-\(formatter.string(from: Date())).zip")
            var result: URL?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: root, options: [.forUploading], error: &coordinationError) { zipped in
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.copyItem(at: zipped, to: dest)) != nil { result = dest }
            }
            return result
        }.value
    }

    /// Removes every saved capture (photos, results, labels) from this
    /// phone. The Study panel asks first.
    static func deleteAllCaptures() {
        guard let root = capturesRoot,
              let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for item in items { try? FileManager.default.removeItem(at: item) }
    }

    /// Letters and digits only, upper case, for the file name.
    static func sanitized(_ initials: String) -> String {
        String(initials.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
    }

    static func url(in folder: URL, labeler: String) -> URL {
        folder.appendingPathComponent("label-\(labeler).json")
    }

    static func load(in folder: URL, labeler: String) -> HumanLabel? {
        guard !labeler.isEmpty, let data = try? Data(contentsOf: url(in: folder, labeler: labeler)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HumanLabel.self, from: data)
    }

    static func save(_ label: HumanLabel, in folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(label).write(to: url(in: folder, labeler: label.labeler))
    }
}
