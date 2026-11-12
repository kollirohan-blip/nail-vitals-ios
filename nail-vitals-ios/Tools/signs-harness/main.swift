// Named checks for the sign model (Signs/) and the history file
// (Session/). Build and run with ../test.sh. Exit code 1 if any check fails.
import CoreGraphics
import Foundation

var failures = 0
func check(_ name: String, _ body: () -> Bool) {
    if body() { print("PASS  \(name)") } else { print("FAIL  \(name)"); failures += 1 }
}

func reading(_ lovibond: Double, _ hyponychial: Double, _ ratio: Double) -> FingerSigns {
    FingerSigns(lovibond: lovibond, hyponychial: hyponychial, depthRatio: ratio)
}

// MARK: - CheckupReport

check("typicalSession") {
    let r = CheckupReport(readings: [reading(166, 179, 0.84), reading(167, 178, 0.83), reading(166.5, 180, 0.85)])
    return r.results.count == 1 && r.results[0].sign == .clubbing && r.results[0].state == .typical
        && r.results[0].valueText == "166.5°" && r.overall == .typical && r.headline == "Nothing stood out today"
}
check("twoSignsAboveIsWorthDiscussing") {
    let r = CheckupReport(readings: [reading(185, 196, 0.9), reading(186, 197, 0.9), reading(184, 195, 0.9)])
    return r.results[0].state == .worthDiscussing && r.overall == .worthDiscussing
}
check("nothingMeasuredIsNotTypical") {
    let r = CheckupReport(readings: [FingerSigns()])
    return r.results[0].state == .couldntCheck && r.overall == .couldntCheck && r.measuredCount == 0
        && r.headline == "Couldn't check this time"
}
check("noDipShowsAtLeast180") {
    var a = reading(180, 196, 1.05)
    a.noCuticleDip = true
    return CheckupReport(readings: [a, a, a]).results[0].valueText == "≥180°"
}
check("couldntCheckNeverRaisesTheBanner") {
    let extra = [SignResult(sign: .refill, state: .couldntCheck, value: nil, valueText: nil, reason: "Hand moved", analyzerVersion: 1)]
    let r = CheckupReport(readings: [reading(166, 179, 0.84)], extra: extra, enabled: [.clubbing, .refill])
    return r.results.count == 2 && r.overall == .typical && r.measuredCount == 1
}
check("disabledSignsAreHidden") {
    let extra = [SignResult(sign: .pallor, state: .worthDiscussing, value: 1, valueText: "1", reason: nil, analyzerVersion: 1)]
    let r = CheckupReport(readings: [reading(166, 179, 0.84)], extra: extra)
    return r.results.map(\.sign) == [.clubbing] && r.overall == .typical
}
check("mostSeriousMeasuredStateWins") {
    let extra = [SignResult(sign: .refill, state: .measureAgain, value: 2.4, valueText: "2.4 s", reason: nil, analyzerVersion: 1)]
    return CheckupReport(readings: [reading(166, 179, 0.84)], extra: extra, enabled: [.clubbing, .refill]).overall == .measureAgain
}
check("groups") {
    NailSign.refill.group == .circulation && NailSign.tipBands.group == .colour && NailSign.spoonNails.group == .shape
        && NailSign.schamroth.group == .extra
}
check("resultsInAGroup") {
    let extra = [SignResult(sign: .refill, state: .typical, value: 1.4, valueText: "1.4 s", reason: nil, analyzerVersion: 1)]
    let r = CheckupReport(readings: [reading(166, 179, 0.84)], extra: extra, enabled: [.clubbing, .refill])
    return r.results(in: .shape).map(\.sign) == [.clubbing] && r.results(in: .circulation).map(\.sign) == [.refill]
        && r.results(in: .colour).isEmpty
}
check("everyStateHasItsOwnWordAndIcon") {
    let all: [SignState] = [.typical, .measureAgain, .worthDiscussing, .couldntCheck]
    return Set(all.map(\.label)).count == 4 && Set(all.map(\.symbol)).count == 4
        && SignState.couldntCheck.symbol == "minus.circle" && SignState.typical.symbol == "checkmark.circle"
}

print(failures == 0 ? "signs-harness: all checks passed" : "signs-harness: \(failures) check(s) FAILED")
exit(failures == 0 ? 0 : 1)
