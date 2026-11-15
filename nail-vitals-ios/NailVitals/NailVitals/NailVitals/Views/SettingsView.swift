//
//  SettingsView.swift
//  NailVitals
//
//  Everything that isn't the assessment itself, in one place behind the
//  gear on Home: the look, which finger, the reminder, what the app keeps
//  and how to delete it, and the testing tools. Keeping these off Home is
//  what lets Home stay one status line and one button.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var history: ScanHistory
    /// Scans a printed model finger on a stand (no hand to detect).
    var onStartModelScan: () -> Void = {}

    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .automatic
    @AppStorage("measuredHand") private var hand: MeasuredHand = .right
    @AppStorage("voiceGuidance") private var voiceOn = true
    @ObservedObject private var reminder = CheckupReminder.shared
    @State private var confirmDelete = false
    @State private var showStudy = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Assessment") {
                    Picker("Finger", selection: $hand) {
                        ForEach(MeasuredHand.allCases, id: \.self) { Text("\($0.label) index finger").tag($0) }
                    }
                    Toggle("Voice guidance", isOn: $voiceOn)
                }

                Section("Look") {
                    Picker("Look", selection: $appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if let date = reminder.scheduledDate {
                        LabeledContent("Next reminder", value: date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        Button("Cancel reminder") { reminder.cancel() }
                            .foregroundStyle(Theme.accent)
                    } else {
                        Text("No reminder set. You can set one from your latest result.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                } header: {
                    Text("Reminder")
                }

                Section {
                    Label("Your photos are measured on this phone and aren't kept.", systemImage: "iphone")
                    Label("Only the measured numbers are saved, on this phone.", systemImage: "number")
                    Label("Ask sends your numbers and your question to an AI service, never a photo.", systemImage: "bubble.left.and.text.bubble.right")
                    LabeledContent("Saved assessments", value: "\(history.sessions.count)")
                    Button("Delete all results on this phone", role: .destructive) { confirmDelete = true }
                        .foregroundStyle(Theme.destructive)
                        .disabled(history.sessions.isEmpty)
                } header: {
                    Text("Privacy and data")
                }

                Section {
                    Button {
                        dismiss()
                        onStartModelScan()
                    } label: {
                        Label("Scan a model finger", systemImage: "cube.transparent")
                    }
                    .foregroundStyle(Theme.accent)
                    if saveCapturesForTesting {
                        Button { showStudy = true } label: {
                            Label("Study", systemImage: "person.2.fill")
                        }
                        .foregroundStyle(Theme.accent)
                    }
                } header: {
                    Text("Research tools")
                } footer: {
                    Text("For testing the app's accuracy. A model finger's result isn't saved.")
                }

                Section {
                    SafetyNote()
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showStudy) { StudyPanelView() }
            .confirmationDialog("Delete all saved results from this phone?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all results", role: .destructive) { history.deleteAll() }
            } message: {
                Text("This can't be undone.")
            }
        }
        .tint(Theme.accent)
    }
}
