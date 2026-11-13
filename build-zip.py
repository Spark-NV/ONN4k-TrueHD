#!/usr/bin/env python3
# Zips up module/ into something you can flash in Magisk.
import os, zipfile

root = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(root, 'module')
prop = dict(l.strip().split('=', 1) for l in open(os.path.join(src, 'module.prop')) if '=' in l)
out = os.path.join(root, f"onn-truehd-passthrough-{prop['version']}.zip")

with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for r, _, fs in sorted(os.walk(src)):
        for f in sorted(fs):
            path = os.path.join(r, f)
            info = zipfile.ZipInfo(os.path.relpath(path, src), (2026, 11, 13, 0, 0, 0))
            info.external_attr = (0o755 if f.endswith(('.sh', 'update-binary')) else 0o644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, open(path, 'rb').read())
print(out)
