"""Instruction coverage: which assembled instructions ran.

    cov = Coverage()
    machine.coverage = cov          # every Machine sharing it adds to it
    ... run tests ...
    listing = parse_listing('prog.lst')     # 64tass -L ... --line-numbers
    print(report(cov, listing))

Coverage survives copy.deepcopy (snapshots share the one collector), so a
whole test run accumulates into one set of executed CPU addresses.
"""

import os
import re
from collections import OrderedDict


class Coverage(set):
    """Set of executed CPU addresses; shared, not copied, by deepcopy."""

    def __deepcopy__(self, memo):
        return self

    def __copy__(self):
        return self

    def __reduce__(self):              # pickling keeps the contents only
        return (Coverage, (list(self),))


class Instruction:
    __slots__ = ('addr', 'file', 'line', 'source', 'routine')

    def __init__(self, addr, file, line, source, routine):
        self.addr, self.file, self.line = addr, file, line
        self.source, self.routine = source, routine


_FILE = re.compile(r'^:(\d+)\t;\*+\s+(?:Processing (?:input )?file|Return to file):\s*(.+)$')
_CODE = re.compile(r'^(\d+)\t\.([0-9a-f]{4})\t([0-9a-f]{2}(?: [0-9a-f]{2})*)\t+(\S[^\t]*)\t+(.*)$')
_LABEL = re.compile(r'^(\d+)\t\.[0-9a-f]{4}\t\t\t\t\t([A-Za-z][\w.]*):?\s*$')


def parse_listing(path, root=None):
    """Instructions from a 64tass listing made with -L and --line-numbers.

    Data lines (.byte, inline DMA lists) have no disassembly and are not
    counted.  `routine` is the nearest preceding global label."""
    files, current, routine = {}, None, None
    out = []
    with open(path) as f:
        for raw in f:
            line = raw.rstrip('\n')
            m = _FILE.match(line)
            if m:
                num, name = m.group(1), m.group(2).strip()
                files.setdefault(num, os.path.relpath(name, root) if root else name)
                current = files[num]
                continue
            m = _LABEL.match(line)
            if m:
                routine = m.group(2)
                continue
            m = _CODE.match(line)
            if m:
                out.append(Instruction(int(m.group(2), 16), current, int(m.group(1)),
                                       m.group(5).strip(), routine))
    return out


def report(cov, instructions, detail=True, min_uncovered=1):
    """A text report: totals per file, then per routine with the lines that
    never ran.  Routines with fewer than `min_uncovered` missed lines are
    left out of the detail."""
    by_file = OrderedDict()
    by_routine = OrderedDict()
    for ins in instructions:
        hit = ins.addr in cov
        f = by_file.setdefault(ins.file, [0, 0])
        f[0] += 1
        f[1] += hit
        r = by_routine.setdefault((ins.file, ins.routine), [])
        r.append((ins, hit))

    total = sum(v[0] for v in by_file.values())
    ran = sum(v[1] for v in by_file.values())
    lines = ['Instruction coverage: %d of %d (%.1f%%)' % (ran, total, 100.0 * ran / max(total, 1)),
             '', '%-22s %8s %8s %7s' % ('file', 'instr', 'run', 'cover')]
    for name, (n, h) in sorted(by_file.items(), key=lambda kv: kv[0] or ''):
        lines.append('%-22s %8d %8d %6.1f%%' % (name, n, h, 100.0 * h / max(n, 1)))

    never = [(k, v) for k, v in by_routine.items() if not any(h for _, h in v)]
    lines += ['', 'Routines never entered (%d):' % len(never)]
    for (fname, rname), v in never:
        lines.append('  %s:%d  %s  (%d instructions)' % (fname, v[0][0].line, rname, len(v)))

    if detail:
        lines += ['', 'Partly covered routines, lines that never ran:']
        partial = [(k, v) for k, v in by_routine.items()
                   if any(h for _, h in v) and sum(not h for _, h in v) >= min_uncovered]
        partial.sort(key=lambda kv: -sum(not h for _, h in kv[1]))
        for (fname, rname), v in partial:
            missed = [ins for ins, h in v if not h]
            lines.append('  %s  %s: %d of %d not run' % (fname, rname, len(missed), len(v)))
            for ins in missed:
                lines.append('      %s:%d  %s' % (fname, ins.line, ins.source))
    return '\n'.join(lines) + '\n'
