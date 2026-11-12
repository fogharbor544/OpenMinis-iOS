"""Check that a `.minisbak` Skill restore preserves the full SKILL.md.

This is a portable source/format contract. It models the current export record
and the two write sites in the restore path; it does not boot the iOS app or
execute SwiftUI. The backing `skills/<id>/SKILL.md` blob is the source of truth
and must not be replaced by the record's frontmatter-free `body`.
"""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
EXPORTER = ROOT / "Agent/Backup/BackupExporter.swift"
IMPORTER = ROOT / "Agent/Backup/BackupImporter+Categories.swift"
STORE = ROOT / "Agent/Session/SkillStore.swift"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main() -> None:
    exporter = read(EXPORTER)
    importer = read(IMPORTER)
    store = read(STORE)

    assert "body = s.body" in exporter, "skill records keep the parsed body for older readers"
    assert "let content: String" in exporter, "new backups also carry the full SKILL.md"
    assert "SkillStore.readSkillContent(" in exporter
    assert 'writer.write(BackupRecordEnvelope(t: "SkillV2", d: row))' in exporter
    assert 'logicalPrefix: "skills/\\(row.id)"' in exporter
    assert "result.body = bodyLines.joined(separator:" in store

    # The file tree has the exact bytes, including frontmatter. Restoring it
    # after the metadata row is what makes the detail view and /var/minis view
    # show a working skill instead of a bare heading or placeholder name.
    skills_import = importer.split("private func importSkills(", 1)[1].split("// MARK: - Providers", 1)[0]
    assert skills_import.index("restoreFileTree(") > skills_import.index('readJSONL(dataDir, base: "skills"')
    assert 'parts[0] == "skills"' in importer
    assert "rescanRestoredSkill" in skills_import, "restore must apply the restored SKILL.md after writing the file tree"
    assert "let restoredContent = try? String(contentsOf: skillFile" in skills_import
    assert "rec.content ?? rec.body" in skills_import
    assert "SkillStore.shared.rescanRestoredSkill(" in skills_import
    assert "content: rec.body," not in skills_import, "the parsed body is not a full SKILL.md"
    assert "content: fullContent" in skills_import
    assert skills_import.index("restoreFileTree(") < skills_import.index("rescanRestoredSkill")
    assert "fallbackDescription: rec.description" in skills_import
    assert "fallbackVersion: rec.version" in skills_import

    # A successful restore reloads SkillStore from the DB and the restored file.
    assert "SkillStore.shared.reload()" in importer
    assert "func readSkillFile(" in store
    assert "rootfsSkillsDir.appendingPathComponent(skillId)" in store
    assert "func rescanRestoredSkill(" in store
    assert "respectLocalNewer: false" in store
    assert "if respectLocalNewer," in store
    assert "parsed.description = fallbackDescription" in store
    assert "parsed.version = fallbackVersion" in store
    assert "syncToRootfs(skill: skill, content: content)" in store

    frontmatter = "---\nname: demo\ndescription: Trigger demo\nversion: 1.2.3\n---\n# Demo\n\nUse this skill.\n"
    parse_fence = frontmatter.split("---\n", 2)
    exported_body = parse_fence[2].strip("\n")
    assert exported_body == "# Demo\n\nUse this skill."
    assert "name: demo" not in exported_body and "description: Trigger demo" not in exported_body

    record = {
        "id": "demo",
        "name": "demo",
        "description": "Trigger demo",
        "version": "1.2.3",
        "body": exported_body,
        "content": frontmatter,
    }
    file_tree = {"skills/demo/SKILL.md": frontmatter}
    # The record registers the row and the file tree supplies exact bytes. The
    # final reconciliation parses those bytes and publishes the same content to
    # the Library, rootfs and in-memory skill.
    restored = {record["id"]: file_tree["skills/demo/SKILL.md"]}
    assert restored[record["id"]] == record["content"]
    assert restored[record["id"]] == frontmatter
    assert "name: demo" in restored[record["id"]]
    assert "# Demo" in restored[record["id"]]
    assert "Use this skill." in restored[record["id"]]

    print("PASS: skill backup record, full SKILL.md file tree, restore order and store reload")


if __name__ == "__main__":
    main()
