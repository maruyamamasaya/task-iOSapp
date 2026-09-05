import Foundation

extension Calendar {
    func isJapaneseHoliday(_ date: Date) -> Bool {
        let day = startOfDay(for: date)
        let year = component(.year, from: day)
        return japaneseHolidays(for: year).contains(day)
    }

    private func japaneseHolidays(for year: Int) -> Set<Date> {
        guard year >= 1948 else { return [] }
        var national = Set<Date>()
        func add(_ month: Int, _ day: Int) {
            if let date = self.date(from: DateComponents(year: year, month: month, day: day)) { national.insert(startOfDay(for: date)) }
        }
        func addNthMonday(_ month: Int, _ ordinal: Int) {
            if let date = self.date(from: DateComponents(year: year, month: month, weekday: 2, weekdayOrdinal: ordinal)) { national.insert(startOfDay(for: date)) }
        }

        add(1, 1)
        if year >= 2000 { addNthMonday(1, 2) } else if year >= 1949 { add(1, 15) }
        if year >= 1967 { add(2, 11) }
        if year >= 2020 { add(2, 23) }
        add(3, Int(floor(20.8431 + 0.242194 * Double(year - 1980) - floor(Double(year - 1980) / 4))))
        add(4, 29)
        add(5, 3)
        if year >= 2007 { add(5, 4) }
        add(5, 5)
        if year == 2020 { add(7, 23) }
        else if year == 2021 { add(7, 22) }
        else if year >= 2003 { addNthMonday(7, 3) }
        else if year >= 1996 { add(7, 20) }
        if year == 2020 { add(7, 24) }
        else if year == 2021 { add(7, 23) }
        else if year >= 2016 { add(8, 11) }
        if year >= 2003 { addNthMonday(9, 3) } else if year >= 1966 { add(9, 15) }
        add(9, Int(floor(23.2488 + 0.242194 * Double(year - 1980) - floor(Double(year - 1980) / 4))))
        if year == 2020 { add(8, 10) }
        else if year == 2021 { add(8, 8) }
        else if year >= 2000 { addNthMonday(10, 2) }
        else if year >= 1966 { add(10, 10) }
        add(11, 3); add(11, 23)
        if (1989...2018).contains(year) { add(12, 23) }
        addImperialEvents(year: year, to: &national)

        if year >= 1986 {
            var cursor = self.date(from: DateComponents(year: year, month: 1, day: 2))!
            let end = self.date(from: DateComponents(year: year, month: 12, day: 30))!
            while cursor <= end {
                let previous = self.date(byAdding: .day, value: -1, to: cursor)!
                let next = self.date(byAdding: .day, value: 1, to: cursor)!
                if !national.contains(cursor), national.contains(previous), national.contains(next) { national.insert(cursor) }
                cursor = self.date(byAdding: .day, value: 1, to: cursor)!
            }
        }

        var holidays = national
        if year >= 1973 {
            for holiday in national where component(.weekday, from: holiday) == 1 {
                var substitute = self.date(byAdding: .day, value: 1, to: holiday)!
                if year >= 2007 { while holidays.contains(substitute) { substitute = self.date(byAdding: .day, value: 1, to: substitute)! } }
                if component(.year, from: substitute) == year { holidays.insert(substitute) }
            }
        }
        return holidays
    }

    private func addImperialEvents(year: Int, to holidays: inout Set<Date>) {
        let values: [(Int, Int)]
        switch year {
        case 1959: values = [(4, 10)]
        case 1989: values = [(2, 24)]
        case 1990: values = [(11, 12)]
        case 1993: values = [(6, 9)]
        case 2019: values = [(4, 30), (5, 1), (5, 2), (10, 22)]
        default: values = []
        }
        for (month, day) in values {
            if let date = self.date(from: DateComponents(year: year, month: month, day: day)) { holidays.insert(startOfDay(for: date)) }
        }
    }
    func replacingDate(of original: Date, with day: Date) -> Date {
        let time = dateComponents([.hour, .minute, .second, .nanosecond], from: original)
        return date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? startOfDay(for: day)
    }
    /// Month-only dates retained for callers that do not need a full grid.
    func monthDates(containing date: Date) -> [Date?] {
        guard let month = dateInterval(of: .month, for: date),
              let days = range(of: .day, in: .month, for: date) else { return [] }
        let weekdayOffset = component(.weekday, from: month.start) - firstWeekday
        let leading = (weekdayOffset + 7) % 7
        return Array(repeating: nil, count: leading) + days.compactMap {
            self.date(byAdding: .day, value: $0 - 1, to: month.start)
        }
    }

    /// Six complete Monday-first weeks. Adjacent-month dates are included so the
    /// grid remains stable and month boundaries are easy to understand.
    func monthGridDates(containing date: Date) -> [Date] {
        let configuredCalendar = self
        guard let month = configuredCalendar.dateInterval(of: .month, for: date) else { return [] }
        let weekdayOffset = configuredCalendar.component(.weekday, from: month.start) - configuredCalendar.firstWeekday
        let leading = (weekdayOffset + 7) % 7
        guard let gridStart = configuredCalendar.date(byAdding: .day, value: -leading, to: month.start) else { return [] }
        return (0..<42).compactMap {
            configuredCalendar.date(byAdding: .day, value: $0, to: gridStart)
        }
    }

    /// Seven calendar days in the Monday-first week containing `date`.
    func weekDates(containing date: Date) -> [Date] {
        let value = self
        let day = value.startOfDay(for: date)
        let offset = (value.component(.weekday, from: day) - value.firstWeekday + 7) % 7
        guard let monday = value.date(byAdding: .day, value: -offset, to: day) else { return [] }
        return (0..<7).compactMap { value.date(byAdding: .day, value: $0, to: monday) }
    }

    func mondayWeekDates(containing date: Date) -> [Date] {
        var value = self; value.firstWeekday = 2; return value.weekDates(containing: date)
    }

    func isDate(_ date: Date, inSameMonthAs other: Date) -> Bool {
        isDate(date, equalTo: other, toGranularity: .month)
    }

    func dayInterval(containing date: Date) -> DateInterval {
        let start = startOfDay(for: date)
        return DateInterval(start: start, end: self.date(byAdding: .day, value: 1, to: start) ?? start)
    }
}
