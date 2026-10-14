"""Minimal TIFF / RW2 / ORF tag reader for LNS-02 research (read-only, no writing)."""

import struct

SIZES = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8, 13: 4}


class Reader:
    def __init__(self, data, base=0, little=None):
        self.data = data
        self.base = base
        if little is None:
            little = data[base:base + 2] == b"II"
        self.e = "<" if little else ">"

    def u16(self, off):
        return struct.unpack_from(self.e + "H", self.data, off)[0]

    def u32(self, off):
        return struct.unpack_from(self.e + "I", self.data, off)[0]

    def entries(self, off, rel=0):
        """Entries of the IFD at absolute offset `off`; value offsets are `rel` + stored offset."""
        if off + 2 > len(self.data):
            return []
        n = self.u16(off)
        if n > 1000 or off + 2 + n * 12 > len(self.data):
            return []
        out = []
        for i in range(n):
            at = off + 2 + i * 12
            tag, typ, count = self.u16(at), self.u16(at + 2), self.u32(at + 4)
            size = SIZES.get(typ, 1) * count
            voff = at + 8 if size <= 4 else rel + self.u32(at + 8)
            out.append((tag, typ, count, voff))
        return out

    def next_ifd(self, off):
        n = self.u16(off)
        return self.u32(off + 2 + n * 12)

    def raw(self, entry):
        tag, typ, count, voff = entry
        return self.data[voff:voff + SIZES.get(typ, 1) * count]

    def values(self, entry, fmt=None):
        tag, typ, count, voff = entry
        b = self.raw(entry)
        if fmt is None:
            fmt = {1: "B", 2: "s", 3: "H", 4: "I", 6: "b", 7: "B", 8: "h", 9: "i", 11: "f", 12: "d", 13: "I"}.get(typ, "B")
        if typ in (5, 10) and fmt in ("rational",):
            pass
        if typ == 5:
            v = struct.unpack(self.e + "%dI" % (2 * count), b)
            return [v[2 * i] / v[2 * i + 1] if v[2 * i + 1] else 0 for i in range(count)]
        if typ == 10:
            v = struct.unpack(self.e + "%di" % (2 * count), b)
            return [v[2 * i] / v[2 * i + 1] if v[2 * i + 1] else 0 for i in range(count)]
        if fmt == "s":
            return b.split(b"\0")[0].decode("latin1")
        size = struct.calcsize(fmt)
        n = len(b) // size
        return list(struct.unpack(self.e + "%d%s" % (n, fmt), b[: n * size]))


def tiff_ifd0(data):
    r = Reader(data)
    return r, r.u32(4)


def find(entries, tag):
    for e in entries:
        if e[0] == tag:
            return e
    return None


def exif_makernote(data):
    """(reader, makernote absolute offset, length) for a TIFF-like file."""
    r, ifd0 = tiff_ifd0(data)
    for e in r.entries(ifd0):
        if e[0] == 0x8769:
            exif = r.u32(e[3])
            for x in r.entries(exif):
                if x[0] == 0x927C:
                    return r, x[3], x[2]
    return r, None, 0


def olympus_makernote(data):
    """The Olympus/OM maker note: (reader, IFD offset, base for offsets)."""
    r, mn, length = exif_makernote(data)
    if mn is None:
        return None
    head = data[mn:mn + 16]
    if head.startswith(b"OM SYSTEM\0"):
        rr = Reader(data, little=data[mn + 12:mn + 14] == b"II")
        return rr, mn + 16, mn, "OM SYSTEM"
    if head.startswith(b"OLYMPUS\0"):
        rr = Reader(data, little=data[mn + 8:mn + 10] == b"II")
        return rr, mn + 12, mn, "OLYMPUS"
    if head.startswith(b"OLYMP\0"):
        return r, mn + 8, 0, "OLYMP"
    return None


def olympus_subifds(data):
    """{tag: entries} for the maker note's sub-IFDs (0x2010 Equipment ... 0x2040 ImageProcessing)."""
    got = olympus_makernote(data)
    if got is None:
        return None, {}, None
    r, ifd, base, kind = got
    top = r.entries(ifd, rel=base)
    subs = {"top": top}
    for e in top:
        tag, typ, count, voff = e
        if tag in (0x2010, 0x2020, 0x2030, 0x2031, 0x2040, 0x2050, 0x3000, 0x4000, 0x5000):
            if typ in (13, 4) or (typ == 7):
                # Sub-IFD stored as IFD type with offset, or as UNDEFINED block holding an IFD.
                if typ == 7:
                    off = voff
                    # In OLYMP (old) maker notes, these are UNDEFINED blocks with IFD inside, offsets from block? keep simple
                    subs[tag] = r.entries(off, rel=base)
                else:
                    off = base + r.u32(voff) if count == 1 else voff
                    subs[tag] = r.entries(off, rel=base)
    return r, subs, kind
