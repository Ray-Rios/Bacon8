import os, sys, shutil, time
def size(p):
    t = 0
    for root, dirs, files in os.walk(p, onerror=lambda e: None):
        for f in files:
            try: t += os.lstat(os.path.join(root, f)).st_size
            except OSError: pass
    return t
out = open(r'C:\Bacon8\tmp\disk.txt', 'w')
u = shutil.disk_usage('C:\\'); out.write(f'C: free {u.free/1e9:.1f} GB of {u.total/1e9:.0f}\n'); out.flush()
def scan(base, depth, minsz):
    try: ents = [os.path.join(base, e) for e in os.listdir(base)]
    except OSError: return
    rows = []
    for e in ents:
        if os.path.isdir(e) and not os.path.islink(e): rows.append((size(e), e))
    rows.sort(reverse=True)
    for s, e in rows:
        if s < minsz: break
        out.write(f'{"  "*(3-depth)}{s/1e9:8.2f} GB  {e}\n'); out.flush()
        if depth > 1: scan(e, depth - 1, minsz * 2)
recent = []
scan(r'C:\Bacon8', 3, 1e9)
out.write('--- files changed in the last 3 days over 200 MB\n')
cut = time.time() - 3 * 86400
for root in [r'C:\Bacon8', os.path.expanduser('~'), r'C:\ProgramData\Epic', r'C:\Windows\Temp']:
    for r, d, fs in os.walk(root, onerror=lambda e: None):
        for f in fs:
            p = os.path.join(r, f)
            try: st = os.lstat(p)
            except OSError: continue
            if st.st_size > 2e8 and st.st_mtime > cut: recent.append((st.st_size, p))
recent.sort(reverse=True)
for s, p in recent[:60]: out.write(f'{s/1e9:8.2f} GB  {p}\n')
out.write('--- outside: user folders\n')
for p in [os.path.expanduser('~/AppData/Local/Temp'), os.path.expanduser('~/AppData/Local/UnrealEngine'), os.path.expanduser('~/AppData/Local/Docker'), r'C:\ProgramData\Docker', os.path.expanduser('~/AppData/Local/CrashDumps'), os.path.expanduser('~/AppData/Roaming/Godot')]:
    if os.path.exists(p): out.write(f'{size(p)/1e9:8.2f} GB  {p}\n'); out.flush()
out.write('DONE\n'); out.close()
