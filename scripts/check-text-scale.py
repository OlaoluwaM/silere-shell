"""Flag visible text inside an item that carries a static `scale:` binding.

It reads `scale:` property lines and the text declared beneath them, and only
those. Two shipped forms scale text another way and are deliberately left out:
a `Scale {}` transform (xScale/yScale) on an item holding text, and an animated
`scale` on a text item (NumberAnimation { target: label; property: "scale" }).
Both are transient bumps that settle back at 1.0 within a fraction of a second,
so the resampling they cause never rests on a label.
"""
import glob, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# a tripwire, not a budget: modules/ holds about 150 files, so fewer means the
# glob missed the tree and the scan would pass on nothing
MIN_FILES = 100

files = sorted(os.path.relpath(f, ROOT)
               for f in glob.glob(os.path.join(ROOT, 'modules/**/*.qml'), recursive=True))
if len(files) < MIN_FILES:
    print(f"  scanned {len(files)} QML files under {ROOT}/modules, expected at least {MIN_FILES}")
    sys.exit(1)
bad = []
for f in files:
    lines = open(os.path.join(ROOT, f)).read().split('\n')
    for i, l in enumerate(lines):
        m = re.match(r"^(\s*)scale:\s*(.+)$", l)
        if not m:
            continue
        indent = len(m.group(1))
        sub = []
        for nxt in lines[i + 1:]:
            if nxt.strip() and (len(nxt) - len(nxt.lstrip())) <= indent - 4:
                break
            sub.append(nxt)
        if not any(re.search(r"\b(ShellText|RollingText|Text\s*\{)", s) for s in sub):
            continue
        # a state that is transparent or hidden at that scale can never look soft
        ctx = '\n'.join(lines[max(0, i - 10):i + 3])
        hidden = re.search(r"(opacity|visible):[^\n]*(\?|&&)", ctx) and re.search(r"0\.0|false", ctx)
        if not hidden:
            bad.append(f"{f}:{i + 1}: {m.group(2).strip()[:48]}")
for b in bad:
    print("  " + b)
if not bad:
    print(f"{len(files)} QML files")
sys.exit(1 if bad else 0)
