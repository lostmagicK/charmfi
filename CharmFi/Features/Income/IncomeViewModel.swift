import Foundation
import Observation

@Observable
@MainActor
final class IncomeViewModel {
    var period: DashboardPeriod = DashboardPeriod.current().withMode(.month)
    var sources: [IncomeSource] = []
    var month: IncomeMonth?
    var isLoading = false
    var error: String?

    private let service: IncomeService

    init(auth: AuthState) {
        service = IncomeService(auth: auth)
    }

    var activeSources: [IncomeSource] {
        sources.filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder }
    }

    func entries(for sourceId: String) -> [IncomeEntry] {
        (month?.entries ?? []).filter { $0.incomeSourceId == sourceId }
            .sorted { $0.receivedOn > $1.receivedOn }
    }

    func amount(for sourceId: String) -> Double {
        month?.bySource.first(where: { $0.sourceId == sourceId })?.amount ?? 0
    }

    func setPeriod(_ p: DashboardPeriod) {
        period = p
        Task { await load() }
    }

    func load() async {
        isLoading = true
        error = nil
        async let sourcesResult = service.getSources()
        async let monthResult = service.getMonth(year: period.year, month: period.month)
        do {
            let (s, m) = try await (sourcesResult, monthResult)
            sources = s
            month = m
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func createSource(_ req: IncomeSourceRequest) async {
        do {
            _ = try await service.createSource(req)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    func updateSource(id: String, req: IncomeSourceRequest) async {
        do {
            try await service.updateSource(id: id, req: req)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    func deleteSource(id: String) async {
        do {
            try await service.deleteSource(id: id)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    func createEntry(_ req: IncomeEntryRequest) async {
        do {
            _ = try await service.createEntry(req)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    func updateEntry(id: String, req: IncomeEntryUpdateRequest) async {
        do {
            try await service.updateEntry(id: id, req: req)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    func deleteEntry(id: String) async {
        do {
            try await service.deleteEntry(id: id)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    /// Backfilling a past month should default the new entry's date to the source's usual pay
    /// day, not "now" — mirrors Android's `defaultEntryDate`.
    func defaultEntryDate(for source: IncomeSource) -> Date {
        let cal = Calendar.current
        let now = Date()
        let isCurrentMonth = cal.component(.year, from: now) == period.year && cal.component(.month, from: now) == period.month
        if isCurrentMonth { return now }
        var comps = DateComponents(year: period.year, month: period.month, day: source.dayOfMonth ?? 1)
        let daysInMonth = cal.range(of: .day, in: .month, for: cal.date(from: DateComponents(year: period.year, month: period.month))!)?.count ?? 28
        comps.day = min(comps.day ?? 1, daysInMonth)
        return cal.date(from: comps) ?? now
    }
}
