//
//  ValidationData.swift
//  NailVitals
//
//  The numbers behind "How accurate is this?" on each sign's page, read
//  from the bundled validation.json. Every value in that file comes from
//  our own measured data (photo-lab reports); nothing is typed in from
//  memory. Update the file when new study data is in.
//

import Foundation

nonisolated struct ValidationLine: Codable, Equatable {
    let label: String
    let value: String
}

nonisolated struct SignValidation: Codable, Equatable {
    let sign: NailSign
    /// When the numbers were last worked out, "2026-10-16".
    let updated: String
    let lines: [ValidationLine]
    /// What the numbers don't cover yet.
    let note: String?
}

nonisolated enum ValidationData {
    /// The entries in a validation file, by sign; none if it can't be
    /// read. Entries for signs this build doesn't know are skipped.
    static func parse(_ data: Data) -> [NailSign: SignValidation] {
        guard let entries = try? JSONDecoder().decode([Lenient<SignValidation>].self, from: data) else { return [:] }
        var bySign: [NailSign: SignValidation] = [:]
        for entry in entries.compactMap(\.value) { bySign[entry.sign] = entry }
        return bySign
    }

    /// The file shipped with the app.
    static let bundled: [NailSign: SignValidation] = {
        guard let url = Bundle.main.url(forResource: "validation", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return parse(data)
    }()
}
