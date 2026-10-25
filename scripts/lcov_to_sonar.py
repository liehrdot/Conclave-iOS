"""Turn an lcov file into SonarQube's generic coverage XML.

SonarQube Cloud reads Swift coverage only from Xcode's own reports, which need a Mac; our core tests run
on Linux. llvm-cov there writes lcov, and SonarQube reads any language from its generic format, so this
keeps just the covered/uncovered lines (DA records) per file, with paths relative to the repository.

    python3 scripts/lcov_to_sonar.py coverage.lcov > coverage.xml
"""

import os
import sys
from xml.sax.saxutils import quoteattr


def convert(lcov: str, root: str) -> str:
    files: dict[str, dict[int, bool]] = {}
    lines: dict[int, bool] = {}
    for raw in lcov.splitlines():
        if raw.startswith("SF:"):
            lines = files.setdefault(os.path.relpath(raw[3:], root), {})
        elif raw.startswith("DA:"):
            number, hits = raw[3:].split(",")[:2]
            lines[int(number)] = lines.get(int(number), False) or int(hits) > 0
    out = ['<coverage version="1">']
    for path, covered in sorted(files.items()):
        out.append(f"  <file path={quoteattr(path)}>")
        out += [f'    <lineToCover lineNumber="{n}" covered="{str(c).lower()}"/>' for n, c in sorted(covered.items())]
        out.append("  </file>")
    out.append("</coverage>")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as f:
        sys.stdout.write(convert(f.read(), os.getcwd()))
