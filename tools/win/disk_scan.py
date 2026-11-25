# Disk report for C: (tools\win\disk_scan.cmd; writes C:\Bacon8\tmp\disk.txt and a dated copy, disk_<date>_<time>.txt,
# so the next run can be compared with this one). 2026-11-22: more places outside C:\Bacon8 (the Unreal engine's
# build folders, Zen's cache, Docker's and Claude's virtual disks, the page and hibernation files, the recycle bin),
# RaysSpaceSim broken down further, and C:\UnrealEngine among the places searched for recent big files.
import os, sys, shutil, time
H = os.path.expanduser('~')
def size(p):
    if os.path.isfile(p):
        try: return os.lstat(p).st_size
        except OSError: return 0
    t = 0
    for root, dirs, files in os.walk(p, onerror=lambda e: None):
        for f in files:
            try: t += os.lstat(os.path.join(root, f)).st_size
            except OSError: pass
    return t
stamp = time.strftime('%Y-%m-%d_%H%M')
out = open(r'C:\Bacon8\tmp\disk.txt', 'w')
def w(s): out.write(s + '\n'); out.flush()
u = shutil.disk_usage('C:\\'); w(f'{stamp}  C: free {u.free/1e9:.1f} GB of {u.total/1e9:.0f}')
def scan(base, depth, minsz, ind=0):
    try: ents = [os.path.join(base, e) for e in os.listdir(base)]
    except OSError: return
    rows = []
    for e in ents:
        if os.path.isdir(e) and not os.path.islink(e): rows.append((size(e), e))
    rows.sort(reverse=True)
    for s, e in rows:
        if s < minsz: break
        w(f'{"  "*ind}{s/1e9:8.2f} GB  {e}')
        if depth > 1: scan(e, depth - 1, minsz * 2, ind + 1)
w('--- C:\\Bacon8')
scan(r'C:\Bacon8', 3, 1e9)
w('--- RaysSpaceSim (unreal), deeper')
scan(r'C:\Bacon8\plugins\rays_space_sim\unreal', 4, 5e8)
w('--- outside C:\\Bacon8')
for p in [r'C:\UnrealEngine\Engine\Intermediate', r'C:\UnrealEngine\Engine\Saved', r'C:\UnrealEngine\Engine\DerivedDataCache',
          r'C:\UnrealEngine\Engine\Binaries', r'C:\UnrealEngine\.git',
          H + r'\AppData\Local\UnrealEngine', H + r'\AppData\Local\UnrealEngine\Common\Zen\Data',
          H + r'\AppData\Local\Docker', H + r'\AppData\Local\Docker\wsl\disk\docker_data.vhdx', r'C:\ProgramData\Docker',
          H + r'\AppData\Roaming\Claude\vm_bundles', H + r'\AppData\Local\Packages',
          H + r'\AppData\Local\Temp', r'C:\Windows\Temp', r'C:\$Recycle.Bin', H + r'\Downloads',
          H + r'\AppData\Local\NVIDIA\DXCache', H + r'\AppData\Local\CrashDumps', H + r'\AppData\Roaming\Godot',
          H + r'\.nuget', H + r'\AppData\Local\pip', H + r'\AppData\Local\npm-cache',
          r'C:\pagefile.sys', r'C:\hiberfil.sys', r'C:\swapfile.sys']:
    if os.path.exists(p): w(f'{size(p)/1e9:8.2f} GB  {p}')
w('--- files changed in the last 3 days over 200 MB')
cut = time.time() - 3 * 86400
recent = []
for root in [r'C:\Bacon8', r'C:\UnrealEngine', H, r'C:\ProgramData\Epic', r'C:\ProgramData\Docker', r'C:\Windows\Temp']:
    for r, d, fs in os.walk(root, onerror=lambda e: None):
        for f in fs:
            p = os.path.join(r, f)
            try: st = os.lstat(p)
            except OSError: continue
            if st.st_size > 2e8 and st.st_mtime > cut: recent.append((st.st_size, p))
recent.sort(reverse=True)
for s, p in recent[:80]: w(f'{s/1e9:8.2f} GB  {p}')
w('DONE')
out.close()
shutil.copy(r'C:\Bacon8\tmp\disk.txt', rf'C:\Bacon8\tmp\disk_{stamp}.txt')
