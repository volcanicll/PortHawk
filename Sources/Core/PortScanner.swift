import Foundation
import Darwin

/// 一条监听记录：哪个进程（pid）在哪个端口监听、来自哪个项目。
struct PortEntry: Identifiable, Equatable {
    let port: Int
    let pid: pid_t
    let processName: String
    /// true = 监听 0.0.0.0 / * / [::]，局域网可达；false = 仅 127.0.0.1 / ::1
    let isLanExposed: Bool
    /// 由进程工作目录推断的项目名（目录 basename），系统进程为 nil
    let project: String?
    let projectPath: String?

    var id: String { "\(port)-\(pid)" }
    var scopeText: String { isLanExposed ? "对外" : "本机" }
}

enum PortScanner {
    /// 执行 lsof 扫描全部 TCP LISTEN，并附上每个进程的工作目录。
    /// 返回 nil 表示扫描失败（启动失败/超时），调用方应保留上一轮数据；
    /// 空数组才是「扫描成功、确实没有监听端口」。
    static func scan() -> [PortEntry]? {
        guard let output = runLsof() else { return nil }
        var seen = Set<String>()
        var entries: [PortEntry] = []
        for line in output.split(separator: "\n").dropFirst() {
            guard let entry = parse(String(line)) else { continue }
            // IPv4/IPv6 双栈会让同一 (port, pid) 出现两次，只保留一条
            guard seen.insert(entry.id).inserted else { continue }
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

    // MARK: - 明细页数据（借鉴 Pulse 的 inspector 钻取模式）

    struct ProcessDetail {
        let commandLine: [String]?
        let userName: String?
        let parentPID: pid_t?
        let residentBytes: UInt64?
        let threadCount: Int32?
        /// 进程自启动以来累计的 CPU 时间（秒）
        let cpuSeconds: Double?
        /// 可执行文件路径（argv[0]，跨用户进程可能拿不到）
        let executablePath: String?
    }

    /// 一次性取齐明细页需要的数据；任一项拿不到就置 nil（跨用户进程常见）。
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

    /// 当前瞬时 CPU 时间采样（秒），配合上次采样差值算 CPU%
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

    /// 完整命令行：sysctl KERN_PROCARGS2 → [argc][exec_path][填充 NUL][argv…][env…]
    static func commandLine(for pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<UInt32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        let argc = buffer.withUnsafeBytes { $0.load(as: UInt32.self) }
        guard argc > 0, argc < 4096 else { return nil }

        // 布局：argc 后是 NUL 结尾的 exec_path、若干对齐 NUL、然后是完整 argv 字符串序列
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
        // -n -P -l：不做主机名/端口名/用户名反查，保证毫秒级返回；+c0 输出完整进程名
        task.arguments = ["-iTCP", "-sTCP:LISTEN", "-n", "-P", "-l", "+c0"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }

        // 后台读输出，信号量限时等待：lsof 卡死（fd 爆炸）时不能拖停刷新
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

    /// lsof 行格式：COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME。
    /// COMMAND 可能含空格（+c0），所以按「纯数字 PID + 字母结尾 FD」定位列起点。
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
        let exposed = host == "*" || host == "0.0.0.0" || host == "[::]" || host == "::"

        let cwd = workingDirectory(for: pid)
        return PortEntry(
            port: port,
            pid: pid,
            processName: command,
            isLanExposed: exposed,
            project: cwd.flatMap(projectName),
            projectPath: cwd
        )
    }

    /// 用 proc_pidinfo 读进程工作目录，比派生子进程（lsof -p）快得多。
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

    /// 只有「像项目目录」的工作目录才推断为项目；系统守护进程、/tmp 等一律归入系统组。
    static func isProjectPath(_ path: String) -> Bool {
        // 先解软链接：/tmp 实际是 /private/tmp，/var 实际是 /private/var
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

    /// lsof 会把命令名中的空格等字符转义成 \x20，这里还原。
    static func unescape(_ s: String) -> String {
        var result = ""
        var iterator = s.makeIterator()
        while let ch = iterator.next() {
            if ch == "\\", let x = iterator.next(), x == "x" {
                var hex = ""
                for _ in 0..<2 {
                    if let h = iterator.next() { hex.append(h) }
                }
                if let byte = UInt8(hex, radix: 16) {
                    result.append(Character(Unicode.Scalar(byte)))
                    continue
                }
                result.append("\\x" + hex)
            } else {
                result.append(ch)
            }
        }
        return result
    }

    static func projectName(_ path: String) -> String? {
        let base = URL(fileURLWithPath: path).lastPathComponent
        return base.isEmpty ? nil : base
    }
}
