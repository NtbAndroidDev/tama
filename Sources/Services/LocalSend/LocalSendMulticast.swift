import Foundation
import Darwin

/// LocalSend discovery: a UDP socket joined to 224.0.0.167:53317 that hears
/// other devices' announcements and sends ours. Plain BSD sockets, so it can
/// share the port (SO_REUSEPORT) with the real LocalSend app on this Mac.
/// A non-sandboxed Mac app needs no multicast entitlement; macOS 15+ asks
/// the user once for Local Network access (NSLocalNetworkUsageDescription).
final class LocalSendMulticast: @unchecked Sendable {
    /// A datagram and the address it came from.
    typealias Handler = @Sendable (Data, String) -> Void

    private var socketFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "app.tama.localsend.multicast")
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw LocalSendError.discovery(String(cString: strerror(errno))) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = LocalSendProtocol.port.bigEndian
        address.sin_addr.s_addr = INADDR_ANY.bigEndian
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw LocalSendError.discovery(reason)
        }

        // Join the group on every IPv4 interface that's up, so Wi-Fi and
        // Ethernet both hear announcements.
        var joined = false
        for interface in Self.ipv4Interfaces() {
            var request = ip_mreq()
            request.imr_multiaddr.s_addr = inet_addr(LocalSendProtocol.multicastGroup)
            request.imr_interface.s_addr = interface
            if setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &request, socklen_t(MemoryLayout<ip_mreq>.size)) == 0 { joined = true }
        }
        if !joined {
            var request = ip_mreq()
            request.imr_multiaddr.s_addr = inet_addr(LocalSendProtocol.multicastGroup)
            request.imr_interface.s_addr = INADDR_ANY.bigEndian
            guard setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &request, socklen_t(MemoryLayout<ip_mreq>.size)) == 0 else {
                let reason = String(cString: strerror(errno))
                close(fd)
                throw LocalSendError.discovery(reason)
            }
        }
        var ttl: UInt8 = 4
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        // Our own announcements come back on loopback; they're filtered by fingerprint.
        var loop: UInt8 = 1
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, socklen_t(MemoryLayout<UInt8>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        socketFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let handler = self.handler
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            while true {
                let count = withUnsafeMutablePointer(to: &from) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &length) }
                }
                guard count > 0 else { break }
                var host = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var addr = from.sin_addr
                inet_ntop(AF_INET, &addr, &host, socklen_t(INET_ADDRSTRLEN))
                let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                handler(Data(buffer[0..<count]), ip)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    /// Sends one datagram to the group, out of every interface.
    func send(_ payload: Data) {
        let fd = socketFD
        guard fd >= 0 else { return }
        queue.async {
            var destination = sockaddr_in()
            destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            destination.sin_family = sa_family_t(AF_INET)
            destination.sin_port = LocalSendProtocol.port.bigEndian
            destination.sin_addr.s_addr = inet_addr(LocalSendProtocol.multicastGroup)
            let interfaces = Self.ipv4Interfaces()
            for interface in interfaces.isEmpty ? [INADDR_ANY.bigEndian] : interfaces {
                var out = in_addr(s_addr: interface)
                setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &out, socklen_t(MemoryLayout<in_addr>.size))
                payload.withUnsafeBytes { bytes in
                    _ = withUnsafePointer(to: &destination) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
            }
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        socketFD = -1
    }

    /// Addresses (network byte order) of the IPv4 interfaces that are up,
    /// multicast-capable and not loopback.
    static func ipv4Interfaces() -> [in_addr_t] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var result: [in_addr_t] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = pointer.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (ifa.ifa_flags & UInt32(IFF_UP)) != 0, (ifa.ifa_flags & UInt32(IFF_MULTICAST)) != 0,
                  (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            let value = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            if !result.contains(value) { result.append(value) }
        }
        return result
    }
}
