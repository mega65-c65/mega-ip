"""Mutation testing: flip branches in eth.bin and check the tests notice.

    python tests/mutate.py [--sample N] [--file dns.asm] [--jobs J] [--seed S]

Each mutant flips one conditional branch (BEQ<->BNE, BCC<->BCS, BMI<->BPL,
BVC<->BVS, 8- and 16-bit forms) among the instructions the suite executes,
then runs the whole suite on the patched binary in its own process,
stopping at the first failure.  A mutant the suite fails on is "killed"; a
"surviving" mutant is a branch whose direction no test checks, worth a
look.  Hangs are caught by the harness's instruction limits and count as
killed.  Slow (one suite run per mutant): run it by hand, not in the build.
"""

import argparse
import concurrent.futures
import os
import random
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
os.environ['MEGAIP_COVERAGE'] = '1'
sys.path.insert(0, HERE)

import stack  # noqa: E402
from m65sim import assemble, find_tass, parse_listing  # noqa: E402

FLIP = {0xF0: 0xD0, 0xD0: 0xF0, 0x90: 0xB0, 0xB0: 0x90, 0x30: 0x10, 0x10: 0x30,
        0x50: 0x70, 0x70: 0x50,                                        # 8-bit
        0xF3: 0xD3, 0xD3: 0xF3, 0x93: 0xB3, 0xB3: 0x93, 0x33: 0x13, 0x13: 0x33,
        0x53: 0x73, 0x73: 0x53}                                        # 16-bit


def executed_branches(file_filter):
    """Branches the suite runs, as (Instruction, opcode) pairs."""
    import io
    import unittest
    result = unittest.TextTestRunner(stream=io.StringIO()).run(
        unittest.TestLoader().discover(HERE))
    if not result.wasSuccessful():
        sys.exit('the unmutated suite fails; fix that first')
    work = tempfile.mkdtemp(prefix='megaip_mut_')
    lst = os.path.join(work, 'eth.lst')
    asm = assemble(os.path.join(stack.ROOT, 'src', 'eth.asm'), find_tass(stack.ROOT),
                   workdir=work, extra_args=['-L', lst, '--line-numbers'])
    out = []
    for ins in parse_listing(lst, root=stack.ROOT):
        if ins.addr not in stack.COVERAGE:
            continue
        if file_filter and file_filter not in (ins.file or ''):
            continue
        op = asm.binary[ins.addr - asm.start]
        if op in FLIP:
            out.append((ins, op))
    return out


def run_mutant(branch):
    ins, op = branch
    env = dict(os.environ)
    env.pop('MEGAIP_COVERAGE', None)
    env['MEGAIP_MUTATE'] = '%04x=%02x' % (ins.addr, FLIP[op])
    env['MEGAIP_FUZZ'] = '100'                      # keep the fuzzer short
    try:
        proc = subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', HERE, '-f'],
                              env=env, capture_output=True, text=True, timeout=300)
        killed = proc.returncode != 0
    except subprocess.TimeoutExpired:
        killed = True
    return ins, killed


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--sample', type=int, default=0, help='test N random mutants (0 = all)')
    ap.add_argument('--file', help='only branches in this source file, e.g. dns.asm')
    ap.add_argument('--jobs', type=int, default=os.cpu_count() or 2)
    ap.add_argument('--seed', type=int, default=1)
    args = ap.parse_args()

    branches = executed_branches(args.file)
    if args.sample and args.sample < len(branches):
        branches = random.Random(args.seed).sample(branches, args.sample)
    print('%d mutants, %d jobs' % (len(branches), args.jobs))
    t0 = time.time()
    survivors = []
    with concurrent.futures.ProcessPoolExecutor(args.jobs) as pool:
        for n, (ins, killed) in enumerate(pool.map(run_mutant, branches), 1):
            if not killed:
                survivors.append(ins)
            print('\r%d/%d done, %d survived' % (n, len(branches), len(survivors)),
                  end='', flush=True)
    print('\n%.0f s' % (time.time() - t0))
    killed = len(branches) - len(survivors)
    print('killed %d of %d (%.0f%%)' % (killed, len(branches),
                                         100.0 * killed / max(len(branches), 1)))
    for ins in sorted(survivors, key=lambda i: (i.file, i.line)):
        print('  survived: %s:%d  %-22s %s' % (ins.file, ins.line, ins.routine, ins.source))
    return 0


if __name__ == '__main__':
    sys.exit(main())
