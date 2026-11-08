"""m65sim: a small MEGA65 simulator for unit-testing 45GS02 code in isolation.

See tools/sim/README.md.
"""

from .cpu import Cpu, CpuError, OPCODES
from .dma import Dma, DmaError
from .ethernet import Ethernet
from .machine import Machine, StopRun, ETH_BUFFER
from .tass import assemble, assemble_text, find_tass, Assembly, AssemblyError

__all__ = ['Cpu', 'CpuError', 'OPCODES', 'Dma', 'DmaError', 'Ethernet',
           'Machine', 'StopRun', 'ETH_BUFFER', 'assemble', 'assemble_text',
           'find_tass', 'Assembly', 'AssemblyError']
