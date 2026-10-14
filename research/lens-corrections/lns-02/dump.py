"""Dumps the lens-correction candidate tags of RW2 and ORF files."""

import struct
import sys

from tiff import Reader, find, olympus_subifds, tiff_ifd0


def rw2(path, verbose=True):
    data = open(path, "rb").read()
    r, ifd0 = tiff_ifd0(data)
    magic = r.u16(2)
    out = {"magic": hex(magic)}
    entries = r.entries(ifd0)
    if verbose:
        for e in entries:
            tag, typ, count, voff = e
            if tag in (0x0119, 0x011A, 0x011B, 0x011C, 0x0120, 0x0121, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0x0008, 0x0118):
                b = r.raw(e)
                print("  %#06x type %d count %d" % (tag, typ, count), end=" ")
                if len(b) % 2 == 0 and len(b) <= 128:
                    print(list(struct.unpack("<%dh" % (len(b) // 2), b)))
                else:
                    print(b[:64].hex())
    e = find(entries, 0x0119)
    if e:
        b = r.raw(e)
        out["0119"] = list(struct.unpack("<%dh" % (len(b) // 2), b))
    e = find(entries, 0x011B)
    if e:
        b = r.raw(e)
        out["011B"] = list(struct.unpack("<%dh" % (len(b) // 2), b))
    return out


def orf(path, tags=(0x0801, 0x0804, 0x0805, 0x1503), verbose=True):
    data = open(path, "rb").read()
    r, subs, kind = olympus_subifds(data)
    out = {"kind": kind}
    ip = subs.get(0x2040, [])
    for e in ip:
        tag, typ, count, voff = e
        if verbose and (tags == "all" or tag in tags):
            print("  IP %#06x type %d count %d" % (tag, typ, count), r.values(e)[:64])
        if tags == "all" or tag in tags:
            out["%04X" % tag] = r.values(e)
    return out


if __name__ == "__main__":
    for path in sys.argv[1:]:
        print(path)
        if path.lower().endswith((".rw2", ".rwl", ".raw")):
            print(rw2(path))
        else:
            print(orf(path, tags="all" if "-a" in sys.argv else (0x0801, 0x0804, 0x0805, 0x1503)))
