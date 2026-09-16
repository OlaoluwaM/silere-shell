"""Check local internal-type references without counting comments or strings."""

import re
import sys
from pathlib import Path


# Probes and comments name internal types as text without importing them. Mask
# those tokens before checking the same module boundary as the upstream lint.
TEXT = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|`(?:\\.|[^`\\])*`')


def code_only(source):
    return TEXT.sub(lambda match: re.sub(r'[^\n]', ' ', match.group()), source)


def check(root):
    # Probe runners copy components into their owning module or export them in
    # a disposable qmldir. Their source-tree location is not the runtime module.
    files = sorted(path for path in root.rglob('*.qml')
                   if '.git' not in path.parts
                   and path.relative_to(root).parts[0] != 'scripts')
    sources = {path: code_only(path.read_text()) for path in files}
    failures = []
    for module in sorted(root.rglob('qmldir')):
        if '.git' in module.parts:
            continue
        for row in module.read_text().splitlines():
            fields = row.split()
            if len(fields) < 3 or fields[0] != 'internal':
                continue
            name = fields[1]
            pattern = re.compile(r'\b' + re.escape(name) + r'\b')
            for path, source in sources.items():
                if path.parent == module.parent:
                    continue
                match = pattern.search(source)
                if match:
                    line = source.count('\n', 0, match.start()) + 1
                    failures.append(f'{path.relative_to(root)}:{line}: {name} is internal to {module.parent.relative_to(root)}')
    return failures


if __name__ == '__main__':
    findings = check(Path(sys.argv[1] if len(sys.argv) > 1 else '.'))
    for finding in findings:
        print(finding)
    sys.exit(bool(findings))
