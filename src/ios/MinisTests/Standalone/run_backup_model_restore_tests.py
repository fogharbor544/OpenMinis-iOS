"""Compile the shipping backup model merge and ModelEntry identity with API fixtures."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
merger = (root / 'Agent/Sync/ProviderBackupMerger.swift').read_text(encoding='utf-8')
merge = merger.split('        let localEntriesSnapshot = local.modelEntries', 1)[1].split('        // Per-instance before/after diff', 1)[0]
fixtures = Path(__file__).with_name('ModelEntryIdentityTests.swift').read_text(encoding='utf-8').split('@main struct')[0]
source = fixtures + '''
struct Config { var modelEntries: [ModelEntry] = [] }
func restore(_ entries: [ModelEntry], into local: inout Config,
             tombstonedEntryIds: Set<String> = [], tombstonedInstanceIds: Set<String> = []) {
 let remote = Config(modelEntries: entries)
''' + merge + '''
}
@main struct BackupModelTests {
 static func main() throws {
  let api = ModelEntry(providerInstanceId: "provider", model: LLMModel(id: "api", displayName: "API", provider: "test"))
  var custom = ModelEntry(providerInstanceId: "provider", model: LLMModel(id: "custom", displayName: "Custom", provider: "test"))
  custom.isCustom = true
  // Serialized backup with group member references, restored on an empty device.
  let entries = try JSONDecoder().decode([ModelEntry].self, from: JSONEncoder().encode([api, custom]))
  let groupMembers = [api.id, custom.id]
  var local = Config()
  restore(entries, into: &local)
  precondition(local.modelEntries.count == 2)
  precondition(groupMembers.allSatisfy { id in local.modelEntries.contains { $0.id == id } })
  precondition(local.modelEntries[0].isCustom == false)
  restore(entries, into: &local)
  precondition(local.modelEntries.count == 2)
  // Keep existing API metadata and a newer local override on conflicts.
  local.modelEntries[0] = ModelEntry(providerInstanceId: "provider", model: LLMModel(id: "api", displayName: "Local API metadata", provider: "test"))
  local.modelEntries[0].overrides.displayName = "New local name"
  local.modelEntries[0].userModifiedAt = Date(timeIntervalSince1970: 20)
  var old = api
  old.overrides.displayName = "Old backup name"
  old.userModifiedAt = Date(timeIntervalSince1970: 10)
  restore([old], into: &local)
  precondition(local.modelEntries[0].overrides.displayName == "New local name")
  old.userModifiedAt = Date(timeIntervalSince1970: 30)
  restore([old], into: &local)
  precondition(local.modelEntries[0].overrides.displayName == "Old backup name")
  precondition(local.modelEntries[0].baseModel.displayName == "Local API metadata")
  var excluded = Config()
  restore(entries, into: &excluded, tombstonedEntryIds: [api.id])
  precondition(excluded.modelEntries.map(\\.id) == [custom.id])
  print("PASS: missing API/custom models restored, group IDs resolve, repeated restore and overlay conflict rules")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='minis-backup-models-') as temp:
    path = Path(temp) / 'tests.swift'
    path.write_text(source, encoding='utf-8')
    binary = Path(temp) / 'tests'
    subprocess.run(['swiftc', str(root / 'Providers/ModelEntry.swift'), str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
