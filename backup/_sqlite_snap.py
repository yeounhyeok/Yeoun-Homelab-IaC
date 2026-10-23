#!/usr/bin/env python3
"""Online-consistent SQLite snapshots -> one tar.gz on stdout.
usage: sudo python3 _sqlite_snap.py 'label=/path/db.sqlite[|table1,table2]' ...
 - uses sqlite3 backup API (safe while the app is running, WAL-aware)
 - optional |tables are emptied in the COPY only (e.g. uptime-kuma heartbeat history) then VACUUMed
 - runs pragma integrity_check on each copy; non-ok => exit 3 (stderr says which)
Run via:  ssh host "sudo -n python3 - args" < _sqlite_snap.py   (script on stdin)
"""
import os, shutil, sqlite3, sys, tarfile, tempfile

tmp = tempfile.mkdtemp(prefix="sqlsnap-")
rc = 0
out = tarfile.open(fileobj=sys.stdout.buffer, mode="w|gz")
try:
    for spec in sys.argv[1:]:
        label, rest = spec.split("=", 1)
        path, _, prune = rest.partition("|")
        dst = os.path.join(tmp, label + ".sqlite3")
        try:
            s = sqlite3.connect(path, timeout=60)
            d = sqlite3.connect(dst)
            s.backup(d)
            s.close()
            if prune:
                have = {r[0] for r in d.execute("select name from sqlite_master where type='table'")}
                for t in prune.split(","):
                    if t in have:
                        d.execute('delete from "%s"' % t)
                d.commit()
                d.execute("vacuum")
            r = d.execute("pragma integrity_check").fetchone()[0]
            n = d.execute("select count(*) from sqlite_master where type='table'").fetchone()[0]
            d.close()
            sys.stderr.write("snap %s: integrity=%s tables=%d size=%d\n" % (label, r, n, os.path.getsize(dst)))
            if r != "ok" or n == 0:
                rc = 3
                continue
            out.add(dst, arcname=label + ".sqlite3")
        except Exception as e:
            sys.stderr.write("snap %s: ERROR %s\n" % (label, e))
            rc = 3
finally:
    out.close()
    shutil.rmtree(tmp, ignore_errors=True)
sys.exit(rc)
