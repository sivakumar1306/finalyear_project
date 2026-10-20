"""Read render/Final_Report.pdf and write pages.json for the TOC and lists."""
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
import content as C  # noqa: E402
import ch_intro, ch_method, ch_results  # noqa: E402,F401


class Dummy:
    def __getattr__(self, name):
        return lambda *a, **k: None


# fill the registries without building
ch_intro.write(Dummy()); ch_method.write(Dummy()); ch_results.write(Dummy())

pdf = Path(sys.argv[1])
n = int(re.search(r'Pages:\s+(\d+)', subprocess.run(['pdfinfo', str(pdf)], capture_output=True, text=True).stdout).group(1))
pages = [subprocess.run(['pdftotext', '-layout', '-f', str(i), '-l', str(i), str(pdf), '-'],
                        capture_output=True, text=True).stdout for i in range(1, n + 1)]
lines = [[re.sub(r'\s+', ' ', l).strip() for l in p.splitlines()] for p in pages]

ch1 = next(i for i, ls in enumerate(lines) if 'CHAPTER 1' in ls)


def roman(k):
    vals = [(10, 'x'), (9, 'ix'), (5, 'v'), (4, 'iv'), (1, 'i')]
    out = ''
    for v, s in vals:
        while k >= v:
            out += s
            k -= v
    return out


def label(i):
    return str(i - ch1 + 1) if i >= ch1 else roman(i)  # page index 1 (2nd page) = i


def norm(s):
    return re.sub(r'[^a-z0-9]', '', s.lower())


out = {}
# front matter titles
for name in ('Declaration', 'Certificate', 'Abstract', 'Acknowledgements', 'Codes and Standards',
             'Mapping of Sustainable Development Goals (SDGs)', 'List of Figures', 'List of Tables', 'List of Acronyms'):
    for i in range(1, ch1):
        if any(norm(l) == norm(name) for l in lines[i]):
            out[f'FM:{name}'] = label(i)
            break
# headings
for level, num, title in C.HEADS:
    key = f'H:{num or title}'
    for i in range(ch1, n):
        hit = False
        for l in lines[i]:
            if level == 0 and num and l == f'CHAPTER {num}':
                hit = True
            elif level == 0 and not num and norm(l) == norm(title):
                hit = True
            elif level > 0 and norm(l).startswith(norm(f'{num} {title}')[:40]):
                hit = True
        if hit:
            out[key] = label(i)
            break
for num, cap in C.FIGS:
    for i in range(ch1, n):
        if any(l.startswith(f'Figure {num}:') for l in lines[i]):
            out[f'F:{num}'] = label(i)
            break
for num, cap in C.TABS:
    for i in range(ch1, n):
        if any(l.startswith(f'Table {num}:') for l in lines[i]):
            out[f'T:{num}'] = label(i)
            break
missing = [k for k in ([f'H:{n_ or t}' for _, n_, t in C.HEADS] + [f'F:{f}' for f, _ in C.FIGS] +
                       [f'T:{t}' for t, _ in C.TABS]) if k not in out]
Path(sys.argv[2]).write_text(json.dumps(out, indent=1))
print('found', len(out), 'missing', missing)
