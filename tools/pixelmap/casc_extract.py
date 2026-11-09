#!/usr/bin/env python3
"""Extract files by FileDataID from a local WoW CASC storage using CascLib (ctypes).

usage: casc_extract.py LIBCASC_SO WOW_ROOT PRODUCT OUTDIR FDID [FDID ...]
       casc_extract.py LIBCASC_SO WOW_ROOT PRODUCT OUTDIR @fdids.txt
Writes OUTDIR/<fdid>.blp (raw file bytes). Read-only on the storage.
"""
import ctypes, os, sys

def main():
    so, root, product, out = sys.argv[1:5]
    ids = []
    for a in sys.argv[5:]:
        if a.startswith('@'):
            ids += [int(x) for x in open(a[1:]).read().split()]
        else:
            ids.append(int(a))
    lib = ctypes.CDLL(so)
    lib.CascOpenStorage.argtypes = [ctypes.c_char_p, ctypes.c_uint32, ctypes.POINTER(ctypes.c_void_p)]
    lib.CascOpenStorage.restype = ctypes.c_bool
    lib.CascOpenFile.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.POINTER(ctypes.c_void_p)]
    lib.CascOpenFile.restype = ctypes.c_bool
    lib.CascGetFileSize.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
    lib.CascGetFileSize.restype = ctypes.c_uint32
    lib.CascReadFile.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint32)]
    lib.CascReadFile.restype = ctypes.c_bool
    lib.CascCloseFile.argtypes = [ctypes.c_void_p]
    lib.GetCascError.restype = ctypes.c_uint32
    h = ctypes.c_void_p()
    if not lib.CascOpenStorage(f"{root}*{product}".encode(), 0xFFFFFFFF, ctypes.byref(h)):
        sys.exit(f"open storage failed: error {lib.GetCascError()}")
    os.makedirs(out, exist_ok=True)
    ok = bad = 0
    for fid in ids:
        dst = os.path.join(out, f"{fid}.blp")
        if os.path.exists(dst):
            ok += 1; continue
        f = ctypes.c_void_p()
        if not lib.CascOpenFile(h, ctypes.c_void_p(fid), 0xFFFFFFFF, 3, ctypes.byref(f)):
            print(f"{fid}: open failed {lib.GetCascError()}"); bad += 1; continue
        size = lib.CascGetFileSize(f, None)
        if size == 0xFFFFFFFF:  # in the index but not stored locally (not downloaded)
            print(f"{fid}: not available locally"); bad += 1; lib.CascCloseFile(f); continue
        buf = ctypes.create_string_buffer(size)
        n = ctypes.c_uint32()
        if lib.CascReadFile(f, buf, size, ctypes.byref(n)) and n.value == size:
            open(dst, 'wb').write(buf.raw); ok += 1
        else:
            print(f"{fid}: read failed {lib.GetCascError()} ({n.value}/{size})"); bad += 1
        lib.CascCloseFile(f)
    print(f"extracted {ok}, failed {bad}")

if __name__ == '__main__':
    main()
