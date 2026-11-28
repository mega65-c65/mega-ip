"""Checks on the BASIC 65 programs' source (they can't run on the simulator).

In BASIC 65, TI counts seconds (MEGA65 book, B-253), not the 1/60 s jiffies
of C64 BASIC.  A wait written as `ti-t<600` waits ten minutes, not ten
seconds.
"""

import glob
import os
import re
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
LONGEST_WAIT = 120             # seconds; anything longer was written in jiffies

# ti-<var> compared with a number, either way round
_TI_WAIT = re.compile(r'\bti\s*-\s*[a-z][a-z0-9]*\s*([<>]=?|=)\s*(\d+)', re.I)


def basic_sources():
    src_root = os.environ.get('MEGAIP_ROOT', ROOT)
    return sorted(glob.glob(os.path.join(src_root, 'basic', '*.bas')))


def code(line):
    """The line without its strings and its rem."""
    line = re.sub(r'"[^"]*("|$)', '""', line)
    return re.split(r'\brem\b', line, maxsplit=1, flags=re.I)[0]


class TiWaits(unittest.TestCase):
    def test_waits_are_in_seconds(self):
        found = []
        long_waits = []
        for path in basic_sources():
            with open(path, encoding='latin-1') as f:
                for line in f:
                    for m in _TI_WAIT.finditer(code(line)):
                        found.append(m.group(0))
                        if int(m.group(2)) > LONGEST_WAIT:
                            long_waits.append('%s: %s' % (os.path.basename(path), line.strip()))
        self.assertTrue(found, 'no TI waits found: has the pattern gone stale?')
        self.assertEqual(long_waits, [])

    def test_pattern(self):
        self.assertEqual(_TI_WAIT.search('if ti-tt<600 then 410').group(2), '600')
        self.assertEqual(_TI_WAIT.search('if jp=1 and ti-jt>10 then').group(2), '10')
        self.assertIsNone(_TI_WAIT.search(code('print"ti-tt<600":rem')))
        self.assertIsNone(_TI_WAIT.search(code('10 rem wait ti-tt<600')))


if __name__ == '__main__':
    unittest.main()
