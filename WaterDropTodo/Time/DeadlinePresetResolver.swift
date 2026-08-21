import Foundation

enum DeadlinePreset: Sendable, Equatable {
    case after30Minutes
    case after1Hour
    case after2Hours
    case tonightAt20
    case tomorrowAt9
    case custom(Date)
}

enum DeadlinePresetError: Error, Sendable, Equatable, LocalizedError {
    case tonightUnavailable
    case calendarCalculationFailed

    var errorDescription: String? {
        switch self {
        case .tonightUnavailable:
            "今天 20:00 已经过期，请选择其他时间。"
        case .calendarCalculationFailed:
            "无法根据当前日历计算截止时间。"
        }
    }
}

enum DeadlinePresetResolver {
    static func resolve(
        _ preset: DeadlinePreset,
        selectedAt date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Date {
        switch preset {
        case .after30Minutes:
            return date.addingTimeInterval(30 * 60)
        case .after1Hour:
            return date.addingTimeInterval(60 * 60)
        case .after2Hours:
            return date.addingTimeInterval(2 * 60 * 60)
        case .tonightAt20:
            guard let tonight = calendar.date(
                bySettingHour: 20,
                minute: 0,
                second: 0,
                of: date
            ) else {
                throw DeadlinePresetError.calendarCalculationFailed
            }
            guard date < tonight else { throw DeadlinePresetError.tonightUnavailable }
            return tonight
        case .tomorrowAt9:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date),
                  let deadline = calendar.date(
                    bySettingHour: 9,
                    minute: 0,
                    second: 0,
                    of: tomorrow
                  ) else {
                throw DeadlinePresetError.calendarCalculationFailed
            }
            return deadline
        case let .custom(customDate):
            let components = calendar.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
                from: customDate
            )
            guard let minutePrecision = calendar.date(from: components) else {
                throw DeadlinePresetError.calendarCalculationFailed
            }
            return minutePrecision
        }
    }
}
