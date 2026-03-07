import Foundation
import Network

@MainActor
class BonjourBrowser: ObservableObject {
    @Published var discoveredHosts: [DiscoveredHost] = []
    @Published var isSearching = false

    private var browser: NWBrowser?
    private var resolutionTasks: [String: Task<Void, Never>] = [:]

    struct DiscoveredHost: Identifiable, Equatable {
        let id: String          // service name — stable across re-scans
        let name: String
        let host: String        // resolved IPv4
        let port: Int

        var displayName: String { name }
        var baseURL: String { "http://\(host):\(port)" }
    }

    func startBrowsing() {
        stopBrowsing()
        discoveredHosts = []
        isSearching = true

        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_maestro._tcp", domain: nil),
            using: params
        )

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .failed, .cancelled:
                    self?.isSearching = false
                default: break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for result in results {
                    if case .service(let name, _, _, _) = result.endpoint {
                        guard self.resolutionTasks[name] == nil else { continue }
                        self.resolutionTasks[name] = Task {
                            if let ip = await self.resolveIP(result) {
                                let host = DiscoveredHost(id: name, name: name, host: ip, port: 27182)
                                self.discoveredHosts.removeAll { $0.id == name }
                                self.discoveredHosts.append(host)
                            }
                            self.resolutionTasks[name] = nil
                        }
                    }
                }
            }
        }

        browser?.start(queue: .main)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        resolutionTasks.values.forEach { $0.cancel() }
        resolutionTasks = [:]
        isSearching = false
    }

    // MARK: - IP Resolution

    private func resolveIP(_ result: NWBrowser.Result) async -> String? {
        await withCheckedContinuation { continuation in
            let conn = NWConnection(to: result.endpoint, using: .tcp)
            var resolved = false

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !resolved else { return }
                    resolved = true
                    let ip: String?
                    if case .hostPort(let host, _) = conn.currentPath?.remoteEndpoint {
                        // Strip IPv6 zone ID or interface suffix
                        let raw = "\(host)"
                        ip = raw.components(separatedBy: "%").first
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                    } else {
                        ip = nil
                    }
                    conn.cancel()
                    continuation.resume(returning: ip)
                case .failed, .cancelled:
                    guard !resolved else { return }
                    resolved = true
                    conn.cancel()
                    continuation.resume(returning: nil)
                default: break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))

            // Timeout after 4 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                guard !resolved else { return }
                resolved = true
                conn.cancel()
                continuation.resume(returning: nil)
            }
        }
    }
}
