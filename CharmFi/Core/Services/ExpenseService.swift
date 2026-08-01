import Foundation

final class ExpenseService: @unchecked Sendable {
    private let api = APIClient.shared
    private let auth: AuthState

    init(auth: AuthState) { self.auth = auth }

    func getExpenses(filters: ExpenseFilters) async throws -> PagedResponse<Expense> {
        try await api.request(ExpenseEndpoint.list(filters), authState: auth)
    }

    func createExpense(_ req: CreateExpenseRequest) async throws -> Expense {
        // Server returns only {"id":"..."} on create — decode the ID then reconstruct
        let created: CreatedExpenseResponse = try await api.request(ExpenseEndpoint.create(req), authState: auth)
        return Expense(
            id: created.id,
            amount: req.amount,
            currency: req.currency,
            merchant: req.merchant,
            paymentMethod: req.paymentMethod,
            transactionDate: req.transactionDate,
            source: req.source,
            status: req.status,
            comment: req.comment,
            rawSmsText: req.rawSmsText,
            paymentAccountId: req.paymentAccountId,
            categoryId: req.categoryId
        )
    }

    func updateExpense(id: String, req: UpdateExpenseRequest) async throws -> Expense {
        try await api.request(ExpenseEndpoint.update(id: id, body: req), authState: auth)
    }

    func deleteExpense(id: String) async throws {
        try await api.requestVoid(ExpenseEndpoint.delete(id: id), authState: auth)
    }

    func submitExpense(id: String) async throws {
        try await api.requestVoid(ExpenseEndpoint.submit(id: id), authState: auth)
    }

    func batchSubmit(ids: [String]) async throws {
        try await api.requestVoid(ExpenseEndpoint.batchSubmit(ids: ids), authState: auth)
    }

    // Returns the ids of drafts that duplicate an already-Submitted expense.
    func checkDuplicates(_ drafts: [Expense]) async throws -> [String] {
        guard !drafts.isEmpty else { return [] }
        let candidates = drafts.map {
            DuplicateCandidateRequest(
                key: $0.id, transactionDate: $0.transactionDate,
                amount: $0.amount, paymentMethod: $0.paymentMethod)
        }
        let response: CheckDuplicatesResponse = try await api.request(
            ExpenseEndpoint.checkDuplicates(candidates), authState: auth)
        return response.duplicateKeys
    }

    func getDrafts() async throws -> PagedResponse<Expense> {
        var filters = ExpenseFilters()
        filters.status = .draft
        filters.pageSize = 100
        return try await getExpenses(filters: filters)
    }

    func exposeApplyRules() async throws {
        try await api.requestVoid(ExpenseEndpoint.applyMerchantRules, authState: auth)
    }

    func uploadPdf(fileURL: URL, password: String? = nil, bankHint: String? = nil) async throws -> PdfUploadResponse {
        let token = try await auth.validAccessToken()
        let boundary = "Boundary-\(UUID().uuidString)"
        let uploadURL = api.baseURL.appendingPathComponent("pdf/upload")
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let fileData = try Data(contentsOf: fileURL)
        body.appendMultipart(boundary: boundary, name: "file",
                             filename: fileURL.lastPathComponent, mimeType: "application/pdf", data: fileData)
        if let password, !password.isEmpty {
            body.appendMultipartField(boundary: boundary, name: "password", value: password)
        }
        if let bankHint, !bankHint.isEmpty {
            body.appendMultipartField(boundary: boundary, name: "bankHint", value: bankHint)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        APIClient.log(request, response: response, data: data)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let msg = (try? APIClient.decoder.decode(APIError.self, from: data))?.message ?? "PDF upload failed"
            throw NetworkError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0, msg)
        }
        return try APIClient.decoder.decode(PdfUploadResponse.self, from: data)
    }

    func createPaidFor(_ req: CreateExpenseRequest) async throws -> Expense {
        try await api.request(PaidForEndpoint.create(req), authState: auth)
    }

    func getPaidFor() async throws -> [PaidForExpense] {
        try await api.request(PaidForEndpoint.list, authState: auth)
    }

    /// Whole-set replace — always send the complete desired tag list, not a delta.
    func setTags(id: String, tagIds: [String]) async throws {
        try await api.requestVoid(ExpenseEndpoint.setTags(id: id, tagIds: tagIds), authState: auth)
    }
}
