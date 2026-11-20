import Darwin
import Foundation
import Synchronization

/// The bundled executable talks to the running app when invoked from a shell.
nonisolated enum StayAwakeCommand: Sendable, Equatable {
    case start(minutes: Int)
    case extend(minutes: Int)
    case status
    case end

    private static let usage = "Usage: Graft --caffeinate {start 1–240 | extend 1–240 | status | end} (minutes)"

    static func runIfRequested() {
        let arguments = CommandLine.arguments.dropFirst()
        guard arguments.first == "--caffeinate" || arguments.first == "--stay-awake" else { return }
        guard let command = parse(Array(arguments.dropFirst())) else {
            writeError(usage)
            exit(2)
        }

        do {
            let reply = try StayAwakeSocket.request(command)
            if reply.success { print(reply.message) }
            else { writeError(reply.message) }
            exit(reply.success ? EXIT_SUCCESS : EXIT_FAILURE)
        } catch {
            writeError(error.localizedDescription)
            exit(EXIT_FAILURE)
        }
    }

    static func parse(_ arguments: [String]) -> Self? {
        switch arguments.first {
        case "status" where arguments.count == 1: return .status
        case "end" where arguments.count == 1: return .end
        case "start", "extend":
            guard arguments.count == 2, let minutes = Int(arguments[1]), (1...240).contains(minutes) else { return nil }
            return arguments[0] == "start" ? .start(minutes: minutes) : .extend(minutes: minutes)
        default: return nil
        }
    }

    fileprivate var requestLine: String {
        switch self {
        case .start(let minutes): "start \(minutes)"
        case .extend(let minutes): "extend \(minutes)"
        case .status: "status"
        case .end: "end"
        }
    }

    private static func writeError(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
    }
}

nonisolated struct StayAwakeCommandReply: Sendable {
    let success: Bool
    let message: String

    fileprivate var responseLine: String {
        let singleLine = message.components(separatedBy: .newlines).joined(separator: " ")
        return (success ? "1 " : "0 ") + String(decoding: singleLine.utf8.prefix(1_000), as: UTF8.self)
    }

    fileprivate init?(responseLine: String) {
        guard responseLine.hasPrefix("1 ") || responseLine.hasPrefix("0 ") else { return nil }
        success = responseLine.hasPrefix("1 ")
        message = String(responseLine.dropFirst(2))
    }

    init(success: Bool, message: String) {
        self.success = success
        self.message = message
    }
}

final class StayAwakeCommandServer {
    private var listener: DispatchSourceRead?

    init(handler: @escaping @MainActor @Sendable (StayAwakeCommand) -> StayAwakeCommandReply) {
        do {
            let endpoint = try StayAwakeSocket.listen()
            let queue = DispatchQueue(label: "com.itsasheruwu.graft.stay-awake", qos: .utility)
            let source = DispatchSource.makeReadSource(fileDescriptor: endpoint.socket, queue: queue)
            source.setEventHandler { @Sendable [weak self] in
                StayAwakeSocket.accept(on: endpoint.socket) { command, deadline, mailbox in
                    Task { @MainActor [weak self] in
                        guard self?.listener != nil, DispatchTime.now() < deadline, !Task.isCancelled else { return }
                        let reply = handler(command)
                        mailbox.reply.withLock { $0 = reply }
                        mailbox.ready.signal()
                    }
                }
            }
            source.setCancelHandler { @Sendable in
                _ = close(endpoint.socket)
                _ = unlink(endpoint.path)
                _ = close(endpoint.lock)
            }
            listener = source
            source.resume()
        } catch {
            NSLog("Graft could not start the Caffeinate command listener: %@", error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    isolated deinit { stop() }
}

private nonisolated enum StayAwakeSocket {
    struct Endpoint: Sendable {
        let socket: Int32
        let lock: Int32
        let path: String
    }

    final class Mailbox: Sendable {
        let reply = Mutex<StayAwakeCommandReply?>(nil)
        let ready = DispatchSemaphore(value: 0)
    }

    private enum ConnectionError: LocalizedError {
        case unavailable, timeout, protocolError

        var errorDescription: String? {
            switch self {
            case .unavailable: "Open Graft and try the Caffeinate command again."
            case .timeout: "Graft did not answer the Caffeinate command in time."
            case .protocolError: "Graft received an invalid Caffeinate command or reply."
            }
        }
    }

    static func request(_ command: StayAwakeCommand) throws -> StayAwakeCommandReply {
        let path = try privateDirectory(create: false) + "/session.sock"
        let socket = try makeSocket()
        defer { _ = close(socket) }
        let deadline = DispatchTime.now() + .seconds(3)
        let result = try withAddress(path) { Darwin.connect(socket, $0, $1) }
        if result != 0 {
            guard errno == EINPROGRESS else { throw ConnectionError.unavailable }
            try wait(socket, for: Int16(POLLOUT), until: deadline)
            var status: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(socket, SOL_SOCKET, SO_ERROR, &status, &size) == 0, status == 0 else {
                throw ConnectionError.unavailable
            }
        }
        guard peerIsCurrentUser(socket) else { throw ConnectionError.unavailable }
        try write(command.requestLine, to: socket, until: deadline)
        let line = try read(from: socket, limit: 4_096, until: deadline)
        guard let reply = StayAwakeCommandReply(responseLine: line) else { throw ConnectionError.protocolError }
        return reply
    }

    static func listen() throws -> Endpoint {
        let directory = try privateDirectory(create: true)
        let path = directory + "/session.sock"
        let lock = open(directory + "/listener.lock", O_WRONLY | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw ConnectionError.unavailable }
        do {
            var info = stat()
            guard fstat(lock, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
                  flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw ConnectionError.unavailable }
            // The lock stays open for the listener's lifetime, so a new instance
            // can remove a socket left by a crash without unlinking a live one.
            if unlink(path) != 0, errno != ENOENT { throw ConnectionError.unavailable }
            let socket = try makeSocket()
            do {
                guard try withAddress(path, { Darwin.bind(socket, $0, $1) }) == 0,
                      chmod(path, 0o600) == 0,
                      Darwin.listen(socket, 4) == 0 else { throw ConnectionError.unavailable }
                return Endpoint(socket: socket, lock: lock, path: path)
            } catch {
                _ = close(socket)
                _ = unlink(path)
                throw error
            }
        } catch {
            _ = close(lock)
            throw error
        }
    }

    static func accept(
        on listener: Int32,
        handle: (StayAwakeCommand, DispatchTime, Mailbox) -> Task<Void, Never>
    ) {
        let socket = Darwin.accept(listener, nil, nil)
        guard socket >= 0 else { return }
        defer { _ = close(socket) }
        guard peerIsCurrentUser(socket), configure(socket) else { return }

        do {
            let line = try read(from: socket, limit: 64, until: .now() + .seconds(1))
            guard let command = StayAwakeCommand.parse(line.split(separator: " ").map(String.init)) else {
                throw ConnectionError.protocolError
            }
            let mailbox = Mailbox()
            let deadline = DispatchTime.now() + .seconds(1)
            // Read and wait on the listener's queue. The handler alone runs on
            // the main actor, and a command still queued at expiry is skipped.
            let task = handle(command, deadline, mailbox)
            guard mailbox.ready.wait(timeout: deadline) == .success,
                  let reply = mailbox.reply.withLock({ $0 }) else {
                task.cancel()
                throw ConnectionError.timeout
            }
            try write(reply.responseLine, to: socket, until: .now() + .milliseconds(250))
        } catch {
            let reply = StayAwakeCommandReply(success: false, message: error.localizedDescription)
            try? write(reply.responseLine, to: socket, until: .now() + .milliseconds(250))
        }
    }

    private static func privateDirectory(create: Bool) throws -> String {
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        guard length > 1 else { throw ConnectionError.unavailable }
        var temporary = [CChar](repeating: 0, count: length)
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &temporary, length) == length else {
            throw ConnectionError.unavailable
        }
        let path = String(decoding: temporary.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self) + "GraftStayAwake"
        if create, mkdir(path, 0o700) != 0, errno != EEXIST { throw ConnectionError.unavailable }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw ConnectionError.unavailable }
        return path
    }

    private static func makeSocket() throws -> Int32 {
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { throw ConnectionError.unavailable }
        guard configure(socket) else {
            _ = close(socket)
            throw ConnectionError.unavailable
        }
        return socket
    }

    private static func configure(_ socket: Int32) -> Bool {
        var enabled: Int32 = 1
        return fcntl(socket, F_SETFL, O_NONBLOCK) == 0 && fcntl(socket, F_SETFD, FD_CLOEXEC) == 0
            && setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0
    }

    private static func peerIsCurrentUser(_ socket: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(socket, &uid, &gid) == 0 && uid == getuid()
    }

    private static func withAddress<T>(_ path: String, _ operation: (UnsafePointer<sockaddr>, socklen_t) -> T) throws -> T {
        var address = sockaddr_un()
        let bytes = path.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path),
              let offset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) else { throw ConnectionError.unavailable }
        let length = offset + bytes.count
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(length)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            bytes.withUnsafeBytes { destination.copyBytes(from: $0) }
        }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { operation($0, socklen_t(length)) }
        }
    }

    private static func wait(_ socket: Int32, for event: Int16, until deadline: DispatchTime) throws {
        var descriptor = pollfd(fd: socket, events: event, revents: 0)
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline.uptimeNanoseconds else { throw ConnectionError.timeout }
            let remaining = (deadline.uptimeNanoseconds - now + 999_999) / 1_000_000
            let result = poll(&descriptor, 1, Int32(remaining))
            if result > 0 {
                guard descriptor.revents & event != 0 else { throw ConnectionError.unavailable }
                return
            }
            if result == 0 { throw ConnectionError.timeout }
            guard errno == EINTR else { throw ConnectionError.unavailable }
        }
    }

    private static func read(from socket: Int32, limit: Int, until deadline: DispatchTime) throws -> String {
        var bytes = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 256)
        while bytes.count < limit {
            try wait(socket, for: Int16(POLLIN), until: deadline)
            let received = recv(socket, &chunk, min(chunk.count, limit - bytes.count), 0)
            if received < 0, [EAGAIN, EINTR].contains(errno) { continue }
            guard received > 0 else { throw ConnectionError.unavailable }
            let data = chunk.prefix(received)
            if let newline = data.firstIndex(of: 0x0a) {
                bytes.append(contentsOf: data.prefix(upTo: newline))
                guard let line = String(bytes: bytes, encoding: .utf8) else { throw ConnectionError.protocolError }
                return line
            }
            bytes.append(contentsOf: data)
        }
        throw ConnectionError.protocolError
    }

    private static func write(_ line: String, to socket: Int32, until deadline: DispatchTime) throws {
        let bytes = Array((line + "\n").utf8)
        var written = 0
        while written < bytes.count {
            try wait(socket, for: Int16(POLLOUT), until: deadline)
            let count = bytes.withUnsafeBufferPointer {
                send(socket, $0.baseAddress?.advanced(by: written), $0.count - written, 0)
            }
            if count < 0, [EAGAIN, EINTR].contains(errno) { continue }
            guard count > 0 else { throw ConnectionError.unavailable }
            written += count
        }
    }
}
