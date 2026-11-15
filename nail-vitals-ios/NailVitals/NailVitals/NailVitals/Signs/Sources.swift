//
//  Sources.swift
//  NailVitals
//
//  The studies behind the app's limits and healthy averages, each with a
//  link, so every clinical number on screen is one tap from its source.
//  Checked against the papers' abstracts or full text (Oct 2026); see the
//  project notes for what each one does and doesn't say.
//

import Foundation

nonisolated struct Source: Equatable {
    /// Short name for a label: "JAMA 2001".
    let short: String
    /// Full citation.
    let citation: String
    /// What the app takes from it.
    let finding: String
    let url: String

    static let myersFarquhar2001 = Source(
        short: "JAMA 2001",
        citation: "Myers KA, Farquhar DR. Does this patient have clubbing? JAMA. 2001;286(3):341-7.",
        finding: "In people without clubbing, the profile angle, hyponychial angle and depth ratio do not exceed 176°, 192° and 1.0.",
        url: "https://pubmed.ncbi.nlm.nih.gov/11466101/")

    static let bentley1976 = Source(
        short: "Bentley 1976",
        citation: "Bentley D, Moore A, Shwachman H. Finger clubbing: a quantitative survey by analysis of the shadowgraph. Lancet. 1976;2(7978):164-7.",
        finding: "Measured on silhouettes of the right index finger, the normal profile angle averaged 168.3° (SD 3.6).",
        url: "https://pubmed.ncbi.nlm.nih.gov/73793/")

    static let husarik2002 = Source(
        short: "Husarik 2002",
        citation: "Husarik D, Vavricka SR, Mark M, Schaffner A, Walter RB. Assessment of digital clubbing in medical inpatients by digital photography and computerized analysis. Swiss Med Wkly. 2002;132:132-8.",
        finding: "On side photos, the hyponychial angle of 123 healthy people averaged 178.9° (SD 4.7).",
        url: "https://smw.ch/index.php/smw/article/download/154/151")

    static let regan1967 = Source(
        short: "Regan 1967",
        citation: "Regan GM, Tagg B, Thomson ML. Subjective assessment and objective measurement of finger clubbing. Lancet. 1967;1(7489):530-2.",
        finding: "Introduced the hyponychial angle as an objective measure.",
        url: "https://pubmed.ncbi.nlm.nih.gov/4163900/")

    static let all = [myersFarquhar2001, bentley1976, husarik2002, regan1967]
}

extension SignKind {
    /// Where this sign's limit comes from.
    var limitSource: Source { .myersFarquhar2001 }

    /// "limit 176° · JAMA 2001"
    var limitLabel: String { "limit \(formattedThreshold) · \(limitSource.short)" }

    /// The value with how far a scan usually moves from day to day
    /// (Repeatability, our own repeat sessions): "172.2° ± 3°". A reading
    /// from a phone photo isn't exact to a tenth of a degree, and the
    /// screen shouldn't suggest it is.
    func withUncertainty(_ value: Double) -> String {
        guard let range = Repeatability.range95[self] else { return formatted(value) }
        let plusMinus = self == .depthRatio ? String(format: "%.2f", range) : String(format: "%.0f°", range)
        return "\(formatted(value)) ± \(plusMinus)"
    }
}
