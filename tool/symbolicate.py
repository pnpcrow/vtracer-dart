"""Symbolicate crash offsets against the local Flutter engine PDB via dbghelp."""
import ctypes
import ctypes.wintypes as wt
import sys

DLL = r'C:\Develop\flutter\bin\cache\artifacts\engine\windows-x64-release\flutter_windows.dll'
BASE = 0x10000000

kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
dbghelp = ctypes.WinDLL('dbghelp', use_last_error=True)

kernel32.GetCurrentProcess.restype = ctypes.c_void_p

dbghelp.SymInitializeW.argtypes = [ctypes.c_void_p, wt.LPCWSTR, wt.BOOL]
dbghelp.SymInitializeW.restype = wt.BOOL
dbghelp.SymSetOptions.argtypes = [wt.DWORD]
dbghelp.SymSetOptions.restype = wt.DWORD
dbghelp.SymLoadModuleExW.argtypes = [
    ctypes.c_void_p, ctypes.c_void_p, wt.LPCWSTR, wt.LPCWSTR,
    ctypes.c_ulonglong, wt.DWORD, ctypes.c_void_p, wt.DWORD]
dbghelp.SymLoadModuleExW.restype = ctypes.c_ulonglong
dbghelp.SymCleanup.argtypes = [ctypes.c_void_p]
dbghelp.SymCleanup.restype = wt.BOOL


class SYMBOL_INFOW(ctypes.Structure):
    _fields_ = [('SizeOfStruct', wt.ULONG), ('TypeIndex', wt.ULONG),
                ('Reserved', ctypes.c_ulonglong * 2), ('Index', wt.ULONG),
                ('Size', wt.ULONG), ('ModBase', ctypes.c_ulonglong),
                ('Flags', wt.ULONG), ('Value', ctypes.c_ulonglong),
                ('Address', ctypes.c_ulonglong), ('Register', wt.ULONG),
                ('Scope', wt.ULONG), ('Tag', wt.ULONG),
                ('NameLen', wt.ULONG), ('MaxNameLen', wt.ULONG),
                ('Name', ctypes.c_wchar * 512)]


class IMAGEHLP_LINEW64(ctypes.Structure):
    _fields_ = [('SizeOfStruct', wt.DWORD), ('Key', ctypes.c_void_p),
                ('LineNumber', wt.DWORD), ('FileName', ctypes.c_wchar_p),
                ('Address', ctypes.c_ulonglong)]


dbghelp.SymFromAddrW.argtypes = [
    ctypes.c_void_p, ctypes.c_ulonglong,
    ctypes.POINTER(ctypes.c_ulonglong), ctypes.POINTER(SYMBOL_INFOW)]
dbghelp.SymFromAddrW.restype = wt.BOOL
dbghelp.SymGetLineFromAddrW64.argtypes = [
    ctypes.c_void_p, ctypes.c_ulonglong,
    ctypes.POINTER(wt.DWORD), ctypes.POINTER(IMAGEHLP_LINEW64)]
dbghelp.SymGetLineFromAddrW64.restype = wt.BOOL

# LOAD_LINES | UNDNAME | DEFERRED_LOADS
dbghelp.SymSetOptions(0x10 | 0x02 | 0x04)

hproc = kernel32.GetCurrentProcess()
if not dbghelp.SymInitializeW(hproc, None, False):
    raise ctypes.WinError(ctypes.get_last_error())

import os
size = os.path.getsize(DLL)
loaded = dbghelp.SymLoadModuleExW(hproc, None, DLL, 'flutter_windows', BASE, size, None, 0)
print(f'SymLoadModuleExW -> 0x{loaded or 0:x} (lasterr={ctypes.get_last_error()})')

offsets = [int(x, 16) for x in sys.argv[1:]] if len(sys.argv) > 1 else [
    0x3c16a, 0x3bb3a, 0x3ee4b, 0x3b310, 0x19a90, 0xdab55, 0xe9447,
    0x728627, 0xe936e, 0x728376, 0x71fc80, 0x733a56, 0xe9e66, 0x70f059,
    0x7767, 0x7a6dc7, 0x73ec26, 0x73ce88, 0x8348b5, 0x7fa88b, 0x83452a,
    0x286ac, 0xe4f80,
]
for off in offsets:
    addr = BASE + off
    si = SYMBOL_INFOW()
    si.SizeOfStruct = 88
    si.MaxNameLen = 511
    dis = ctypes.c_ulonglong(0)
    ok = dbghelp.SymFromAddrW(hproc, addr, ctypes.byref(dis), ctypes.byref(si))
    err = ctypes.get_last_error()
    name = si.Name[:si.NameLen] if ok else f'?? (err {err})'
    line = IMAGEHLP_LINEW64()
    line.SizeOfStruct = ctypes.sizeof(line)
    pd = wt.DWORD(0)
    ok2 = dbghelp.SymGetLineFromAddrW64(hproc, addr, ctypes.byref(pd), ctypes.byref(line))
    src = ''
    if ok2:
        src = f'  [{line.FileName}:{line.LineNumber}+{pd.value}]'
    print(f'+0x{off:06x}  {name}+0x{dis.value:x}{src}')

dbghelp.SymCleanup(hproc)
