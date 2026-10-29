"""Exercise shipping completion waiting and updateSchedule with real notifications/tasks.
Only execution/registry side effects are spies. Requires macOS Swift Foundation.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
registry = (root / 'Agent/Jobs/AgentJobRegistry.swift').read_text(encoding='utf-8')
runner = (root / 'Agent/Jobs/ScheduledJobRunner.swift').read_text(encoding='utf-8')
trigger = registry.split('enum AgentJobTrigger: Equatable {', 1)[1].split('/// Where the job', 1)[0]
edit = registry.split('    func updateSchedule(', 1)[1].split('    /// Drop a job', 1)[0]
calendar = runner.split('    nonisolated static func nextCalendarFire(', 1)[1].split('    /// "30m"', 1)[0]
wait = runner.split('        case .onCompletion(let ofJobId):', 1)[1].split('\n        }\n        logger.info', 1)[0]
wait = wait.replace('let seq = NotificationCenter.default.notifications(named: .agentJobDidFinish)',
                    'let seq = NotificationCenter.default.notifications(named: .agentJobDidFinish)\n                ready += 1')
source = '''import Foundation
extension Notification.Name { static let agentJobDidFinish = Notification.Name("test-finish") }
enum AgentJobTrigger: Equatable {''' + trigger + '''
enum State { case pending, running, done }
@MainActor final class Job {
 let id: String
 init(_ id: String) { self.id = id }
 var trigger: AgentJobTrigger = .onCompletion(ofJobId: "upstream")
 var prompt: String? = "before"
 var state = State.pending
 var fireInFlight = false
 var firedCount = 0
 var skippedCount = 0
 var remaining: Int?
 var task: Task<Void, Never>?
 var nextFireAt: Date?
 var isEnabled = true
}
enum JobInsuranceNotification { static func cancel(jobId: String) {} }
@MainActor final class AgentJobRegistry {
 static let shared = AgentJobRegistry()
 var jobs: [String: Job] = [:]
 var finishes = 0
 func jobsDidChange() {}
 func finish(_ id: String, state: State, result: String?, keepIfChildRunning: Bool) {
  finishes += 1; jobs[id]?.state = state
 }
 func updateSchedule(''' + edit + '''
}
@MainActor enum ScheduledJobRunner {
 static var ready = 0
 static var prompts: [String] = []
 static let maxDurationSeconds: TimeInterval = 10 * 365 * 86400
 static func fire(_ job: Job, upstreamJobId: String) async { prompts.append(job.prompt!); job.firedCount += 1 }
 nonisolated static func nextCalendarFire(''' + calendar + '''
 static func arm(_ job: Job) {
  job.task?.cancel()
  guard case .onCompletion(let ofJobId) = job.trigger else { fatalError("Unexpected test trigger") }
''' + wait + '''
 }
}
@main struct CompletionTests {
 @MainActor static func waitFor(_ condition: () -> Bool) async {
  let deadline = Date().addingTimeInterval(5)
  while !condition() && Date() < deadline { await Task.yield() }
  precondition(condition(), "Timed out")
 }
 @MainActor static func main() async {
  let registry = AgentJobRegistry.shared
  let job = Job("downstream")
  registry.jobs = [job.id: job, "upstream": Job("upstream")]
  ScheduledJobRunner.arm(job)
  await waitFor { ScheduledJobRunner.ready == 1 }
  let old = job.task!
  precondition(registry.updateSchedule(jobId: job.id, trigger: job.trigger, prompt: "after"))
  await old.value
  await waitFor { ScheduledJobRunner.ready == 2 }
  precondition(job.state == .pending && job.firedCount == 0 && registry.finishes == 0)
  NotificationCenter.default.post(name: .agentJobDidFinish, object: "unrelated")
  for _ in 0..<50 { await Task.yield() }
  precondition(job.firedCount == 0)
  NotificationCenter.default.post(name: .agentJobDidFinish, object: "upstream")
  await waitFor { job.state == .done }
  NotificationCenter.default.post(name: .agentJobDidFinish, object: "upstream")
  await job.task?.value
  precondition(ScheduledJobRunner.prompts == ["after"] && registry.finishes == 1)
  let cancelled = Job("cancelled")
  registry.jobs[cancelled.id] = cancelled
  ScheduledJobRunner.arm(cancelled)
  await waitFor { ScheduledJobRunner.ready == 3 }
  cancelled.task?.cancel()
  await cancelled.task?.value
  precondition(cancelled.state == .pending && cancelled.firedCount == 0 && registry.finishes == 1)
  print("PASS: real completion wait cancellation, editing, unrelated events and single execution with new prompt")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='minis-completion-tests-') as temp:
    path = Path(temp) / 'tests.swift'
    path.write_text(source, encoding='utf-8')
    binary = Path(temp) / 'tests'
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
