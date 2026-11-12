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

// MARK: - History file

let oldHistory = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":"2026-10-02T18:00:00Z","hand":"right","readings":[{"lovibond":166.4,"hyponychial":179.1,"depthRatio":0.84,"noCuticleDip":false}]}]"#

check("oldHistoryLoads") {
    let s = ScanHistory.decode(Data(oldHistory.utf8))
    return s.count == 1 && s[0].extraSigns == nil && s[0].report.results.map(\.sign) == [.clubbing]
        && s[0].readings.first?.lovibond == 166.4
}
check("unknownSignIsDropped") {
    // A result written by a newer build of the app.
    let newer = oldHistory.replacingOccurrences(
        of: #""hand":"right","#,
        with: #""hand":"right","extraSigns":[{"sign":"futureSign","state":"typical","analyzerVersion":1},{"sign":"refill","state":"typical","value":1.4,"valueText":"1.4 s","analyzerVersion":1}],"#)
    let s = ScanHistory.decode(Data(newer.utf8))
    return s.count == 1 && s[0].extraSigns?.map(\.sign) == [.refill]
}
check("unknownStateIsDropped") {
    let newer = oldHistory.replacingOccurrences(
        of: #""hand":"right","#,
        with: #""hand":"right","extraSigns":[{"sign":"refill","state":"futureState","analyzerVersion":1}],"#)
    let s = ScanHistory.decode(Data(newer.utf8))
    return s.count == 1 && s[0].extraSigns?.isEmpty == true
}
check("historyRoundTrip") {
    let refill = SignResult(sign: .refill, state: .typical, value: 1.4, valueText: "1.4 s", reason: nil, analyzerVersion: 1)
    let session = ScanSession(date: Date(timeIntervalSince1970: 1_790_000_000), hand: "left",
                              readings: [StoredReading(reading(166, 179, 0.84))], extraSigns: [refill])
    guard let data = ScanHistory.encode([session]) else { return false }
    return ScanHistory.decode(data) == [session]
}
check("damagedFileGivesNoSessions") {
    ScanHistory.decode(Data("{ not json".utf8)).isEmpty
}

check("damagedFileIsKeptAsideNotOverwritten") {
    // A history file the app can't read must survive the next save.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nv-history-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("History.json")
    try? Data("{ not json".utf8).write(to: url)
    let history = ScanHistory(url: url)
    history.add(readings: [reading(166, 179, 0.84)], hand: .right)
    let kept = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    let aside = kept.first { $0.hasPrefix("History-unreadable") }
    let asideText = aside.flatMap { try? String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8) }
    return history.sessions.count == 1 && asideText == "{ not json" && ScanHistory(url: url).sessions.count == 1
}
check("addKeepsExtraSigns") {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nv-history-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("History.json")
    let refill = SignResult(sign: .refill, state: .typical, value: 1.4, valueText: "1.4 s", reason: nil, analyzerVersion: 1)
    ScanHistory(url: url).add(readings: [reading(166, 179, 0.84)], hand: .left, extra: [refill])
    let reloaded = ScanHistory(url: url).sessions
    return reloaded.count == 1 && reloaded[0].extraSigns == [refill] && reloaded[0].hand == "left"
}

// MARK: - Accuracy lines (validation.json)

/// The app source folder, passed by test.sh.
let appFolder = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

check("validationParses") {
    guard let data = FileManager.default.contents(atPath: appFolder + "/Signs/validation.json") else { return false }
    let all = ValidationData.parse(data)
    guard let clubbing = all[.clubbing] else { return false }
    return clubbing.lines.count == 4 && clubbing.lines[0].label == "Healthy photos measured"
        && clubbing.lines[0].value == "81, none flagged" && clubbing.note?.isEmpty == false
}
check("validationOnlyCoversKnownSigns") {
    // An entry for a sign this build doesn't know is skipped, the rest stay.
    let json = #"[{"sign":"futureSign","updated":"2027-01-01","lines":[]},{"sign":"refill","updated":"2026-12-01","lines":[{"label":"Videos timed by hand","value":"40"}]}]"#
    let all = ValidationData.parse(Data(json.utf8))
    return all.count == 1 && all[.refill]?.lines.first?.value == "40"
}
check("brokenValidationFileGivesNothing") {
    ValidationData.parse(Data(#"{"broken""#.utf8)).isEmpty
}

// MARK: - Home wording

var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC")!
func day(_ text: String) -> Date { ISO8601DateFormatter().date(from: text + "T12:00:00Z")! }
let now = day("2026-11-12")

check("noCheckupsYet") {
    CheckupWording.lastCheckupLine(date: nil, overall: nil, now: now, calendar: utc) == "No check-ups yet"
}
check("lastCheckupToday") {
    CheckupWording.lastCheckupLine(date: day("2026-11-12"), overall: .typical, now: now, calendar: utc)
        == "Last check-up today · nothing stood out"
}
check("lastCheckupYesterday") {
    CheckupWording.lastCheckupLine(date: day("2026-11-11"), overall: .measureAgain, now: now, calendar: utc)
        == "Last check-up yesterday · measure again"
}
check("lastCheckupDaysAgo") {
    CheckupWording.lastCheckupLine(date: day("2026-11-09"), overall: .typical, now: now, calendar: utc)
        == "Last check-up 3 days ago · nothing stood out"
}
check("lastCheckupWeeksAgo") {
    CheckupWording.lastCheckupLine(date: day("2026-10-20"), overall: .worthDiscussing, now: now, calendar: utc)
        == "Last check-up 3 weeks ago · worth discussing with a doctor"
}
check("lastCheckupLongAgoShowsTheDate") {
    let line = CheckupWording.lastCheckupLine(date: day("2026-08-01"), overall: .couldntCheck, now: now, calendar: utc)
    return line.hasPrefix("Last check-up on ") && line.hasSuffix(" · couldn't check") && !line.contains("ago")
}
check("aClockSetBackNeverSaysNegativeDays") {
    // The last check-up is dated after "now" (the phone's clock was changed).
    CheckupWording.lastCheckupLine(date: day("2026-11-14"), overall: .typical, now: now, calendar: utc)
        == "Last check-up today · nothing stood out"
}
check("greetings") {
    CheckupWording.greeting(hour: 6) == "Good morning" && CheckupWording.greeting(hour: 12) == "Good afternoon"
        && CheckupWording.greeting(hour: 16) == "Good afternoon" && CheckupWording.greeting(hour: 17) == "Good evening"
        && CheckupWording.greeting(hour: 2) == "Good evening"
}

print(failures == 0 ? "signs-harness: all checks passed" : "signs-harness: \(failures) check(s) FAILED")
exit(failures == 0 ? 0 : 1)
