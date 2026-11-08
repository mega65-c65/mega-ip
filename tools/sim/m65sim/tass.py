"""Assemble 64tass sources for testing: binary, load address and labels."""

import os
import re
import subprocess
import tempfile


class AssemblyError(Exception):
    pass


class Assembly:
    def __init__(self, binary, start, labels, output):
        self.binary = binary          # bytes, gaps between segments zero-filled
        self.start = start            # address of binary[0]
        self.labels = labels          # name -> int (global labels and constants)
        self.output = output          # assembler stdout/stderr

    def __getitem__(self, name):
        try:
            return self.labels[name]
        except KeyError:
            raise KeyError('label %r not found in assembly' % name) from None

    @property
    def end(self):
        return self.start + len(self.binary)


_DATA = re.compile(r'Data:\s+\d+\s+\$([0-9a-fA-F]+)-\$([0-9a-fA-F]+)')
_LABEL = re.compile(r'^(\S+?)\s*=\s*(\$[0-9a-fA-F]+|%[01]+|-?\d+)\s*$')


def _value(text):
    if text.startswith('$'):
        return int(text[1:], 16)
    if text.startswith('%'):
        return int(text[1:], 2)
    return int(text)


def find_tass(start_dir=None):
    """Locate 64tass: $M65SIM_TASS, then PATH, then 64tass(.exe) in
    `start_dir` or any parent directory."""
    import shutil
    env = os.environ.get('M65SIM_TASS')
    if env:
        return env
    on_path = shutil.which('64tass')
    if on_path:
        return on_path
    d = os.path.abspath(start_dir or os.getcwd())
    while True:
        for name in ('64tass.exe', '64tass'):
            p = os.path.join(d, name)
            if os.path.isfile(p):
                return p
        parent = os.path.dirname(d)
        if parent == d:
            raise AssemblyError('64tass not found; set M65SIM_TASS')
        d = parent


def assemble_text(text, tass, workdir=None, name='snippet'):
    """Assemble source text (e.g. a test snippet)."""
    workdir = workdir or tempfile.mkdtemp(prefix='m65sim_')
    path = os.path.join(workdir, name + '.asm')
    with open(path, 'w') as f:
        f.write(text)
    return assemble(path, tass, workdir=workdir)


def assemble(source, tass, defines=None, workdir=None, extra_args=()):
    """Assemble `source` (path) with the 64tass executable `tass`.

    `defines` maps symbol -> value (passed as -D).  Output goes to `workdir`
    (a new temp dir by default).  Raises AssemblyError on failure.
    """
    workdir = workdir or tempfile.mkdtemp(prefix='m65sim_')
    base = os.path.splitext(os.path.basename(source))[0]
    out = os.path.join(workdir, base + '.bin')
    lbl = os.path.join(workdir, base + '.lbl')
    args = [tass, source, '--nostart', '-o', out, '-l', lbl]
    for k, v in (defines or {}).items():
        args += ['-D', '%s=%s' % (k, v)]
    args += list(extra_args)
    proc = subprocess.run(args, capture_output=True, text=True,
                          cwd=os.path.dirname(os.path.abspath(source)) or None)
    output = proc.stdout + proc.stderr
    if proc.returncode != 0:
        raise AssemblyError('64tass failed:\n' + output)
    starts = [int(m.group(1), 16) for m in _DATA.finditer(output)]
    if not starts:
        raise AssemblyError('could not find the load address in:\n' + output)
    with open(out, 'rb') as f:
        binary = f.read()
    labels = {}
    with open(lbl) as f:
        for line in f:
            m = _LABEL.match(line.strip())
            if m:
                labels[m.group(1)] = _value(m.group(2))
    return Assembly(binary, min(starts), labels, output)
