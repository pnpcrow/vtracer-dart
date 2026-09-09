import struct

path = r'C:\Develop\flutter\bin\cache\artifacts\engine\windows-x64-release\flutter_windows.dll.pdb'
f = open(path, 'rb')
hdr = f.read(56)
sig, blocksize, freeblock, nblocks, dirsize, unk, blockmapaddr = struct.unpack('<32sIIIIII', hdr)
f.seek(blockmapaddr * blocksize)
ndirblocks = (dirsize + blocksize - 1) // blocksize
dirblocks = struct.unpack('<' + 'I' * ndirblocks, f.read(4 * ndirblocks))
dirdata = b''
for b in dirblocks:
    f.seek(b * blocksize)
    dirdata += f.read(blocksize)
dirdata = dirdata[:dirsize]
pos = 0
(nstreams,) = struct.unpack_from('<I', dirdata, pos)
pos += 4
sizes = struct.unpack_from('<' + 'I' * nstreams, dirdata, pos)
pos += 4 * nstreams
blocks_of = []
for s in sizes:
    if s == 0xFFFFFFFF:
        blocks_of.append(None)
        continue
    n = (s + blocksize - 1) // blocksize
    blocks_of.append((s, struct.unpack_from('<' + 'I' * n, dirdata, pos)))
    pos += 4 * n
size1, blocks = blocks_of[1]
data = b''
for b in blocks:
    f.seek(b * blocksize)
    data += f.read(blocksize)
data = data[:size1]
ver, sig_, age = struct.unpack_from('<III', data, 0)
guid = data[12:28]
print('ver', ver, 'guid', guid.hex().upper(), 'age', age)
f.close()
