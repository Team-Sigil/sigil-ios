import Foundation

/// The gateway's live events (`GET /events`), one stream per family.
///
/// Each event carries ids only — `{"request_id": …}` — so the app refetches through the
/// ordinary endpoints rather than trusting anything in the stream. The token goes in the
/// `Authorization` header, never the URL.
@MainActor
final class EventStream {
    private var streams: [String: Task<Void, Never>] = [:]

    /// Opens a stream per family, replacing any already running. A guardian with several
    /// dependents gets several streams, since the gateway scopes events by family.
    func listen(families: [String], api: (String) -> SigilAPI, onEvent: @escaping () -> Void) {
        for familyID in families where streams[familyID] == nil {
            let request = api(familyID).eventStream()
            streams[familyID] = Task { await Self.run(request, onEvent: onEvent) }
        }
        for (familyID, task) in streams where !families.contains(familyID) {
            task.cancel()
            streams[familyID] = nil
        }
    }

    func stop() {
        for task in streams.values { task.cancel() }
        streams = [:]
    }

    /// Reads events until cancelled, reconnecting after a drop. The gateway sends a
    /// heartbeat every 15 s, and the connection can still be cut by anything in between.
    private static func run(_ request: URLRequest, onEvent: @escaping () -> Void) async {
        var backoff: UInt64 = 1
        while !Task.isCancelled {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                backoff = 1
                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    // Only the data lines matter; the ids in them are refetched anyway.
                    guard line.hasPrefix("data:") else { continue }
                    await MainActor.run { onEvent() }
                }
            } catch {
                if Task.isCancelled { return }
            }
            try? await Task.sleep(for: .seconds(min(backoff, 30)))
            backoff *= 2
        }
    }
}
