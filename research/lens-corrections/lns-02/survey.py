"""Surveys the candidate lens-correction tags across the bench's Panasonic and Olympus samples."""

import json
import os
import struct
import sys

from tiff import Reader, find, olympus_subifds, tiff_ifd0

ROOT = "/Volumes/SSD/redlamp-tmp/pv16-raw-pixls"


def exif(data):
    r, ifd0 = tiff_ifd0(data)
    info = {}
    ents = r.entries(ifd0)
    for e in ents:
        if e[0] == 0x010F:
            info["make"] = r.values(e, "s")
        if e[0] == 0x0110:
            info["model"] = r.values(e, "s")
        if e[0] == 0x8769:
            for x in r.entries(r.u32(e[3])):
                if x[0] == 0x920A:
                    info["focal"] = r.values(x)[0]
                if x[0] == 0xA434:
                    info["lens"] = r.values(x, "s")
                if x[0] == 0xA405:
                    info["focal35"] = r.values(x)[0]
    return r, ifd0, ents, info


def rw2(path):
    data = open(path, "rb").read()
    r, ifd0, ents, info = exif(data)
    info["magic"] = hex(r.u16(2))
    e = find(ents, 0x0119)
    if e:
        b = r.raw(e)
        info["d"] = list(struct.unpack("<%dh" % (len(b) // 2), b))
    for tag, name in ((0x002E, "jpg"), (0x0127, "jpg2")):
        e = find(ents, tag)
        if e:
            info[name] = e[2]
    for tag, name in ((0x0002, "sw"), (0x0003, "sh"), (0x0004, "top"), (0x0005, "left"), (0x0006, "bottom"), (0x0007, "right")):
        e = find(ents, tag)
        if e:
            info[name] = r.values(e)[0]
    return info


def orf(path):
    data = open(path, "rb").read()
    r0, ifd0, ents, info = exif(data)
    r, subs, kind = olympus_subifds(data)
    info["kind"] = kind
    if r is None:
        return info
    for e in subs.get(0x2010, []):
        if e[0] == 0x0203:
            info["lens"] = r.values(e, "s")
        if e[0] == 0x0201:
            info["lensType"] = r.values(e)
    ip = subs.get(0x2040, [])
    for e in ip:
        tag = e[0]
        if tag in (0x0801, 0x0804, 0x1503, 0x150A, 0x150C, 0x1510, 0x1011, 0x1012, 0x1513, 0x1520, 0x0802, 0x0806, 0x0807, 0x0611, 0x0612, 0x0613, 0x0614, 0x0615, 0x1112, 0x1113):
            info["%04X" % tag] = r.values(e)
    return info


if __name__ == "__main__":
    out = {}
    names = sorted(os.listdir(ROOT))
    for name in names:
        low = name.lower()
        path = os.path.join(ROOT, name)
        try:
            if low.endswith((".rw2", ".rwl")) or (low.endswith(".raw") and (name.startswith("Panasonic") or name.startswith("Leica"))):
                out[name] = rw2(path)
            elif low.endswith((".orf", ".ori")):
                out[name] = orf(path)
        except Exception as error:
            out[name] = {"error": repr(error)}
    json.dump(out, open("survey.json", "w"), indent=1, default=str)
    for name, info in out.items():
        if "d" in info or "magic" in info:
            d = info.get("d")
            print("%-32s %-18s %-40s f=%s d=%s" % (name[:32], info.get("model", "")[:18], (info.get("lens") or "")[:40], info.get("focal"), d))
    print()
    for name, info in out.items():
        if "kind" in info:
            print("%-32s %-16s %-36s f=%s v=%s ca=%s k=%s 1503=%s dc=%s sc=%s" % (
                name[:32], (info.get("model") or "")[:16], (info.get("lens") or "")[:36], info.get("focal"),
                (info.get("0801") or [])[:2] + (info.get("0801") or [])[-1:], bool(info.get("150C")),
                [round(x, 5) for x in info.get("150A", [])], info.get("1503"), info.get("1011"), info.get("1012")))
