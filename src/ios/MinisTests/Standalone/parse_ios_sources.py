"""Parse every shipping iOS Swift file, including code outside the feature screens."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
files = [p for p in root.rglob('*.swift') if 'MinisTests' not in p.parts]
def parse(path):
    return subprocess.run(['xcrun', 'swiftc', '-frontend', '-parse', '-enable-bare-slash-regex', str(path)],
                          text=True, capture_output=True, timeout=90)
with ThreadPoolExecutor(max_workers=4) as pool:
    failures = [result for result in pool.map(parse, files) if result.returncode]
for result in failures:
    print(result.stderr)
assert not failures, f'{len(failures)} Swift files failed parsing'
print(f'PASS: parsed {len(files)} shipping Swift sources')
