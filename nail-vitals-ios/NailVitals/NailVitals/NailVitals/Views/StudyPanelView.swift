//
//  StudyPanelView.swift
//  NailVitals
//
//  Testing builds only (saveCapturesForTesting): bookkeeping for the small
//  validation study. A list of people (codes like "P3", never names), each
//  with an optional rough skin-tone group; whoever is selected is tagged
//  on every capture automatically. Also the way into Label mode, and a way
//  to clear this phone's saved captures once they're copied off.
//

import SwiftUI

/// One study participant: a code and an optional rough skin-tone group.
struct StudyParticipant: Codable, Identifiable, Equatable {
    var code: String
    var skinTone: String  // "", "lighter", "medium", "darker"
    var id: String { code }
}

/// The participant list, kept in UserDefaults as JSON.
enum StudyRoster {
    static let currentKey = "studyCurrentParticipant"
    static let listKey = "studyParticipants"

    static let skinTones: [(tag: String, name: String)] = [("", "Not recorded"), ("lighter", "Lighter"), ("medium", "Medium"), ("darker", "Darker")]

    static func decode(_ json: String) -> [StudyParticipant] {
        guard let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([StudyParticipant].self, from: data), !list.isEmpty
        else { return [StudyParticipant(code: "P1", skinTone: "")] }
        return list
    }

    static func encode(_ list: [StudyParticipant]) -> String {
        (try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// The next free code: one more than the highest number used.
    static func nextCode(after list: [StudyParticipant]) -> String {
        let highest = list.compactMap { Int($0.code.dropFirst()) }.max() ?? 0
        return "P\(highest + 1)"
    }
}

struct StudyPanelView: View {
    @AppStorage(StudyRoster.currentKey) private var current = "P1"
    @AppStorage(StudyRoster.listKey) private var listJSON = ""
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDeletePhotos = false
    @State private var confirmReset = false
    @State private var savedCount = 0
    @State private var shareFile: ShareFile?
    @State private var packing = false
    @State private var shareError: String?

    private var people: [StudyParticipant] { StudyRoster.decode(listJSON) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(people) { person in
                        row(person)
                    }
                    .onDelete(perform: remove)
                    Button {
                        var list = people
                        let code = StudyRoster.nextCode(after: list)
                        list.append(StudyParticipant(code: code, skinTone: ""))
                        listJSON = StudyRoster.encode(list)
                        current = code
                    } label: {
                        Label("Add a person", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Who's being measured")
                } footer: {
                    Text("Tap a person to select them (the panel closes); every scan is tagged with the selected person and their skin-tone group. Codes only, no names. Skin tone is optional and only used to check the app measures everyone equally well. Swipe left to remove a person from this list (their saved scans stay).")
                }

                Section {
                    Button {
                        packing = true
                        shareError = nil
                        Task {
                            let url = await HumanLabelStore.zipAllCaptures()
                            packing = false
                            if let url { shareFile = ShareFile(url: url) } else { shareError = "Couldn't pack the photos. Try again." }
                        }
                    } label: {
                        HStack {
                            Text("Share saved photos (\(savedCount))")
                            if packing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(savedCount == 0 || packing)
                    if let shareError {
                        Text(shareError).foregroundColor(Theme.attention)
                    }
                } footer: {
                    Text("Packs every scan and label on this phone into one zip and opens the share sheet. AirDrop it to Rohan's Mac, or send a private iCloud or Drive link. Never post it publicly: these are photos of people's hands.")
                }

                Section {
                    NavigationLink("Label saved photos") { LabelBrowserView() }
                } footer: {
                    Text("Place the measurement points by hand, without seeing the app's markers or numbers, so the app's accuracy can be checked against people.")
                }

                Section {
                    Button("Delete saved photos on this phone (\(savedCount))", role: .destructive) {
                        confirmDeletePhotos = true
                    }
                    .disabled(savedCount == 0)
                    Button("Reset people list to P1", role: .destructive) {
                        confirmReset = true
                    }
                } footer: {
                    Text("Copy the photos to the Mac first (plug in and run the pull script); deleting can't be undone.")
                }
            }
            .navigationTitle("Study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                // Keep the selection on someone who exists.
                if !people.contains(where: { $0.code == current }) { current = people[0].code }
                if listJSON.isEmpty { listJSON = StudyRoster.encode(people) }
                savedCount = HumanLabelStore.captureFolders().count
            }
            .sheet(item: $shareFile) { file in
                ActivityView(items: [file.url])
            }
            .confirmationDialog("Delete \(savedCount) saved photos and their labels from this phone?",
                                isPresented: $confirmDeletePhotos, titleVisibility: .visible) {
                Button("Delete \(savedCount) photos", role: .destructive) {
                    HumanLabelStore.deleteAllCaptures()
                    savedCount = HumanLabelStore.captureFolders().count
                }
            } message: {
                Text("This can't be undone. Make sure they've been copied to the Mac.")
            }
            .confirmationDialog("Start the people list again from P1?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset to P1", role: .destructive) {
                    listJSON = StudyRoster.encode([StudyParticipant(code: "P1", skinTone: "")])
                    current = "P1"
                }
            } message: {
                Text("Saved scans keep the codes they were tagged with.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ person: StudyParticipant) -> some View {
        HStack {
            Button {
                // Selecting someone is the common case at a measuring
                // session, so it also closes the panel.
                current = person.code
                dismiss()
            } label: {
                HStack {
                    Image(systemName: person.code == current ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(person.code == current ? Theme.aligned : .secondary)
                    Text(person.code)
                        .font(.system(size: 17, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Picker("Skin tone", selection: Binding(
                get: { person.skinTone },
                set: { tone in
                    var list = people
                    if let i = list.firstIndex(where: { $0.code == person.code }) { list[i].skinTone = tone }
                    listJSON = StudyRoster.encode(list)
                }
            )) {
                ForEach(StudyRoster.skinTones, id: \.tag) { Text($0.name).tag($0.tag) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func remove(at offsets: IndexSet) {
        var list = people
        list.remove(atOffsets: offsets)
        if list.isEmpty { list = [StudyParticipant(code: "P1", skinTone: "")] }
        listJSON = StudyRoster.encode(list)
        if !list.contains(where: { $0.code == current }) { current = list[0].code }
    }
}

/// A file to hand to the share sheet.
struct ShareFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet (AirDrop, Messages, Files, ...).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
