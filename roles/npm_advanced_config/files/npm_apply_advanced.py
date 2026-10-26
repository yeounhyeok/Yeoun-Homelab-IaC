#!/usr/bin/env python3
# usage: npm_apply_advanced.py <npm data dir> <proxy_host id>
# Sets proxy_host.advanced_config from <data>/advanced-<id>.conf and replaces the
# advanced block in nginx/proxy_host/<id>.conf. The rendered block sits between
# the default `location / {...}` and the trailing custom include (NPM template).
import re, shutil, sqlite3, sys
data, hid = sys.argv[1], int(sys.argv[2])
new = open(f"{data}/advanced-{hid}.conf").read().strip() + "\n"
db = f"{data}/database.sqlite"
c = sqlite3.connect(db)
cur = c.execute("select advanced_config from proxy_host where id=?", (hid,)).fetchone()[0] or ""
conf_p = f"{data}/nginx/proxy_host/{hid}.conf"
conf = open(conf_p).read()
m = re.search(r"(\n  location / \{.*?\n  \}\n)(.*?)(\n  include /data/nginx/custom/server_proxy\[\.\]conf;)", conf, re.S)
if not m:
    sys.exit("rendered conf layout not recognised")
rendered = "\n".join(("  " + l) if l.strip() else "" for l in new.rstrip("\n").split("\n"))
if cur == new and m.group(2) == rendered:
    print("OK"); sys.exit(0)
shutil.copy2(db, db + ".pre-advanced")
shutil.copy2(conf_p, conf_p + ".pre-advanced")
c.execute("update proxy_host set advanced_config=?, modified_on=datetime('now') where id=?", (new, hid))
c.commit()
open(conf_p, "w").write(conf[:m.start(2)] + rendered + conf[m.end(2):])
print("CHANGED")
