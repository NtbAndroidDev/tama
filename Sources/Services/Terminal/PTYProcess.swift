import Foundation
import Darwin

/// A shell on a pseudo-terminal: `forkpty` gives it a controlling tty, so
/// Ctrl-C, job control, `vim` and `top` behave as they do in Terminal.
/// Output arrives on a background queue; callers hop to the main actor.
final class PTYProcess: @unchecked Sendable {
    let pid: pid_t
    private let master: Int32
    private let queue = DispatchQueue(label: "app.tama.pty")
    private var readSource: DispatchSourceRead?
    private var exitSource: DispatchSourceProcess?
    private let lock = NSLock()
    private var closed = false

    enum SpawnError: Error, LocalizedError {
        case forkFailed(Int32)
        var errorDescription: String? {
            switch self {
            case let .forkFailed(code): "Couldn't start the shell (\(String(cString: strerror(code))))."
            }
        }
    }

    /// Starts `executable` with `arguments` (argv[0] included) on a new pty.
    /// Everything the child needs is turned into C strings before forking:
    /// between fork and exec only async-signal-safe calls are allowed.
    init(executable: String, arguments: [String], environment: [String: String], directory: String,
         columns: Int, rows: Int,
         onData: @escaping @Sendable (Data) -> Void, onExit: @escaping @Sendable (Int32) -> Void) throws {
        let path = strdup(executable)
        let cwd = strdup(directory)
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            free(path)
            free(cwd)
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var size = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: columns), ws_xpixel: 0, ws_ypixel: 0)
        var masterFD: Int32 = -1
        let child = argv.withUnsafeBufferPointer { argvBuffer in
            envp.withUnsafeBufferPointer { envBuffer in
                Self.forkAndExec(&masterFD, &size, path, cwd, argvBuffer.baseAddress, envBuffer.baseAddress)
            }
        }
        guard child > 0 else { throw SpawnError.forkFailed(errno) }
        pid = child
        master = masterFD
        _ = fcntl(master, F_SETFD, FD_CLOEXEC)
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

        let read = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        let fd = master
        read.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 32 * 1024)
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                onData(Data(buffer[0..<count]))
            } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
                // EIO: the shell and everything on its tty has gone.
                self?.readSource?.cancel()
            }
        }
        readSource = read
        read.resume()

        let exit = DispatchSource.makeProcessSource(identifier: child, eventMask: .exit, queue: queue)
        exit.setEventHandler { [weak self] in
            var status: Int32 = 0
            waitpid(child, &status, 0)
            self?.closeMaster()
            onExit(status)
            self?.exitSource?.cancel()
        }
        exitSource = exit
        exit.resume()
    }

    /// The child side runs only C calls: chdir, execve, _exit.
    private static func forkAndExec(_ master: UnsafeMutablePointer<Int32>, _ size: UnsafeMutablePointer<winsize>,
                                    _ path: UnsafeMutablePointer<CChar>?, _ cwd: UnsafeMutablePointer<CChar>?,
                                    _ argv: UnsafePointer<UnsafeMutablePointer<CChar>?>?,
                                    _ envp: UnsafePointer<UnsafeMutablePointer<CChar>?>?) -> pid_t {
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)
        let pid = forkpty(master, nil, nil, size)
        if pid == 0 {
            // Signal masks and ignored signals survive exec: a shell started
            // from a thread that blocks SIGINT would never see Ctrl-C.
            sigprocmask(SIG_SETMASK, &emptyMask, nil)
            var signal: Int32 = 1
            while signal < NSIG {
                _ = Darwin.signal(signal, SIG_DFL)
                signal += 1
            }
            _ = chdir(cwd)
            execve(path, argv, envp)
            _exit(127)
        }
        return pid
    }

    func write(_ data: Data) {
        guard !data.isEmpty else { return }
        let fd = master
        queue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            data.withUnsafeBytes { raw in
                guard var pointer = raw.baseAddress else { return }
                var remaining = raw.count
                var attempts = 0
                while remaining > 0, attempts < 200 {
                    let written = Darwin.write(fd, pointer, remaining)
                    if written > 0 {
                        remaining -= written
                        pointer += written
                    } else if errno == EAGAIN || errno == EINTR {
                        attempts += 1
                        usleep(2_000)
                    } else {
                        return
                    }
                }
            }
        }
    }

    func resize(columns: Int, rows: Int) {
        let size = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: columns), ws_xpixel: 0, ws_ypixel: 0)
        let fd = master
        queue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            var value = size
            _ = ioctl(fd, TIOCSWINSZ, &value)
        }
    }

    /// The directory the shell is in right now (follows `cd`).
    var currentDirectory: String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            let path = String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            return path.isEmpty ? nil : path
        }
    }

    /// The command running in the foreground on the tty ("vim", "npm"), or
    /// nil while the shell itself waits at the prompt.
    var foregroundCommand: String? {
        let group = tcgetpgrp(master)
        guard group > 0, group != pid else { return nil }
        var name = [CChar](repeating: 0, count: 256)
        guard proc_name(group, &name, UInt32(name.count)) > 0 else { return nil }
        return String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Hangs up the tty (SIGHUP to everything on it), then makes sure the shell goes.
    func terminate() {
        let pid = self.pid
        kill(-pid, SIGHUP)
        kill(pid, SIGHUP)
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, !self.isClosed else { return }
            kill(-pid, SIGKILL)
            kill(pid, SIGKILL)
        }
    }

    private var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    private func closeMaster() {
        lock.lock()
        let wasClosed = closed
        closed = true
        lock.unlock()
        guard !wasClosed else { return }
        readSource?.cancel()
        close(master)
    }

    deinit {
        if !isClosed {
            kill(pid, SIGHUP)
            closeMaster()
        }
    }
}
