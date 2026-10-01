//
//  StudyPanelView.swift
//  NailVitals
//
//  Testing builds only (saveCapturesForTesting): bookkeeping for the small
//  validation study. Who is being measured (a code like "P3", never a
//  name), an optional rough skin-tone group to check the app measures
//  everyone equally well, and the way into Label mode.
//

import SwiftUI

struct StudyPanelView: View {
    static let participantKey = "studyParticipant"
    static let participantNumberKey = "studyParticipantNumber"
    static let skinToneKey = "studySkinTone"

    @AppStorage(participantKey) private var participant = "P1"
    @AppStorage(participantNumberKey) private var number = 1
    @AppStorage(skinToneKey) private var skinTone = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Now measuring")
                        Spacer()
                        Text(participant)
                            .font(.system(size: 17, weight: .bold))
                            .monospacedDigit()
                    }
                    Button("Start a new person") {
                        number += 1
                        participant = "P\(number)"
                        skinTone = ""
                    }
                } header: {
                    Text("Participant")
                } footer: {
                    Text("Start a new person before measuring someone else, so each person's readings stay together. Codes only, no names.")
                }

                Section {
                    Picker("Skin tone group", selection: $skinTone) {
                        Text("Not recorded").tag("")
                        Text("Lighter").tag("lighter")
                        Text("Medium").tag("medium")
                        Text("Darker").tag("darker")
                    }
                } footer: {
                    Text("Optional and rough. Used only to check that the app measures everyone equally well.")
                }

                Section {
                    NavigationLink("Label saved photos") { LabelBrowserView() }
                } footer: {
                    Text("Place the measurement points by hand, without seeing the app's markers or numbers, so the app's accuracy can be checked against people.")
                }
            }
            .navigationTitle("Study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
