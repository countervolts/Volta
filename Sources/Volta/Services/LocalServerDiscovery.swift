import Combine
import Darwin
import Foundation

struct DiscoveredMusicServer: Identifiable, Hashable, Sendable {
    let name: String
    let address: String
    let backend: MusicBackendKind

    var primaryDisplayName: String {
        hasDockerContainerHostname ? backend.displayName : name
    }

    var secondaryDisplayName: String {
        hasDockerContainerHostname ? name : backend.displayName
    }

    var id: String {
        "\(backend.rawValue)|\(address.lowercased())"
    }

    /// Docker's default hostname is the container ID, normally exposed as a
    /// 12-character hexadecimal value (or occasionally the full 64 characters).
    private var hasDockerContainerHostname: Bool {
        guard backend == .jellyfin || backend == .emby,
              name.count == 12 || name.count == 64 else { return false }
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return name.unicodeScalars.allSatisfy { hexadecimal.contains($0) }
    }
}

/// Discovers supported music servers that advertise themselves on the local network.
///
/// Jellyfin and Emby use their UDP/7359 discovery protocol, Plex uses GDM, and
/// Bonjour/SSDP cover servers that publish a standard web or product-specific service.
@MainActor
final class LocalServerDiscovery: NSObject, ObservableObject {
    @Published private(set) var servers: [DiscoveredMusicServer] = []
    @Published private(set) var isScanning = false

    private var browsers: [NetServiceBrowser] = []
    private var resolvingServices: [NetService] = []
    private var datagramSearches: [DatagramSearch] = []
    private var scanTask: Task<Void, Never>?
    private var subnetScanTask: Task<Void, Never>?

    private static let bonjourTypes = [
        "_navidrome._tcp.",
        "_subsonic._tcp.",
        "_airsonic._tcp.",
        "_jellyfin._tcp.",
        "_emby._tcp.",
        "_plexmediasvr._tcp.",
        "_http._tcp.",
        "_https._tcp.",
    ]

    func start() {
        stop(clearResults: true)
        isScanning = true

        for type in Self.bonjourTypes {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browsers.append(browser)
            browser.searchForServices(ofType: type, inDomain: "local.")
        }

        startDatagramSearches()
        subnetScanTask = Task { [weak self] in
            // Give Bonjour a moment to present/settle the local-network permission
            // prompt before direct HTTP probes begin.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.scanLocalSubnet()
        }
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.finishScan()
        }
    }

    func stop() {
        stop(clearResults: false)
    }

    private func stop(clearResults: Bool) {
        scanTask?.cancel()
        scanTask = nil
        subnetScanTask?.cancel()
        subnetScanTask = nil
        browsers.forEach { $0.stop() }
        browsers.removeAll()
        resolvingServices.forEach { $0.stop() }
        resolvingServices.removeAll()
        datagramSearches.forEach { $0.stop() }
        datagramSearches.removeAll()
        subnetScanTask?.cancel()
        subnetScanTask = nil
        isScanning = false
        if clearResults { servers.removeAll() }
    }

    private func finishScan() {
        browsers.forEach { $0.stop() }
        browsers.removeAll()
        resolvingServices.forEach { $0.stop() }
        resolvingServices.removeAll()
        datagramSearches.forEach { $0.stop() }
        datagramSearches.removeAll()
        scanTask = nil
        isScanning = false
    }

    private func startDatagramSearches() {
        addDatagramSearch(
            message: "Who is Jellyfin Server?",
            host: "255.255.255.255",
            port: 7359,
            handler: { [weak self] data, _ in self?.handleMediaBrowserResponse(data, backend: .jellyfin) }
        )
        addDatagramSearch(
            message: "who is EmbyServer?",
            host: "255.255.255.255",
            port: 7359,
            handler: { [weak self] data, _ in self?.handleMediaBrowserResponse(data, backend: .emby) }
        )
        addDatagramSearch(
            message: "M-SEARCH * HTTP/1.0\r\nHost: 239.0.0.250:32414\r\nMan: \"ssdp:discover\"\r\nST: plex/media-server\r\nMX: 3\r\n\r\n",
            host: "239.0.0.250",
            port: 32414,
            handler: { [weak self] data, host in self?.handlePlexResponse(data, host: host) }
        )
        addDatagramSearch(
            message: "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: ssdp:all\r\n\r\n",
            host: "239.255.255.250",
            port: 1900,
            handler: { [weak self] data, _ in self?.handleSSDPResponse(data) }
        )
    }

    // MARK: - Direct local-subnet discovery

    /// Some servers (notably Navidrome) do not advertise on the LAN, while
    /// container port forwarding often prevents UDP discovery from reaching
    /// Jellyfin/Emby/Plex. Probe a bounded set of their known HTTP ports on the
    /// current Wi-Fi subnet and identify the service from a public endpoint.
    private func scanLocalSubnet() async {
        guard let network = IPv4Network.current(), !Task.isCancelled else { return }
        let hosts = network.hostAddresses
        guard !hosts.isEmpty else { return }

        let ports: [ScanPort] = [
            ScanPort(port: 4533, family: .subsonic),
            ScanPort(port: 8096, family: .mediaBrowser),
            ScanPort(port: 8097, family: .mediaBrowser),
            ScanPort(port: 32400, family: .plex),
            ScanPort(port: 4040, family: .subsonic),
            ScanPort(port: 8098, family: .mediaBrowser),
            ScanPort(port: 8099, family: .mediaBrowser),
            ScanPort(port: 8920, family: .mediaBrowser),
            ScanPort(port: 8921, family: .mediaBrowser),
            ScanPort(port: 8922, family: .mediaBrowser),
        ]
        // Port-major ordering means every host is checked for the most likely
        // services first. A server at .254 is not delayed behind all ports on
        // the preceding 253 hosts.
        let targets = ports.flatMap { scanPort in
            hosts.map { ScanTarget(host: $0, port: scanPort.port, family: scanPort.family) }
        }

        // Keep the scan quick without opening thousands of simultaneous sockets.
        let concurrency = 96
        await withTaskGroup(of: DiscoveredMusicServer?.self) { group in
            var nextTarget = targets.startIndex

            func enqueueNext() {
                guard nextTarget < targets.endIndex else { return }
                let target = targets[nextTarget]
                nextTarget = targets.index(after: nextTarget)
                group.addTask { await Self.probe(target) }
            }

            for _ in 0..<min(concurrency, targets.count) { enqueueNext() }
            while let server = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }
                if let server {
                    addServer(name: server.name, address: server.address, backend: server.backend)
                }
                enqueueNext()
            }
        }
    }

    private enum ScanFamily: Sendable {
        case subsonic
        case mediaBrowser
        case plex
    }

    private struct ScanPort: Sendable {
        let port: Int
        let family: ScanFamily
    }

    private struct ScanTarget: Sendable {
        let host: String
        let port: Int
        let family: ScanFamily
    }

    private static let scanSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 0.8
        configuration.timeoutIntervalForResource = 1.2
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private static func probe(_ target: ScanTarget) async -> DiscoveredMusicServer? {
        guard !Task.isCancelled else { return nil }
        switch target.family {
        case .subsonic:
            return await probeSubsonic(host: target.host, port: target.port)
        case .mediaBrowser:
            return await probeMediaBrowser(host: target.host, port: target.port)
        case .plex:
            return await probePlex(host: target.host, port: target.port)
        }
    }

    private static func probeSubsonic(host: String, port: Int) async -> DiscoveredMusicServer? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/rest/ping.view"
        components.queryItems = [
            URLQueryItem(name: "u", value: "volta-discovery"),
            URLQueryItem(name: "p", value: "volta-discovery"),
            URLQueryItem(name: "v", value: SubsonicClient.apiVersion),
            URLQueryItem(name: "c", value: SubsonicClient.clientName),
            URLQueryItem(name: "f", value: "json"),
        ]
        guard let url = components.url,
              let data = await responseData(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let envelopeEntry = object.first(where: { $0.key.caseInsensitiveCompare("subsonic-response") == .orderedSame }),
              let envelope = envelopeEntry.value as? [String: Any] else { return nil }

        let type = envelope.first(where: { $0.key.caseInsensitiveCompare("type") == .orderedSame })?.value as? String
        let product = type?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Subsonic Server"
        return DiscoveredMusicServer(
            name: product.capitalized,
            address: "http://\(host):\(port)",
            backend: .subsonic
        )
    }

    private static func probeMediaBrowser(host: String, port: Int) async -> DiscoveredMusicServer? {
        guard let url = URL(string: "http://\(host):\(port)/System/Info/Public"),
              let data = await responseData(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let values = Dictionary(uniqueKeysWithValues: object.map { ($0.key.lowercased(), $0.value) })
        let product = (values["productname"] as? String)?.lowercased() ?? ""
        let backend: MusicBackendKind
        if product.contains("jellyfin") {
            backend = .jellyfin
        } else if product.contains("emby")
                    || (product.isEmpty
                        && values["servername"] is String
                        && values["version"] is String
                        && values["id"] is String) {
            // Current Emby releases omit ProductName from this otherwise
            // distinctive public server-info payload.
            backend = .emby
        } else {
            return nil
        }
        let name = (values["servername"] as? String)?.nonEmpty ?? backend.displayName
        return DiscoveredMusicServer(name: name, address: "http://\(host):\(port)", backend: backend)
    }

    private static func probePlex(host: String, port: Int) async -> DiscoveredMusicServer? {
        guard let url = URL(string: "http://\(host):\(port)/identity"),
              let data = await responseData(from: url),
              let response = String(data: data, encoding: .utf8),
              response.localizedCaseInsensitiveContains("MediaContainer"),
              response.localizedCaseInsensitiveContains("machineIdentifier") else { return nil }
        return DiscoveredMusicServer(
            name: "Plex Media Server",
            address: "http://\(host):\(port)",
            backend: .plex
        )
    }

    private static func responseData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await scanSession.data(for: request)
            return data
        } catch {
            return nil
        }
    }

    private func addDatagramSearch(
        message: String,
        host: String,
        port: UInt16,
        handler: @escaping (Data, String) -> Void
    ) {
        guard let search = DatagramSearch(
            message: Data(message.utf8),
            host: host,
            port: port,
            onResponse: { data, sender in
                Task { @MainActor in handler(data, sender) }
            }
        ) else { return }
        datagramSearches.append(search)
        search.start()
    }

    private func handleMediaBrowserResponse(_ data: Data, backend: MusicBackendKind) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let values = Dictionary(uniqueKeysWithValues: object.map { ($0.key.lowercased(), $0.value) })
        guard let address = values["address"] as? String,
              URL(string: address)?.host != nil else { return }
        let name = (values["name"] as? String)?.nonEmpty ?? backend.displayName
        addServer(name: name, address: address, backend: backend)
    }

    private func handlePlexResponse(_ data: Data, host: String) {
        guard let response = String(data: data, encoding: .utf8),
              response.lowercased().contains("plex/media-server") else { return }
        let headers = Self.headers(in: response)
        let port = Int(headers["port"] ?? "") ?? 32400
        let name = headers["name"]?.nonEmpty ?? "Plex Media Server"
        addServer(name: name, address: "http://\(host):\(port)", backend: .plex)
    }

    private func handleSSDPResponse(_ data: Data) {
        guard let response = String(data: data, encoding: .utf8) else { return }
        let headers = Self.headers(in: response)
        let signature = ([headers["server"], headers["st"], headers["usn"]]
            .compactMap { $0 } + [response]).joined(separator: " ").lowercased()
        let backend: MusicBackendKind
        if signature.contains("jellyfin") {
            backend = .jellyfin
        } else if signature.contains("emby") {
            backend = .emby
        } else if signature.contains("plex") {
            backend = .plex
        } else if signature.contains("navidrome") || signature.contains("subsonic") || signature.contains("airsonic") {
            backend = .subsonic
        } else {
            return
        }

        guard let location = headers["location"],
              let locationURL = URL(string: location),
              var components = URLComponents(url: locationURL, resolvingAgainstBaseURL: false) else { return }
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let address = components.url?.absoluteString else { return }
        addServer(name: backend.displayName, address: address, backend: backend)
    }

    private static func headers(in response: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in response.components(separatedBy: .newlines) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }
        return headers
    }

    private func addServer(name: String, address: String, backend: MusicBackendKind) {
        guard let normalized = Self.normalizedAddress(address) else { return }
        let server = DiscoveredMusicServer(name: name, address: normalized, backend: backend)
        guard !servers.contains(where: { $0.id == server.id }) else { return }
        servers.append(server)
        servers.sort {
            if $0.backend.displayName != $1.backend.displayName {
                return $0.backend.displayName < $1.backend.displayName
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func normalizedAddress(_ address: String) -> String? {
        guard var components = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.host != nil,
              components.scheme == "http" || components.scheme == "https" else { return nil }
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.url?.absoluteString
    }
}

extension LocalServerDiscovery: NetServiceBrowserDelegate, NetServiceDelegate {
    nonisolated func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.isScanning else { return }
            service.delegate = self
            self.resolvingServices.append(service)
            service.resolve(withTimeout: 5)
        }
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        Task { @MainActor [weak self] in
            self?.handleResolvedBonjourService(sender)
        }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        Task { @MainActor [weak self] in
            self?.resolvingServices.removeAll { $0 === sender }
        }
    }

    private func handleResolvedBonjourService(_ service: NetService) {
        defer { resolvingServices.removeAll { $0 === service } }
        guard let backend = Self.backend(for: service),
              let host = service.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty else { return }

        let txt = service.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        let schemeFromTXT = Self.txtString("scheme", in: txt)?.lowercased()
        let scheme = schemeFromTXT == "https" || service.type.lowercased().contains("_https") ? "https" : "http"
        let path = Self.txtString("path", in: txt) ?? ""
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if !((scheme == "http" && service.port == 80) || (scheme == "https" && service.port == 443)) {
            components.port = service.port
        }
        components.path = path.hasPrefix("/") || path.isEmpty ? path : "/" + path
        guard let address = components.url?.absoluteString else { return }
        addServer(name: service.name.nonEmpty ?? backend.displayName, address: address, backend: backend)
    }

    private static func backend(for service: NetService) -> MusicBackendKind? {
        let type = service.type.lowercased()
        let txt = service.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        let txtSignature = txt.values.compactMap { String(data: $0, encoding: .utf8) }.joined(separator: " ")
        let signature = "\(service.name) \(type) \(txtSignature)".lowercased()
        if signature.contains("jellyfin") { return .jellyfin }
        if signature.contains("emby") { return .emby }
        if signature.contains("plex") { return .plex }
        if signature.contains("navidrome") || signature.contains("subsonic") || signature.contains("airsonic") || signature.contains("gonic") {
            return .subsonic
        }
        return nil
    }

    private static func txtString(_ key: String, in record: [String: Data]) -> String? {
        guard let match = record.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) else { return nil }
        return String(data: match.value, encoding: .utf8)
    }
}

private final class DatagramSearch {
    private let descriptor: Int32
    private let message: Data
    private let destination: sockaddr_in
    private let queue = DispatchQueue(label: "com.ayo.music.server-discovery")
    private let onResponse: (Data, String) -> Void
    private var readSource: DispatchSourceRead?

    init?(message: Data, host: String, port: UInt16, onResponse: @escaping (Data, String) -> Void) {
        let descriptor = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return nil }

        var enabled: Int32 = 1
        guard Darwin.setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_BROADCAST,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            Darwin.close(descriptor)
            return nil
        }

        var localAddress = sockaddr_in()
        localAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        localAddress.sin_family = sa_family_t(AF_INET)
        localAddress.sin_port = 0
        localAddress.sin_addr = in_addr(s_addr: INADDR_ANY)
        let bindResult = withUnsafePointer(to: &localAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(descriptor)
            return nil
        }

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = port.bigEndian
        guard host.withCString({ Darwin.inet_pton(AF_INET, $0, &destination.sin_addr) }) == 1 else {
            Darwin.close(descriptor)
            return nil
        }

        self.descriptor = descriptor
        self.message = message
        self.destination = destination
        self.onResponse = onResponse
    }

    func start() {
        guard readSource == nil else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.receiveAvailableDatagrams() }
        source.setCancelHandler { [descriptor] in Darwin.close(descriptor) }
        readSource = source
        source.resume()

        var destination = destination
        message.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            withUnsafePointer(to: &destination) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = Darwin.sendto(
                        descriptor,
                        baseAddress,
                        bytes.count,
                        0,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
    }

    private func receiveAvailableDatagrams() {
        while true {
            var buffer = [UInt8](repeating: 0, count: 65_535)
            var sender = sockaddr_storage()
            var senderLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let count = withUnsafeMutablePointer(to: &sender) { senderPointer in
                senderPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    Darwin.recvfrom(descriptor, &buffer, buffer.count, MSG_DONTWAIT, socketAddress, &senderLength)
                }
            }
            guard count > 0 else { return }
            guard let host = Self.ipv4Address(from: sender) else { continue }
            onResponse(Data(buffer.prefix(count)), host)
        }
    }

    private static func ipv4Address(from storage: sockaddr_storage) -> String? {
        guard Int32(storage.ss_family) == AF_INET else { return nil }
        var storage = storage
        var address = withUnsafePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
        }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard Darwin.inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        return String(cString: buffer)
    }
}

private struct IPv4Network {
    let address: UInt32
    let netmask: UInt32

    static func current() -> IPv4Network? {
        var interfaceList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceList) == 0, let first = interfaceList else { return nil }
        defer { freeifaddrs(interfaceList) }

        var candidates: [(name: String, network: IPv4Network)] = []
        var interface: UnsafeMutablePointer<ifaddrs>? = first
        while let current = interface {
            defer { interface = current.pointee.ifa_next }
            guard let socketAddress = current.pointee.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET),
                  let maskAddress = current.pointee.ifa_netmask else { continue }

            let flags = current.pointee.ifa_flags
            guard flags & UInt32(IFF_UP) != 0,
                  flags & UInt32(IFF_LOOPBACK) == 0 else { continue }

            let name = String(cString: current.pointee.ifa_name)
            let address = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            let netmask = maskAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            guard isPrivate(address), netmask != 0 else { continue }
            candidates.append((name, IPv4Network(address: address, netmask: netmask)))
        }

        return candidates.first(where: { $0.name == "en0" })?.network ?? candidates.first?.network
    }

    var hostAddresses: [String] {
        // Never expand beyond the local /24. This keeps Auto discovery bounded
        // even on networks configured with a much wider mask.
        let effectiveMask = netmask.nonzeroBitCount < 24 ? UInt32(0xFFFFFF00) : netmask
        let networkAddress = address & effectiveMask
        let broadcastAddress = networkAddress | ~effectiveMask
        guard broadcastAddress > networkAddress + 1 else { return [] }

        return ((networkAddress + 1)..<broadcastAddress).compactMap { candidate in
            guard candidate != address else { return nil }
            return Self.string(from: candidate)
        }
    }

    private static func isPrivate(_ address: UInt32) -> Bool {
        let first = (address >> 24) & 0xFF
        let second = (address >> 16) & 0xFF
        return first == 10
            || (first == 172 && (16...31).contains(second))
            || (first == 192 && second == 168)
    }

    private static func string(from address: UInt32) -> String {
        "\((address >> 24) & 0xFF).\((address >> 16) & 0xFF).\((address >> 8) & 0xFF).\(address & 0xFF)"
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
