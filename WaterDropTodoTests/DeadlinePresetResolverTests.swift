import Foundation
import Testing
@testable import WaterDropTodo

struct DeadlinePresetResolverTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func relativePresetsAddExpectedIntervals() throws {
        let selected = date(2026, 8, 20, 12, 15)
        #expect(
            try DeadlinePresetResolver.resolve(.after30Minutes, selectedAt: selected, calendar: calendar)
                == selected.addingTimeInterval(1_800)
        )
        #expect(
            try DeadlinePresetResolver.resolve(.after1Hour, selectedAt: selected, calendar: calendar)
                == selected.addingTimeInterval(3_600)
        )
        #expect(
            try DeadlinePresetResolver.resolve(.after2Hours, selectedAt: selected, calendar: calendar)
                == selected.addingTimeInterval(7_200)
        )
    }

    @Test func tonightIsAvailableAt1959AndUnavailableAt2000() throws {
        let at1959 = date(2026, 8, 20, 19, 59)
        #expect(
            try DeadlinePresetResolver.resolve(.tonightAt20, selectedAt: at1959, calendar: calendar)
                == date(2026, 8, 20, 20, 0)
        )

        do {
            _ = try DeadlinePresetResolver.resolve(
                .tonightAt20,
                selectedAt: date(2026, 8, 20, 20, 0),
                calendar: calendar
            )
            Issue.record("20:00 后不应继续提供今晚选项")
        } catch {
            #expect(error as? DeadlinePresetError == .tonightUnavailable)
        }
    }

    @Test func tomorrowHandlesMonthEndAndYearEnd() throws {
        #expect(
            try DeadlinePresetResolver.resolve(
                .tomorrowAt9,
                selectedAt: date(2026, 8, 31, 23, 0),
                calendar: calendar
            ) == date(2026, 9, 1, 9, 0)
        )
        #expect(
            try DeadlinePresetResolver.resolve(
                .tomorrowAt9,
                selectedAt: date(2026, 12, 31, 23, 0),
                calendar: calendar
            ) == date(2027, 1, 1, 9, 0)
        )
    }

    @Test func customDeadlineDropsSeconds() throws {
        let custom = date(2026, 8, 20, 14, 33, 47)
        #expect(
            try DeadlinePresetResolver.resolve(.custom(custom), selectedAt: custom, calendar: calendar)
                == date(2026, 8, 20, 14, 33)
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        ))!
    }
}
