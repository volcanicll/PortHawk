import Foundation
import Darwin

/// One listening record: which process (pid) listens on which port, and which
/// project it belongs to.
struct PortEntry: Identifiable, Equatable {
    let port: Int
    let pid: pid_t
    let processName: String
    /// The address lsof reported for this listener: "*", "0.0.0.0", "127.0.0.1",
    /// "[::1]", "192.168.1.5"… Kept verbatim so both the exposure verdict and
    /// the browser target are derived from what is actually bound, rather than
    /// from a stored flag that could drift out of step with it.
    let host: String
    /// Project name (directory basename) inferred from the process working
    /// directory; nil for system processes.
    let project: String?
    let projectPath: String?

    var id: String { "\(port)-\(pid)" }

    /// true = reachable from outside this process (wildcard or a specific
    /// interface address); false = loopback only.
    var isLanExposed: Bool { PortScanner.isExposed(host: host) }
    var scopeText: String { isLanExposed ? "LAN" : "local" }

    /// Host to hand a browser. A wildcard bind is also reachable on loopback, so
    /// 127.0.0.1 is the target that always works; a listener bound to one
    /// specific interface address is only reachable there. An IPv6 literal keeps
    /// its brackets, as URLs require.
    var browseHost: String {
        let h = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if h.isEmpty || h == "*" || h == "0.0.0.0" || h == "::" { return "127.0.0.1" }
        if h == "::1" { return "[::1]" }
        return h.contains(":") ? "[\(h)]" : h
    }

    /// Ports where TLS is a safe assumption, so the browser is not pointed at a
    /// plaintext URL in front of an HTTPS listener.
    private static let tlsPorts: Set<Int> = [443, 8443, 9443]

    /// Where to open this listener. nil for placeholder rows (no process) and
    /// for anything that is not a real port.
    var browseURL: URL? {
        guard pid > 0, port > 0, port <= 65535 else { return nil }
        let scheme = Self.tlsPorts.contains(port) ? "https" : "http"
        return URL(string: "\(scheme)://\(browseHost):\(port)/")
    }
}

enum PortScanner {
    /// Scan every TCP listener via lsof and attach each process's working directory.
    /// Returns nil when the scan itself failed (spawn failure / timeout), in which
    /// case callers must keep the previous snapshot; an empty array means the scan
    /// succeeded and there is genuinely nothing listening.
    static func scan() -> [PortEntry]? {
        guard let output = runLsof() else { return nil }
        return parseAll(output)
    }

    /// Parse a full lsof table into entries, collapsing IPv4/IPv6 dual-stack
    /// duplicates. Split out from `scan()` so the parsing rules are testable
    /// without spawning a process.
    static func parseAll(_ output: String) -> [PortEntry] {
        var indexByID: [String: Int] = [:]
        var entries: [PortEntry] = []
        for line in output.split(separator: "\n").dropFirst() {
            guard let entry = parse(String(line)) else { continue }
            if let existing = indexByID[entry.id] {
                // Dual-stack: one (port, pid) can listen on loopback and on a
                // wildcard address at once. Keep the widest exposure, otherwise a
                // LAN-reachable socket is masked whenever lsof happens to print
                // the 127.0.0.1 row first.
                if entry.isLanExposed && !entries[existing].isLanExposed {
                    entries[existing] = entry
                }
                continue
            }
            indexByID[entry.id] = entries.count
            entries.append(entry)
        }
        return entries
    }

    static func kill(pid: pid_t, force: Bool) -> Bool {
        Darwin.kill(pid, force ? SIGKILL : SIGTERM) == 0
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        Darwin.kill(pid, 0) == 0
    }

    // MARK: - Detail data

    struct ProcessDetail {
        let commandLine: [String]?
        let userName: String?
        let parentPID: pid_t?
        let residentBytes: UInt64?
        let threadCount: Int32?
        /// CPU time accumulated since process start, in seconds.
        let cpuSeconds: Double?
        /// Executable path (argv[0]); unavailable for other users' processes.
        let executablePath: String?
    }

    /// Collect everything the detail page needs in one pass. Any field that
    /// cannot be read becomes nil, which is common for other users' processes.
    static func detail(for pid: pid_t) -> ProcessDetail {
        let commandLine = commandLine(for: pid)
        let taskInfo = taskInfo(for: pid)
        return ProcessDetail(
            commandLine: commandLine,
            userName: userName(for: pid),
            parentPID: parentPID(for: pid),
            residentBytes: taskInfo?.residentBytes,
            threadCount: taskInfo?.threadCount,
            cpuSeconds: taskInfo?.cpuSeconds,
            executablePath: commandLine?.first
        )
    }

    /// Instantaneous CPU-time sample (seconds); diff two samples to get CPU%.
    static func cpuSecondsSnapshot(for pid: pid_t) -> Double? {
        taskInfo(for: pid)?.cpuSeconds
    }

    private static func taskInfo(for pid: pid_t) -> (residentBytes: UInt64, threadCount: Int32, cpuSeconds: Double)? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, size)
        }
        guard result > 0 else { return nil }
        return (info.pti_resident_size, info.pti_threadnum, Double(info.pti_total_user + info.pti_total_system) / 1e9)
    }

    private static func parentPID(for pid: pid_t) -> pid_t? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &proc, &size, nil, 0) == 0,
              proc.kp_proc.p_pid == pid,
              proc.kp_eproc.e_ppid > 0 else { return nil }
        return proc.kp_eproc.e_ppid
    }

    private static func userName(for pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &proc, &size, nil, 0) == 0, proc.kp_proc.p_pid == pid else { return nil }
        guard let pw = getpwuid(proc.kp_eproc.e_pcred.p_ruid), let name = pw.pointee.pw_name else {
            return String(proc.kp_eproc.e_pcred.p_ruid)
        }
        return String(cString: name)
    }

    /// Full command line: sysctl KERN_PROCARGS2 -> [argc][exec_path][NUL padding][argv…][env…]
    static func commandLine(for pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<UInt32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        let argc = buffer.withUnsafeBytes { $0.load(as: UInt32.self) }
        guard argc > 0, argc < 4096 else { return nil }

        // Layout: argc, then NUL-terminated exec_path, some alignment NULs, then
        // the argv strings back to back.
        var strings: [String] = []
        var index = MemoryLayout<UInt32>.size
        while index < size, strings.count < Int(argc) {
            if buffer[index] == 0 { index += 1; continue }
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            strings.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return strings.isEmpty ? nil : strings
    }

    // MARK: - Private

    private static func runLsof(timeout: TimeInterval = 3) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // -n -P -l: no host/port/user lookups, so it returns in milliseconds;
        // +c0 prints full process names.
        task.arguments = ["-iTCP", "-sTCP:LISTEN", "-n", "-P", "-l", "+c0"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }

        // Read on a background queue and wait with a timeout: a wedged lsof
        // (exploding fd table) must not stall the refresh loop.
        let semaphore = DispatchSemaphore(value: 0)
        var output: String?
        DispatchQueue.global(qos: .userInitiated).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            output = String(data: data, encoding: .utf8)
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            _ = semaphore.wait(timeout: .now() + 0.5)
            return nil
        }
        task.waitUntilExit()
        return output
    }

    /// lsof row layout: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME.
    /// COMMAND may contain spaces (we pass +c0), so locate the columns by
    /// finding a numeric PID immediately followed by an FD like "12u".
    static func parse(_ line: String) -> PortEntry? {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard tokens.count >= 9 else { return nil }

        var pidIndex: Int? = nil
        for i in 0..<(tokens.count - 2) where tokens[i].allSatisfy(\.isNumber) {
            let fd = tokens[i + 2]
            if let last = fd.last, last.isLetter,
               fd.dropLast().allSatisfy(\.isNumber) {
                pidIndex = i
                break
            }
        }
        guard let p = pidIndex, tokens.count >= p + 8 else { return nil }

        let command = Self.unescape(tokens[0..<p].joined(separator: " "))
        guard let pid = pid_t(tokens[p]), pid > 0 else { return nil }
        guard tokens[p + 6] == "TCP" else { return nil }

        var name = tokens[(p + 7)...].joined(separator: " ")
        if let range = name.range(of: " (LISTEN)") { name = String(name[..<range.lowerBound]) }
        guard let colon = name.lastIndex(of: ":"),
              let port = Int(name[name.index(after: colon)...]), port > 0 else { return nil }
        let host = String(name[..<colon])

        let cwd = workingDirectory(for: pid)
        return PortEntry(
            port: port,
            pid: pid,
            processName: command,
            host: host,
            project: cwd.flatMap(projectName),
            projectPath: cwd
        )
    }

    /// Anything that is not loopback is reachable from outside this process.
    /// Treating it that way (rather than whitelisting `*` / `0.0.0.0`) means a
    /// listener bound to a specific interface address such as 192.168.1.5 is
    /// reported as exposed instead of being silently filed under "local".
    static func isExposed(host: String) -> Bool {
        let h = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if h.isEmpty || h == "*" || h == "::" { return true }
        if h == "localhost" || h == "::1" { return false }
        if h.hasPrefix("127.") { return false }
        return true
    }

    /// Read a process working directory via proc_pidinfo; far cheaper than
    /// spawning `lsof -p`.
    static func workingDirectory(for pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, $0, size)
        }
        guard result > 0 else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw -> String in
            var chars: [CChar] = []
            for byte in raw.bindMemory(to: CChar.self) {
                if byte == 0 { break }
                chars.append(byte)
            }
            chars.append(0)
            return String(cString: chars)
        }
        guard isProjectPath(path) else { return nil }
        return path
    }

    /// Only directories that look like projects are inferred as such; system
    /// daemons and paths like /tmp all fall into the system group.
    static func isProjectPath(_ path: String) -> Bool {
        // Resolve symlinks first: /tmp is really /private/tmp, /var is /private/var.
        let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let excludedPrefixes = [
            "/System", "/usr", "/private/var", "/private/tmp", "/var", "/tmp",
            "/Library", "/Applications", "/dev", "/opt", "/private/var/folders",
        ]
        if excludedPrefixes.contains(where: { canonical.hasPrefix($0) }) { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if canonical == home || canonical == "/" { return false }
        return true
    }

    /// lsof escapes spaces and other characters in command names: `\x20` for a
    /// space, `\xNN` for non-printables, `\\` for a literal backslash.
    /// An unrecognized `\X` sequence keeps both characters rather than dropping
    /// the escaped one.
    static func unescape(_ s: String) -> String {
        let chars = Array(s)
        var result = ""
        var i = 0
        while i < chars.count {
            guard chars[i] == "\\" else {
                result.append(chars[i])
                i += 1
                continue
            }
            guard i + 1 < chars.count else {
                // Trailing backslash: nothing to escape.
                result.append(chars[i])
                break
            }
            let next = chars[i + 1]
            if next == "x" {
                // Look ahead without consuming, so a non-hex character is not
                // swallowed when the escape turns out to be malformed.
                var hex = ""
                var j = i + 2
                while j < chars.count, hex.count < 2, chars[j].isHexDigit {
                    hex.append(chars[j])
                    j += 1
                }
                if hex.count == 2, let byte = UInt8(hex, radix: 16) {
                    result.append(Character(Unicode.Scalar(byte)))
                    i = j
                } else {
                    result.append("\\x" + hex)
                    i = j
                }
            } else if next == "\\" {
                result.append("\\")
                i += 2
            } else {
                // Not an escape we know: keep the backslash and the character.
                result.append(chars[i])
                result.append(next)
                i += 2
            }
        }
        return result
    }

    static func projectName(_ path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let base = URL(fileURLWithPath: path).lastPathComponent
        return base.isEmpty ? nil : base
    }
}
