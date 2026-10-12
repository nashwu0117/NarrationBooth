#!/usr/bin/env python3
"""Lists UI strings that are missing, unused or broken in Localizations/*.json.

Every UI string is written in the source as T("繁體中文", "English"); the English text is the key in the JSON files.
Run after changing UI text:  python3 Scripts/check_translations.py          (report)
                             python3 Scripts/check_translations.py --fix    (add missing keys with empty values)
"""
import glob, json, re, sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
lit = r'"((?:[^"\\]|\\.)*)"'
call = re.compile(r'\bT\(\s*' + lit + r'\s*,\s*' + lit, re.S)
spec = re.compile(r'%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?[@dfs%]')


def unescape(s):
    return s.replace('\\"', '"').replace('\\n', '\n').replace('\\\\', '\\')


def specs(s):
    return sorted(re.sub(r'\d+\$', '', x) for x in spec.findall(s))


keys = []
for f in sorted(glob.glob(str(root / 'Sources/NarrationBooth/*.swift'))):
    for m in call.finditer(open(f, encoding='utf-8').read()):
        en = unescape(m.group(2))
        if en not in keys:
            keys.append(en)

fix = '--fix' in sys.argv
problems = 0
for path in sorted((root / 'Localizations').glob('*.json')):
    table = json.loads(path.read_text(encoding='utf-8'))
    missing = [k for k in keys if not table.get(k)]
    unused = [k for k in table if k not in keys]
    broken = [k for k in keys if table.get(k) and specs(k) != specs(table[k])]
    print(f'{path.name}: {len(keys) - len(missing)}/{len(keys)} translated, '
          f'{len(missing)} missing, {len(unused)} unused, {len(broken)} with wrong placeholders')
    for k in broken:
        print(f'  placeholders differ: {k!r}')
    problems += len(missing) + len(broken)
    if fix:
        out = {k: table.get(k, '') for k in keys}
        path.write_text(json.dumps(out, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
sys.exit(1 if problems and not fix else 0)
