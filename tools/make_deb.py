#!/usr/bin/env python3
"""把单个 dylib 打包成 rootless iOS deb，不依赖 dpkg-deb。"""
import io
import os
import sys
import tarfile
import time


def tar_bytes(members, compression):
    bio = io.BytesIO()
    with tarfile.open(fileobj=bio, mode=f"w:{compression}") as tf:
        for arcname, data in members:
            info = tarfile.TarInfo(arcname)
            info.size = len(data)
            info.mtime = int(time.time())
            info.mode = 0o755 if arcname.startswith("./usr/lib") else 0o644
            tf.addfile(info, io.BytesIO(data))
    return bio.getvalue()


def ar_member(name, data):
    header = (f"{name:<16}{int(time.time()):<12}{0:<6}{0:<6}{100644:<8}{len(data):<10}`\n").encode()
    assert len(header) == 60, len(header)
    padded = data + (b"\n" if len(data) % 2 else b"")
    return header + padded


def build(control_path, dylib_path, out_path, dylib_install_name="usr/lib/TrollAutoClicker/TrollAutoClicker.dylib"):
    control = open(control_path, "rb").read()
    dylib = open(dylib_path, "rb").read()
    control_tar = tar_bytes([("./control", control)], "gz")
    data_tar = tar_bytes([("./" + dylib_install_name, dylib)], "xz")
    with open(out_path, "wb") as f:
        f.write(b"!<arch>\n")
        f.write(ar_member("debian-binary", b"2.0\n"))
        f.write(ar_member("control.tar.gz", control_tar))
        f.write(ar_member("data.tar.xz", data_tar))
    print("wrote", out_path, os.path.getsize(out_path), "bytes")


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    dylib = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "packages", "TrollAutoClicker.dylib")
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "packages", "com.trollautoclicker.tweak_1.0.0_iphoneos-arm64.deb")
    build(os.path.join(root, "control"), dylib, out)
