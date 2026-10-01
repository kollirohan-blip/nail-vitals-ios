//
//  ScanHistory.swift
//  NailVitals
//
//  Finished scan sessions kept on this phone so Home can show the last
//  result and a trend over time. Only the measured numbers are stored --
//  never photos -- in Documents/History.json.
//

import Foundation
import Combine

/// One reading's three signs, as stored.
nonisolated struct StoredReading: Codable, Equatable {
    var lovibond: Double?
    var hyponychial: Double?
    var depthRatio: Double?
    var noCuticleDip: Bool

    init(_ s: FingerSigns) {
        lovibond = s.lovibond
        hyponychial = s.hyponychial
        depthRatio = s.depthRatio
        noCuticleDip = s.noCuticleDip
    }

    var signs: FingerSigns {
        var s = FingerSigns(lovibond: lovibond, hyponychial: hyponychial, depthRatio: depthRatio)
        s.noCuticleDip = noCuticleDip
        return s
    }
}

nonisolated struct ScanSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var hand: String
    var readings: [StoredReading]

    var signs: [FingerSigns] { readings.map(\.signs) }
}

final class ScanHistory: ObservableObject {
    @Published private(set) var sessions: [ScanSession] = []

    private let url: URL? = try? FileManager.default
        .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        .appendingPathComponent("History.json")

    init() {
        guard let url, let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        sessions = (try? decoder.decode([ScanSession].self, from: data)) ?? []
    }

    var latest: ScanSession? { sessions.last }

    func session(_ id: UUID) -> ScanSession? {
        sessions.first { $0.id == id }
    }

    func add(readings: [FingerSigns], hand: MeasuredHand) {
        guard !readings.isEmpty else { return }
        sessions.append(ScanSession(date: Date(), hand: hand.rawValue, readings: readings.map(StoredReading.init)))
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
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(sessions).write(to: url, options: .atomic)
    }
}
