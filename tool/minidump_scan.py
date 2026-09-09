"""Minimal minidump stack scanner for crash triage.

Parses a Windows minidump, prints the exception record, the faulting
thread's RIP/RSP, the loaded module list, and a heuristic stack scan
(all qwords on the faulting stack that point into a module).
"""
import struct
import sys


def read(stream, off, fmt):
    stream.seek(off)
    data = stream.read(struct.calcsize(fmt))
    return struct.unpack(fmt, data)


def main(path):
    f = open(path, 'rb')

    sig, ver, n_streams, dir_rva, checksum, ts, flags = read(
        f, 0, '<4sIIIIIQ')
    assert sig == b'MDMP', 'not a minidump'

    streams = {}
    for i in range(n_streams):
        stype, size, rva = read(f, dir_rva + i * 12, '<III')
        streams.setdefault(stype, []).append((size, rva))

    # ---- module list (stream 4) ----
    modules = []
    if 4 in streams:
        size, rva = streams[4][0]
        (n,) = read(f, rva, '<I')
        entry = rva + 4
        for i in range(n):
            base, msize, cksum, tds, name_rva = read(f, entry, '<QIIII')
            (name_len,) = read(f, name_rva, '<I')
            name = f.read(name_len).decode('utf-16-le').rstrip('\0')
            modules.append((base, msize, name))
            entry += 108

    def locate(addr):
        for base, msize, name in modules:
            if base <= addr < base + msize:
                return f'{name}+0x{addr - base:x}'
        return None

    # ---- exception stream (6) ----
    if 6 not in streams:
        print('no exception stream')
        return
    size, rva = streams[6][0]
    tid, _align = read(f, rva, '<II')
    exc_code, exc_flags, rec, addr, nparams = read(f, rva + 8, '<IIQQI')
    ctx_size, ctx_rva = read(f, rva + 160, '<II')
    # thread context: CONTEXT structure x64
    # P1 HomeData..P6, ctx flags at ctx+0x30
    (ctx_flags,) = read(f, ctx_rva + 0x30, '<I')
    rip, = read(f, ctx_rva + 0xF8, '<Q')
    rsp, = read(f, ctx_rva + 0x98, '<Q')

    print(f'exception: code=0x{exc_code:x} address=0x{addr:x} tid={tid}')
    print(f'  faulting location: {locate(addr)}')
    print(f'RIP=0x{rip:x} ({locate(rip)})')
    print(f'RSP=0x{rsp:x}')
    print()

    print('modules:')
    for base, msize, name in modules:
        print(f'  0x{base:012x} +0x{msize:x} {name}')
    print()

    # ---- stack scan: find memory range containing RSP ----
    def find_memory(addr):
        for stype in (5, 9):  # MemoryListStream, Memory64ListStream
            if stype not in streams:
                continue
            size, rva = streams[stype][0]
            if stype == 5:
                (n,) = read(f, rva, '<I')
                for i in range(n):
                    sa, ssz, srva = read(f, rva + 4 + i * 16, '<QQI')
                    if sa <= addr < sa + ssz:
                        return srva + (addr - sa), ssz - (addr - sa)
            else:
                nranges, base_rva = read(f, rva, '<QQ')
                off = base_rva
                p = rva + 16
                for i in range(nranges):
                    sa, ssz = read(f, p + i * 16, '<QQ')
                    if sa <= addr < sa + ssz:
                        return off + (addr - sa), ssz - (addr - sa)
                    off += ssz
        return None, None

    mem_off, avail = find_memory(rsp)
    if mem_off is None:
        print('stack memory not found in dump')
        return

    f.seek(mem_off)
    stack = f.read(min(avail, 0x8000))
    print('raw stack scan (module hits, innermost first):')
    seen = 0
    last = None
    for off in range(0, len(stack) - 8, 8):
        (v,) = struct.unpack_from('<Q', stack, off)
        loc = locate(v)
        if loc and loc != last:
            print(f'  [rsp+0x{off:04x}] {loc}')
            last = loc
            seen += 1
            if seen > 60:
                break


if __name__ == '__main__':
    main(sys.argv[1])
