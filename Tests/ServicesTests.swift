import Foundation

actor FakeRunner: CommandRunning {
    enum Scenario { case healthy, missing, permission, unchanged, idle }
    let scenario: Scenario
    var killed: Set<String> = []
    var calls: [[String]] = []
    init(_ scenario: Scenario) { self.scenario = scenario }
    func run(_ executable: String, _ arguments: [String], timeout: Double) async -> CommandResult {
        calls.append([executable] + arguments)
        if executable == "/usr/bin/killall" {
            if scenario == .permission { return .init(status: 1, output: "Operation not permitted") }
            killed.insert(arguments.last!)
            if scenario == .idle { return .init(status: 1, output: "No matching processes belonging to you were found") }
            return .init(status: 0, output: "")
        }
        if arguments.first == "kickstart" { return .init(status: 0, output: "") }
        if scenario == .missing { return .init(status: 113, output: "Could not find service") }
        let name = arguments.last!.components(separatedBy: ".").last!
        if scenario == .idle && name != "sharingd" { return .init(status: 0, output: "service = {\n\tstate = not running\n\tlast exit code = 0\n}") }
        let pid = killed.contains(name) && scenario != .unchanged ? 222 : 111
        return .init(status: 0, output: "service = {\n\tstate = running\n\tpid = \(pid)\n}")
    }
}
@main struct Tests {
    static func main() async {
        if CommandLine.arguments.contains("--probe") {
            let result: [String: Any] = ["healthy": L10n.text("state.healthy"), "running": ServiceStatus.running.localized(), "error": ServiceProblem(reason: .checkTimeout).localized(), "preferred": Bundle.main.preferredLocalizations, "time": L10n.time(Date(timeIntervalSince1970: 0))]
            let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return
        }
        var count = 0
        func expect(_ condition: Bool, _ name: String) {
            guard condition else { fatalError("FAIL: \(name)") }
            count += 1; print("PASS: \(name)")
        }
        let demand = HandoffWatcherService.all[0], persistent = HandoffWatcherService.all[1]
        func parse(_ text: String, _ service: HandoffWatcherService = HandoffWatcherService.all[0]) -> ServiceReport {
            ServiceReport.parse(.init(status: 0, output: text), service: service)
        }
        expect(parse("x = {\n\tstate = running\n\tpid = 123\n\tendpoints = {\n\t\tstate = waiting\n\t}\n}").pid == 123, "Parse only root-level state and PID")
        expect(parse("\tstate = not running\n\tlast exit code = 0", demand).healthy, "Demand service may be idle")
        expect(!parse("\tstate = not running\n\tlast exit code = 0", persistent).healthy, "Keep-alive service must be running")
        expect(!parse("\tstate = not running\n\tlast exit code = 9").healthy, "Abnormal idle exit is unhealthy")
        expect(!parse("\tstate = running").healthy, "Running service needs a valid PID")
        expect(!parse("unrecognized").healthy, "Unknown format fails closed")
        expect(!ServiceReport.parse(.init(status: 1, output: "missing"), service: demand).healthy, "Missing service fails")
        expect(ServiceReport.parse(.init(status: 0, output: "", timedOut: true), service: demand).status.problem?.reason == .checkTimeout, "Timeout is distinguished")
        for scenario in [FakeRunner.Scenario.healthy, .missing, .permission, .unchanged, .idle] {
            let fake = FakeRunner(scenario)
            let engine = ServiceEngine(runner: fake, uid: 501, user: "test-user", retryCount: 2, retryDelay: 1)
            let result = await engine.restart()
            let shouldPass = scenario == .healthy || scenario == .idle
            expect((result.failure == nil) == shouldPass, "Restart \(scenario)")
            if scenario == .permission {
                expect(result.failure?.problems.allSatisfy { $0.reason == .permissionDenied } == true, "Permission failure is structured")
            }
            if scenario == .unchanged {
                expect(result.failure?.summary == .recoveryTimeout && result.failure?.problems.allSatisfy { $0.reason == .restartUnconfirmed } == true, "Unchanged PIDs produce structured recovery failure")
            }
            let calls = await fake.calls
            let kills = calls.filter { $0.first == "/usr/bin/killall" }
            expect(kills.count == 3 && kills.allSatisfy { $0[1...3] == ["-u", "test-user", "-TERM"] }, "Restart restricted to selected user (\(scenario))")
            expect(!calls.contains { $0.contains("sudo") }, "No elevation (\(scenario))")
        }
        let start = Date()
        let timeout = await SystemRunner().run("/bin/sleep", ["5"], timeout: 0.1)
        expect(timeout.timedOut && Date().timeIntervalSince(start) < 2, "Real subprocess timeout terminates promptly")
        let nonexistent = await SystemRunner().run("/nonexistent/handoff-watcher-test", [], timeout: 0.1)
        expect(nonexistent.status == -1, "Launch error is reported")
        let resourceRoot = Bundle.main.resourceURL!
        func table(_ language: String) -> [String: String] {
            let data = try! Data(contentsOf: resourceRoot.appendingPathComponent(language + ".lproj/Localizable.strings"))
            return try! PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
        }
        let enTable = table("en"), zhTable = table("zh-Hans")
        expect(Set(enTable.keys) == Set(zhTable.keys), "Languages have identical keys")
        let placeholders = try! NSRegularExpression(pattern: "%[@dfsu]")
        for key in enTable.keys.sorted() {
            func tokens(_ value: String) -> [String] {
                placeholders.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { String(value[Range($0.range, in: value)!]) }
            }
            expect(!enTable[key]!.isEmpty && !zhTable[key]!.isEmpty && tokens(enTable[key]!) == tokens(zhTable[key]!), "Nonempty translations and matching placeholders: \(key)")
        }
        let english = Localizer(bundle: Bundle(url: resourceRoot.appendingPathComponent("en.lproj"))!)
        let chinese = Localizer(bundle: Bundle(url: resourceRoot.appendingPathComponent("zh-Hans.lproj"))!)
        expect(ServiceStatus.running.localized(using: english) == "Running", "English service label")
        expect(ServiceStatus.idle.localized(using: chinese) == "待命", "Chinese idle label")
        expect(english.text("last_checked", "12:34:56") == "Last checked: 12:34:56", "English time placeholder")
        expect(chinese.text("last_checked", "12:34:56") == "上次检查：12:34:56", "Chinese time placeholder")
        for reason in ProblemReason.allCases {
            let problem = ServiceProblem(reason: reason, service: "sharingd", argument: reason == .abnormalExit ? "9" : nil, diagnostic: "RAW_SYSTEM_DIAGNOSTIC")
            for localizer in [english, chinese] {
                let text = problem.localized(using: localizer)
                expect(!text.contains("error.") && !text.contains("%@") && !text.contains("RAW_SYSTEM_DIAGNOSTIC"), "Translated summary without raw diagnostics: \(reason)")
            }
        }
        let bad = ServiceReport.parse(.init(status: 1, output: "RAW_SYSTEM_DIAGNOSTIC"), service: demand)
        let outcome = RestartOutcome(reports: [bad], failure: nil)
        expect(bad.status.problem?.diagnostic == "RAW_SYSTEM_DIAGNOSTIC", "Original diagnostics retained")
        expect(Set(outcome.json().keys) == ["services", "error"], "Default JSON schema unchanged")
        let serviceJSON = (outcome.json()["services"] as! [[String: Any]])[0]
        expect(Set(serviceJSON.keys) == ["name", "healthy", "detail", "pid"] && serviceJSON["healthy"] as? Bool == false && serviceJSON["pid"] is NSNull, "Service JSON types and fields unchanged")
        let diagnostics = outcome.json(verbose: true)["diagnostics"] as! [[String: Any]]
        expect(diagnostics[0]["output"] as? String == "RAW_SYSTEM_DIAGNOSTIC", "Raw diagnostics available only when requested")
        print("\(count) tests passed")
    }
}
