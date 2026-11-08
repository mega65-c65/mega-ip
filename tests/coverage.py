"""Run the stack tests and report which instructions of eth.bin they ran.

    python tests/coverage.py [--out FILE] [--all]

Prints a summary and writes the full report (routines never entered, and
for each partly covered routine the source lines that never ran) to FILE,
default target/coverage.txt.  --all lists every partly covered routine;
otherwise routines with fewer than 3 missed instructions are left out.
"""

import argparse
import io
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
os.environ['MEGAIP_COVERAGE'] = '1'          # before stack is imported
sys.path.insert(0, HERE)

import stack  # noqa: E402
from m65sim import assemble, coverage_report, find_tass, parse_listing  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--out', default=os.path.join(stack.ROOT, 'target', 'coverage.txt'))
    ap.add_argument('--all', action='store_true')
    args = ap.parse_args()

    suite = unittest.TestLoader().discover(HERE)
    result = unittest.TextTestRunner(stream=io.StringIO(), verbosity=0).run(suite)
    print('tests: %d run, %d failures, %d errors' % (
        result.testsRun, len(result.failures), len(result.errors)))

    work = tempfile.mkdtemp(prefix='megaip_cov_')
    lst = os.path.join(work, 'eth.lst')
    src_root = os.environ.get('MEGAIP_ROOT', stack.ROOT)
    assemble(os.path.join(src_root, 'src', 'eth.asm'), find_tass(stack.ROOT), workdir=work,
             extra_args=['-L', lst, '--line-numbers'])
    text = coverage_report(stack.COVERAGE, parse_listing(lst, root=src_root),
                           min_uncovered=1 if args.all else 3)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, 'w') as f:
        f.write(text)
    summary = text.split('\nRoutines never entered')[0]
    print(summary)
    never = text.split('Routines never entered (')[1].split(')')[0]
    print('routines never entered: %s (details in %s)' % (never, args.out))
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(main())
