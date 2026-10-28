#!/usr/bin/env python3
"""Exercise the shipping schedule-edit method with timer/notification boundary spies."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
registry = (root / 'Agent/Jobs/AgentJobRegistry.swift').read_text(encoding='utf-8')
runner = (root / 'Agent/Jobs/ScheduledJobRunner.swift').read_text(encoding='utf-8')
trigger = registry.split('enum AgentJobTrigger: Equatable {', 1)[1].split('/// Where the job', 1)[0]
method = registry.split('    func updateSchedule(', 1)[1].split('    /// Drop a job', 1)[0]
cron = runner.split('    nonisolated static func nextCronDate(', 1)[1].split('    /// "30m"', 1)[0]
source = '''import Foundation
enum AgentJobTrigger: Equatable {''' + trigger + '''
enum State { case pending, running, done }
final class Job {
 let id = "job"
 var trigger: AgentJobTrigger = .loop(interval: 60, count: 8)
 var state = State.pending
 var fireInFlight = false
 var firedCount = 2
 var skippedCount = 1
 var prompt: String? = "before"
 var task: Task<Void, Never>?
 var remaining: Int? = 5
 var nextFireAt: Date? = Date()
 var isEnabled = true
}
enum JobInsuranceNotification {
 static var cancellations = 0
 static func cancel(jobId: String) { cancellations += 1 }
}
enum ScheduledJobRunner {
 static let maxDurationSeconds: TimeInterval = 10 * 365 * 86400
 static var arms = 0
 static func arm(_ job: Job) { arms += 1 }
 nonisolated static func nextCronDate(''' + cron + '''
}
final class Registry {
 var jobs: [String: Job] = [:]
 var changes = 0
 func jobsDidChange() { changes += 1 }
 func updateSchedule(''' + method + '''
}
let registry = Registry()
let job = Job()
registry.jobs[job.id] = job
func edit(_ trigger: AgentJobTrigger, _ prompt: String? = "after") -> Bool {
 registry.updateSchedule(jobId: job.id, trigger: trigger, prompt: prompt)
}
precondition(!edit(.immediate))
precondition(!edit(.once(after: .infinity)))
precondition(!edit(.once(after: 1e20)))
precondition(!edit(.loop(interval: 59, count: nil)))
precondition(!edit(.loop(interval: 60, count: 3)))
precondition(!edit(.once(after: 60), "  "))
precondition(!edit(.cron(hour: 24, minute: 0, days: [], start: nil, end: nil)))
precondition(!edit(.cron(hour: 12, minute: 0, days: [8], start: nil, end: nil)))
precondition(!edit(.cron(hour: 12, minute: 0, days: [], start: nil, end: Date(timeIntervalSince1970: 0))))
precondition(!edit(.onCompletion(ofJobId: job.id)))
precondition(!edit(.onCompletion(ofJobId: "missing")))
precondition(registry.changes == 0 && ScheduledJobRunner.arms == 0 && JobInsuranceNotification.cancellations == 0)
precondition(job.prompt == "before" && job.remaining == 5)
job.fireInFlight = true
precondition(!edit(.once(after: 60)))
job.fireInFlight = false
job.state = .running
precondition(!edit(.once(after: 60)))
job.state = .done
precondition(!edit(.once(after: 60)))
job.state = .pending
precondition(edit(.loop(interval: 120, count: 10)))
precondition(registry.jobs[job.id] === job && job.remaining == 7)
precondition(job.firedCount == 2 && job.skippedCount == 1 && job.prompt == "after")
precondition(ScheduledJobRunner.arms == 1 && JobInsuranceNotification.cancellations == 1)
job.isEnabled = false
precondition(edit(.once(after: 300)))
precondition(job.remaining == nil && job.nextFireAt == nil && ScheduledJobRunner.arms == 1)
job.prompt = nil
precondition(edit(.cron(hour: 12, minute: 0, days: [], start: nil, end: nil), nil))
precondition(job.prompt == nil)
print("PASS: shipping schedule edit validation, identity, counters, paused state, rearming and notifications")
'''
with tempfile.TemporaryDirectory(prefix='minis-schedule-tests-') as temp:
    path = Path(temp) / 'main.swift'
    path.write_text(source, encoding='utf-8')
    subprocess.run(['swift', str(path)], check=True)
