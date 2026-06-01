import Foundation

struct WindowQuota: Codable {
    let label: String
    let usedPercent: Double
    let remainingPercent: Double
    let resetsAt: Date?
}

struct QuotaSnapshot: Codable {
    let sourceFileName: String
    let eventTimestamp: Date?
    let detectedAt: Date
    let planType: String?
    let primary: WindowQuota
    let secondary: WindowQuota?
}

enum CodexActivityStatus: String, Codable {
    case answering
    case waitingForUser
    case finished
    case unknown

    var chineseTitle: String {
        switch self {
        case .answering:
            return "执行中"
        case .waitingForUser:
            return "思考中/等待授权"
        case .finished:
            return "已完成"
        case .unknown:
            return "未知"
        }
    }

    func title(language: WidgetLanguage) -> String {
        switch language {
        case .english:
            switch self {
            case .answering:
                return "Working"
            case .waitingForUser:
                return "Waiting"
            case .finished:
                return "Done"
            case .unknown:
                return "Unknown"
            }
        case .chinese:
            return chineseTitle
        }
    }
}

struct CodexActivitySnapshot: Codable {
    static let idleCollapseInterval: TimeInterval = 15
    static let idleBreathingDuration: TimeInterval = 5

    let status: CodexActivityStatus
    let eventTimestamp: Date?
    let needsHumanAttention: Bool

    static var idle: CodexActivitySnapshot {
        CodexActivitySnapshot(status: .finished, eventTimestamp: nil, needsHumanAttention: false)
    }

    var shouldCollapseToGreenOnly: Bool {
        guard status == .finished else {
            return false
        }
        guard let eventTimestamp else {
            return true
        }
        return Date().timeIntervalSince(eventTimestamp) >= Self.idleCollapseInterval + Self.idleBreathingDuration
    }

    var shouldBreatheBeforeCollapse: Bool {
        guard status == .finished, let eventTimestamp else {
            return false
        }

        let elapsed = Date().timeIntervalSince(eventTimestamp)
        return elapsed >= Self.idleCollapseInterval
            && elapsed < Self.idleCollapseInterval + Self.idleBreathingDuration
    }
}

struct WidgetState: Codable {
    var originX: Double?
    var originY: Double?
    var language: WidgetLanguage?
}

enum WidgetLanguage: String, Codable {
    case english
    case chinese

    var toggled: WidgetLanguage {
        switch self {
        case .english:
            return .chinese
        case .chinese:
            return .english
        }
    }

    var menuTitle: String {
        switch self {
        case .english:
            return "Language: English"
        case .chinese:
            return "Language: 中文"
        }
    }
}

enum RefreshCadence {
    case hidden
    case fast
    case normal

    var interval: TimeInterval {
        switch self {
        case .hidden:
            return 5
        case .fast:
            return 1
        case .normal:
            return 2
        }
    }
}
