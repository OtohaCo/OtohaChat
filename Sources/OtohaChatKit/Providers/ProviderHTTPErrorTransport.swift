import AgentModels
import AgentProviders
import Foundation

/// Reads the HTTP body of a failed provider request so the host can show the
/// vendor's sanitized `error.message` instead of only the status code.
struct ProviderHTTPErrorTransport: ProviderHTTPTransport {
    private let inner: any ProviderHTTPTransport

    init(wrapping inner: any ProviderHTTPTransport) {
        self.inner = inner
    }

    func stream(_ request: URLRequest) -> AsyncThrowingStream<ProviderHTTPEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var status: Int?
                var headers: [String: String] = [:]
                var buffer = Data()
                do {
                    for try await event in inner.stream(request) {
                        switch event {
                        case .response(let code, let responseHeaders):
                            status = code
                            headers = responseHeaders
                            if code == 200 {
                                continuation.yield(event)
                            }
                        case .data(let data):
                            if status == 200 {
                                continuation.yield(event)
                            } else {
                                buffer.append(data)
                            }
                        }
                    }
                    if let status, status != 200 {
                        continuation.finish(throwing: classify(status: status, headers: headers, body: buffer))
                        return
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func classify(status: Int, headers: [String: String], body: Data) -> ModelProviderError {
        let kind: ModelProviderError.Kind
        switch status {
        case 401: kind = .authentication
        case 403: kind = .permissionDenied
        case 408: kind = .transport
        case 429: kind = .rateLimited
        case 500...599: kind = .unavailable
        case 400...499: kind = .invalidRequest
        default: kind = .invalidResponse
        }
        let retry = headers.first { $0.key.lowercased() == "retry-after" }.flatMap { Int($0.value) }
        let message = providerMessage(from: body)
            ?? "Provider HTTP request failed (\(status))."
        return .init(
            kind: kind,
            message: SecretRedactor.redact(message),
            retryAfter: retry.flatMap { $0 >= 0 ? .seconds($0) : nil }
        )
    }

    private func providerMessage(from body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let message = json["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
