"""m65sim: a small MEGA65 simulator for unit-testing 45GS02 code in isolation.

See tools/sim/README.md.
"""

from .cpu import Cpu, CpuError, OPCODES
from .dma import Dma, DmaError
from .ethernet import Ethernet
from .machine import Machine, Registers, StopRun, ETH_BUFFER
from .tass import assemble, assemble_text, find_tass, Assembly, AssemblyError
from .coverage import Coverage, parse_listing, report as coverage_report

__all__ = ['Cpu', 'CpuError', 'OPCODES', 'Dma', 'DmaError', 'Ethernet',
           'Machine', 'Registers', 'StopRun', 'ETH_BUFFER', 'assemble', 'assemble_text',
           'find_tass', 'Assembly', 'AssemblyError', 'Coverage', 'parse_listing',
           'coverage_report']
