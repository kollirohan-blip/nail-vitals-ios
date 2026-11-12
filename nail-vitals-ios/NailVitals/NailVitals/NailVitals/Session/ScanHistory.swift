//
//  ScanHistory.swift
//  NailVitals
//
//  Finished check-ups kept on this phone so Home can show the last result
//  and a trend over time. Only the measured numbers are stored -- never
//  photos -- in Documents/History.json.
//
//  The file must survive app updates in both directions: check-ups saved
//  before v2 have no `extraSigns`, and a file written by a newer build may
//  hold signs or states this build doesn't know (those entries are
//  skipped, the check-up stays). A file the app can't read at all is moved
//  aside, never overwritten.
//

import Foundation
import Combine

/// One reading's three signs, as stored.
nonisolated struct StoredReading: Codable, Equatable {
    var lovibond: Double?
    var hyponychial: Double?
    var depthRatio: Double?
    var noCuticleDip: Bool
    /// Added Oct 14; nil in results saved before.
    var quality: ReadingQuality?
    var identity: FingerPrint?

    init(_ s: FingerSigns) {
        lovibond = s.lovibond
        hyponychial = s.hyponychial
        depthRatio = s.depthRatio
        noCuticleDip = s.noCuticleDip
        quality = s.quality
        identity = s.identity
    }

    var signs: FingerSigns {
        var s = FingerSigns(lovibond: lovibond, hyponychial: hyponychial, depthRatio: depthRatio)
        s.noCuticleDip = noCuticleDip
        s.quality = quality
        s.identity = identity
        return s
    }
}

/// One finished check-up. (The v2 spec calls this a check-up session; the
/// type keeps its name so History.json stays compatible.)
nonisolated struct ScanSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var hand: String
    /// The side readings; the clubbing result is worked out from them.
    var readings: [StoredReading]
    /// Results for the other signs, as measured (they can't be worked out
    /// again without the photos). Nil in check-ups saved before v2.
    var extraSigns: [SignResult]?

    var signs: [FingerSigns] { readings.map(\.signs) }

    /// The check-up as the report card shows it.
    var report: CheckupReport { CheckupReport(readings: signs, extra: extraSigns ?? []) }
}

// nonisolated: decoded off the main actor (ScanHistory.decode).
nonisolated extension ScanSession {
    private enum CodingKeys: String, CodingKey {
        case id, date, hand, readings, extraSigns
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        hand = try c.decode(String.self, forKey: .hand)
        readings = try c.decode([StoredReading].self, forKey: .readings)
        extraSigns = try c.decodeIfPresent([Lenient<SignResult>].self, forKey: .extraSigns)?.compactMap(\.value)
    }
}

final class ScanHistory: ObservableObject {
    @Published private(set) var sessions: [ScanSession] = []

    private let url: URL?

    static var defaultURL: URL? {
        try? FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("History.json")
    }

    /// - Parameter url: where the history lives (tests pass a temporary file).
    init(url: URL? = ScanHistory.defaultURL) {
        self.url = url
        guard let url, let data = try? Data(contentsOf: url) else { return }
        if let decoded = Self.decodeOrNil(data) {
            sessions = decoded
        } else {
            // Unreadable: keep it beside the new file rather than lose it
            // to the next save.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = url.deletingLastPathComponent().appendingPathComponent("History-unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
        }
    }

    var latest: ScanSession? { sessions.last }

    func session(_ id: UUID) -> ScanSession? {
        sessions.first { $0.id == id }
    }

    /// - Parameter extra: results for the signs other than clubbing.
    func add(readings: [FingerSigns], hand: MeasuredHand, extra: [SignResult] = []) {
        guard !readings.isEmpty else { return }
        sessions.append(ScanSession(date: Date(), hand: hand.rawValue, readings: readings.map(StoredReading.init),
                                    extraSigns: extra.isEmpty ? nil : extra))
        save()
    }

    func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    func deleteAll() {
        sessions = []
        save()
    }

    private func save() {
        guard let url, let data = Self.encode(sessions) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - File format

    /// The sessions in a history file; none if it can't be read.
    nonisolated static func decode(_ data: Data) -> [ScanSession] {
        decodeOrNil(data) ?? []
    }

    nonisolated private static func decodeOrNil(_ data: Data) -> [ScanSession]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([ScanSession].self, from: data)
    }

    nonisolated static func encode(_ sessions: [ScanSession]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(sessions)
    }
}
