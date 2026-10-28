from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='minis-memory-runtime-') as temp:
    temp = Path(temp)
    sources = []
    for name in ['BotWorkspaceStore', 'BotMemoryStore']:
        source = (root / 'Views/ContentView/Bots' / (name + '.swift')).read_text(encoding='utf-8')
        source = source.replace('static let shared = ' + name + '()',
            'static let shared = ' + name + '(fileURL: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("' + name + '"))')
        out = temp / (name + '.swift')
        out.write_text(source, encoding='utf-8')
        sources.append(str(out))
    binary = temp / 'tests'
    subprocess.run(['swiftc', *sources, str(root / 'Views/ContentView/Bots/AIChatViewModel+BotMemory.swift'),
                    str(Path(__file__).with_name('BotMemoryRuntimeTests.swift')), '-lsqlite3', '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(temp)], check=True, timeout=30)
