import Foundation

/// Exam-stage vocabulary scale. Raw values match `headwords.level` in the
/// bundled lexicon and are ordered from easiest to hardest.
enum Level: Int, CaseIterable, Comparable, Codable, Identifiable {
    case juniorHigh = 0
    case seniorHigh = 1
    case cet4 = 2
    case cet6 = 3
    case postgraduate = 4
    case toeflIelts = 5
    case gre = 6

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .juniorHigh: return "初中"
        case .seniorHigh: return "高中"
        case .cet4: return "四级"
        case .cet6: return "六级"
        case .postgraduate: return "考研"
        case .toeflIelts: return "托福雅思"
        case .gre: return "GRE"
        }
    }

    static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The user's declared vocabulary level. Words at or below it are considered
/// known and are not annotated; the choices offered stop at 托福雅思 because
/// "I know all GRE words" would leave nothing to annotate.
enum Proficiency {
    static let key = "proficiency"
    static let choices: [Level] = [.juniorHigh, .seniorHigh, .cet4, .cet6, .postgraduate, .toeflIelts]

    static var current: Level {
        get {
            let raw = UserDefaults.standard.object(forKey: key) as? Int ?? Level.cet4.rawValue
            return Level(rawValue: raw) ?? .cet4
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}
