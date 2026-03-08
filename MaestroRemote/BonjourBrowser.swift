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
        var baseURL: String {
            // IPv6 addresses need brackets in URLs
            if host.contains(":") { return "http://[\(host)]:\(port)" }
            return "http://\(host):\(port)"
        }
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
            // Force IPv4 — Mac server listens on 0.0.0.0 (IPv4 only)
            let params = NWParameters.tcp
            if let ipOpts = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ipOpts.version = .v4
            }
            let conn = NWConnection(to: result.endpoint, using: params)
            let box = ResolveBox()

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard box.resolve() else { return }
                    let ip: String?
                    if case .hostPort(let host, _) = conn.currentPath?.remoteEndpoint {
                        let raw = "\(host)"
                        ip = raw.components(separatedBy: "%").first
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                    } else {
                        ip = nil
                    }
                    conn.cancel()
                    continuation.resume(returning: ip)
                case .failed, .cancelled:
                    guard box.resolve() else { return }
                    conn.cancel()
                    continuation.resume(returning: nil)
                default: break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                guard box.resolve() else { return }
                conn.cancel()
                continuation.resume(returning: nil)
            }
        }
    }
}

// Thread-safe one-shot flag for async resolve
private final class ResolveBox: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func resolve() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true; return true
    }
}
