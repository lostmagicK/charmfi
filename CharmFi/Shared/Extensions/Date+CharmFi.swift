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

    var apiDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }
}
