import os
import pefile

CASES = [
    (r'C:\Develop\Repositories\vtracer-dart\apps\vtracer_app\build\windows\x64\runner\Debug\flutter_windows.dll', 0x3c18a),
    (r'C:\Develop\Repositories\vtracer-dart\apps\vtracer_app\build\windows\x64\runner\Release\flutter_windows.dll', 0x3c16a),
]

for path, off in CASES:
    pe = pefile.PE(path, fast_load=True)
    pe.parse_data_directories(directories=[
        pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXPORT'],
        pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_DEBUG'],
    ])
    build = os.path.basename(os.path.dirname(path))
    print('===', build, f'offset 0x{off:x}')
    rva = pe.get_rva_from_offset(off)
    print(f'  RVA of fault: 0x{rva:x}')
    for s in pe.sections:
        if s.VirtualAddress <= rva < s.VirtualAddress + max(s.Misc_VirtualSize, s.SizeOfRawData):
            print(f'  section: {s.Name.decode().rstrip(chr(0))}')
    if hasattr(pe, 'DIRECTORY_ENTRY_EXPORT'):
        exports = sorted((e.address, e.name.decode() if e.name else f'ord{e.ordinal}')
                         for e in pe.DIRECTORY_ENTRY_EXPORT.symbols if e.address)
        prev = None
        for a, n in exports:
            if a > rva:
                break
            prev = (a, n)
        if prev:
            print(f'  nearest export below: {prev[1]} (+0x{rva - prev[0]:x} into it)')
        print(f'  exports count={len(exports)}, first RVA=0x{exports[0][0]:x}')
    if hasattr(pe, 'DIRECTORY_ENTRY_DEBUG'):
        for d in pe.DIRECTORY_ENTRY_DEBUG:
            if hasattr(d.entry, 'PdbFileName'):
                print('  pdb:', d.entry.PdbFileName.rstrip(b'\0').decode())
    print()
