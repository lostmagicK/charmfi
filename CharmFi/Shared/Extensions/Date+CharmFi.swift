import Foundation

extension Date {
    static var startOfThisMonth: Date {
        Calendar.current.dateInterval(of: .month, for: Date())!.start
    }

    static var startOfLastMonth: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: .startOfThisMonth)!
    }

    static var startOfThisYear: Date {
        Calendar.current.dateInterval(of: .year, for: Date())!.start
    }

    /// Exclusive upper bound for "this month" filters — without it, presets built as `(start, nil)`
    /// leave the range open-ended and future-dated expenses leak into "This Month" totals.
    static var startOfNextMonth: Date {
        Calendar.current.date(byAdding: .month, value: 1, to: .startOfThisMonth)!
    }

    static var startOfNextYear: Date {
        Calendar.current.date(byAdding: .year, value: 1, to: .startOfThisYear)!
    }

    var monthYearString: String {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f.string(from: self)
    }

    var shortDateString: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: self)
    }

    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }

    /// Machine-readable `yyyy-MM-dd` in the device's local zone.
    ///
    /// Locale and calendar are pinned rather than left to the device: a fixed `dateFormat` renders
    /// in whatever calendar the region is set to, so on a Buddhist or ROC calendar this returns
    /// "2569-08-03" for today. This string is consumed as data — it goes into the AI system prompt
    /// and the grounding context — so an unpinned formatter tells the model the wrong year.
    var apiDateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }
}
