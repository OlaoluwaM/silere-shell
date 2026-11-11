"""Check that relative Markdown links reach a file, and their #anchors a heading.

Every tracked *.md file is read. Links to a scheme (https:, mailto:, ...) and a
bare "#" are left alone; a path is resolved from the linking file, or from the
repository root when it starts with "/". An anchor into a Markdown file must
match one of its heading slugs under GitHub's rule, or an explicit id or name.
"""

import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent

# a tripwire, not a budget: the tree tracks about thirty, so fewer means the
# listing broke and every link would pass unread
MIN_FILES = 20

FENCE = re.compile(r'^\s*(```|~~~)')
HEADING = re.compile(r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$')
CODE_SPAN = re.compile(r'(`+)(?:(?!\1).)+?\1')
INLINE_LINK = re.compile(r'!?\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*(<[^>]*>|[^)\s]+)(?:\s+(?:"[^"]*"|\'[^\']*\'|\([^)]*\)))?\s*\)')
LINK_TEXT = re.compile(r'!?\[([^\]]*)\]\([^)]*\)')
HTML_ID = re.compile(r'<[^>]*\s(?:id|name)\s*=\s*["\']([^"\']+)["\']', re.I)
HTML_TAG = re.compile(r'<[^>]+>')
SCHEME = re.compile(r'^[A-Za-z][A-Za-z0-9+.-]*:')


def code_lines(text):
    """Yield (line number, line) outside fenced code blocks."""
    fence = None
    for number, line in enumerate(text.split('\n'), 1):
        opened = FENCE.match(line)
        if fence:
            if opened and line.strip().startswith(fence):
                fence = None
            continue
        if opened:
            fence = opened.group(1)
            continue
        yield number, line


def slug(heading):
    """GitHub's anchor for a heading: the rendered text, lowercased, with
    everything but letters, digits, spaces, hyphens and underscores dropped and
    each space turned into a hyphen."""
    text = LINK_TEXT.sub(r'\1', heading)
    text = HTML_TAG.sub('', text)
    text = re.sub(r'`', '', text).lower()
    text = ''.join(c for c in text if c.isalnum() or c in ' -_')
    return text.replace(' ', '-')


def anchors(path, cache={}):
    if path not in cache:
        found, seen = set(), {}
        text = path.read_text(encoding='utf-8')
        for _, line in code_lines(text):
            found.update(HTML_ID.findall(line))
            heading = HEADING.match(line)
            if not heading:
                continue
            base = slug(heading.group(2))
            count = seen.get(base, 0)
            seen[base] = count + 1
            found.add(base if count == 0 else f'{base}-{count}')
        cache[path] = found
    return cache[path]


def check(files):
    broken = []
    for name in files:
        source = ROOT / name
        for number, line in code_lines(source.read_text(encoding='utf-8')):
            for link in INLINE_LINK.finditer(CODE_SPAN.sub('', line)):
                target = link.group(1).strip('<>')
                if target == '#' or SCHEME.match(target):
                    continue
                path, _, anchor = target.partition('#')
                path = unquote(path)
                if not path:
                    resolved = source
                elif path.startswith('/'):
                    resolved = ROOT / path.lstrip('/')
                else:
                    resolved = source.parent / path
                if not resolved.exists():
                    broken.append(f'{name}:{number}: {target}')
                elif anchor and resolved.suffix == '.md' and resolved.is_file() \
                        and unquote(anchor).lower() not in anchors(resolved):
                    broken.append(f'{name}:{number}: {target}')
    return broken


if __name__ == '__main__':
    listed = subprocess.run(['git', 'ls-files', '-z', '--', '*.md'], cwd=ROOT,
                            capture_output=True, text=True)
    files = [f for f in listed.stdout.split('\0') if f and (ROOT / f).is_file()]
    if listed.returncode != 0 or len(files) < MIN_FILES:
        print(f'  scanned {len(files)} tracked Markdown files, expected at least '
              f'{MIN_FILES}; the listing is broken')
        sys.exit(1)
    findings = check(files)
    for finding in findings:
        print('  ' + finding)
    if not findings:
        print(f'{len(files)} Markdown files')
    sys.exit(1 if findings else 0)
