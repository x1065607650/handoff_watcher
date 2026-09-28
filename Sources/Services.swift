import Foundation
import Darwin

struct CommandResult: Sendable {
    var status: Int32
    var output: String
    var timedOut: Bool = false
}
protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], timeout: Double) async -> CommandResult
}
struct SystemRunner: CommandRunning {
    func run(_ executable: String, _ arguments: [String], timeout: Double = 2) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                // Keep command diagnostics stable; application language selection stays in Bundle.
                var environment = ProcessInfo.processInfo.environment
                environment["LC_ALL"] = "C"
                environment["LANG"] = "C"
                process.environment = environment
                process.standardOutput = pipe
                process.standardError = pipe
                do { try process.run() }
                catch {
                    continuation.resume(returning: CommandResult(status: -1, output: error.localizedDescription))
                    return
                }
                let watchdog = DispatchWorkItem {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
                let start = Date()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()
                continuation.resume(returning: CommandResult(
                    status: process.terminationStatus,
                    output: String(decoding: data, as: UTF8.self),
                    timedOut: Date().timeIntervalSince(start) >= timeout && process.terminationReason == .uncaughtSignal))
            }
        }
    }
}

struct HandoffWatcherService: Sendable {
    let name: String
    let label: String
    let onDemand: Bool
    static let all: [HandoffWatcherService] = [
        .init(name: "pboard", label: "com.apple.pboard", onDemand: true),
        .init(name: "sharingd", label: "com.apple.sharingd", onDemand: false),
        .init(name: "useractivityd", label: "com.apple.coreservices.useractivityd", onDemand: true)
    ]
}
enum ProblemReason: String, Sendable, CaseIterable {
    case checkTimeout = "error.check_timeout"
    case checkUnavailable = "error.check_unavailable"
    case permissionDenied = "error.permission_denied"
    case stopTimeout = "error.stop_timeout"
    case stopFailed = "error.stop_failed"
    case restartUnconfirmed = "error.restart_unconfirmed"
    case recoveryTimeout = "error.recovery_timeout"
    case cancelled = "error.cancelled"
    case abnormalExit = "error.abnormal_exit"
    case invalidState = "error.invalid_state"
}
struct ServiceProblem: Sendable, Equatable {
    let reason: ProblemReason
    var service: String? = nil
    var argument: String? = nil
    var diagnostic: String? = nil
    func localized(using localizer: Localizer = L10n.current) -> String {
        let message = argument.map { localizer.text(reason.rawValue, $0) } ?? localizer.text(reason.rawValue)
        return service.map { localizer.text("service_detail", $0, message) } ?? message
    }
}
enum ServiceStatus: Sendable, Equatable {
    case running, idle, failed(ServiceProblem)
    var healthy: Bool {
        switch self { case .running, .idle: return true; case .failed: return false }
    }
    var problem: ServiceProblem? {
        if case .failed(let problem) = self { return problem }
        return nil
    }
    func localized(using localizer: Localizer = L10n.current) -> String {
        switch self {
        case .running: return localizer.text("service.running")
        case .idle: return localizer.text("service.idle")
        case .failed(let problem): return problem.localized(using: localizer)
        }
    }
}
struct ServiceReport: Sendable {
    let service: HandoffWatcherService
    let status: ServiceStatus
    let pid: Int32?
    var healthy: Bool { status.healthy }
    var detail: String { status.localized() }
    static func parse(_ result: CommandResult, service: HandoffWatcherService) -> ServiceReport {
        func report(_ status: ServiceStatus, _ pid: Int32? = nil) -> ServiceReport {
            .init(service: service, status: status, pid: pid)
        }
        func failure(_ reason: ProblemReason, argument: String? = nil, diagnostic: String? = nil, pid: Int32? = nil) -> ServiceReport {
            report(.failed(ServiceProblem(reason: reason, argument: argument, diagnostic: diagnostic)), pid)
        }
        if result.timedOut { return failure(.checkTimeout, diagnostic: result.output) }
        if result.status != 0 { return failure(.checkUnavailable, diagnostic: result.output) }
        var fields: [String: String] = [:]
        for line in result.output.components(separatedBy: .newlines) {
            guard line.hasPrefix("\t"), !line.hasPrefix("\t\t") else { continue }
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " = ")
            if parts.count == 2 { fields[parts[0]] = parts[1] }
        }
        let pid = fields["pid"].flatMap(Int32.init)
        if fields["state"] == "running", let pid, pid > 0 { return report(.running, pid) }
        if service.onDemand, ["not running", "waiting"].contains(fields["state"] ?? "") {
            if let exit = fields["last exit code"], exit != "0" { return failure(.abnormalExit, argument: exit, diagnostic: result.output) }
            return report(.idle)
        }
        return failure(.invalidState, diagnostic: result.output, pid: pid)
    }
}
struct RestartFailure: Sendable {
    var summary: ProblemReason? = nil
    var problems: [ServiceProblem] = []
    func localized(using localizer: Localizer = L10n.current) -> String {
        ([summary.map { localizer.text($0.rawValue) }].compactMap { $0 } + problems.map { $0.localized(using: localizer) }).joined(separator: "\n")
    }
}
struct RestartOutcome: Sendable {
    let reports: [ServiceReport]
    let failure: RestartFailure?
    var error: String? { failure?.localized() }
    /// Existing JSON fields stay stable; raw command output is opt-in diagnostic data.
    func json(verbose: Bool = false) -> [String: Any] {
        var result: [String: Any] = ["services": reports.map {
            ["name": $0.service.name, "healthy": $0.healthy, "detail": $0.detail, "pid": $0.pid as Any? ?? NSNull()]
        }, "error": error as Any? ?? NSNull()]
        if verbose {
            var problems = reports.compactMap { report -> ServiceProblem? in
                guard var problem = report.status.problem else { return nil }
                problem.service = report.service.name
                return problem
            }
            problems += failure?.problems ?? []
            result["diagnostics"] = problems.map {
                ["service": $0.service as Any? ?? NSNull(), "reason": $0.reason.rawValue,
                 "output": $0.diagnostic as Any? ?? NSNull()] as [String: Any]
            }
        }
        return result
    }
}
struct ServiceEngine: Sendable {
    var runner: any CommandRunning = SystemRunner()
    var uid: uid_t = getuid()
    var user: String = NSUserName()
    var retryCount = 15
    var retryDelay: UInt64 = 1_000_000_000
    func target(_ service: HandoffWatcherService) -> String { "gui/\(uid)/\(service.label)" }
    func check(_ service: HandoffWatcherService, timeout: Double = 2) async -> ServiceReport {
        let result = await runner.run("/bin/launchctl", ["print", target(service)], timeout: timeout)
        return ServiceReport.parse(result, service: service)
    }
    func checkAll(timeout: Double = 2) async -> [ServiceReport] {
        await withTaskGroup(of: (Int, ServiceReport).self) { group in
            for (index, service) in HandoffWatcherService.all.enumerated() {
                group.addTask { (index, await check(service, timeout: timeout)) }
            }
            var reports: [(Int, ServiceReport)] = []
            for await result in group { reports.append(result) }
            return reports.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
    func restart() async -> RestartOutcome {
        let before = await checkAll()
        var failures: [ServiceProblem] = []
        for service in HandoffWatcherService.all {
            if Task.isCancelled { return RestartOutcome(reports: before, failure: .init(summary: .cancelled)) }
            let result = await runner.run("/usr/bin/killall", ["-u", user, "-TERM", service.name], timeout: 2)
            if result.timedOut || (result.status != 0 && !result.output.contains("No matching processes")) {
                let denied = result.output.localizedCaseInsensitiveContains("Operation not permitted") || result.output.localizedCaseInsensitiveContains("Permission denied")
                let reason: ProblemReason = result.timedOut ? .stopTimeout : (denied ? .permissionDenied : .stopFailed)
                failures.append(.init(reason: reason, service: service.name, diagnostic: result.output))
            }
        }
        if !failures.isEmpty { return RestartOutcome(reports: await checkAll(), failure: .init(problems: failures)) }
        let deadline = Date().addingTimeInterval(15)
        var latest = before
        var requested: Set<String> = []
        for _ in 0..<retryCount {
            if Task.isCancelled { return RestartOutcome(reports: latest, failure: .init(summary: .cancelled)) }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            try? await Task.sleep(nanoseconds: min(retryDelay, UInt64(remaining * 1_000_000_000)))
            guard deadline.timeIntervalSinceNow > 0 else { break }
            latest = await checkAll(timeout: min(2, deadline.timeIntervalSinceNow))
            let restored = latest.allSatisfy { report in
                guard report.healthy else { return false }
                let oldPID = before.first { $0.service.name == report.service.name }?.pid
                return report.pid == nil || oldPID == nil || report.pid != oldPID
            }
            if restored { return RestartOutcome(reports: latest, failure: nil) }
            if Date() >= deadline { break }
            for report in latest where report.pid == nil && !requested.contains(report.service.name) {
                guard deadline.timeIntervalSinceNow > 0 else { break }
                requested.insert(report.service.name)
                _ = await runner.run("/bin/launchctl", ["kickstart", target(report.service)], timeout: min(2, deadline.timeIntervalSinceNow))
            }
        }
        let unresolved = latest.filter { report in
            !report.healthy || (report.pid != nil && report.pid == before.first { $0.service.name == report.service.name }?.pid)
        }.map { report -> ServiceProblem in
            var problem = report.status.problem ?? ServiceProblem(reason: .restartUnconfirmed)
            problem.service = report.service.name
            return problem
        }
        return RestartOutcome(reports: latest, failure: .init(summary: .recoveryTimeout, problems: unresolved))
    }
}
