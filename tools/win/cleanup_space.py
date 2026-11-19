# Space cleanups the owner OKd (2026-11-13): Unreal's dependency download cache, RaysSpaceSim's Visual Studio
# cache (only if VS is closed), and Temp files older than 3 days (anything locked is left).
import os, shutil, time, subprocess
log = open(r"C:\Bacon8\tmp\cleanup_space.txt", "w")
def w(s): log.write(s + "\n"); log.flush()
def size(p):
    t = 0
    for r, d, f in os.walk(p):
        for x in f:
            try: t += os.lstat(os.path.join(r, x)).st_size
            except OSError: pass
    return t
def onerr(func, path, exc):
    try:
        os.chmod(path, 0o666); func(path)
    except Exception:
        pass
free0 = shutil.disk_usage("C:\\").free
for p in [r"C:\UnrealEngine\.git\ue-gitdeps"]:
    if os.path.isdir(p):
        s = size(p); shutil.rmtree(p, onerror=onerr); w(f"{p}: {s/1e9:.1f} GB, gone: {not os.path.exists(p)}")
vs = subprocess.run(["tasklist", "/FI", "IMAGENAME eq devenv.exe"], capture_output=True, text=True).stdout
p = r"C:\Bacon8\plugins\rays_space_sim\unreal\.vs"
if "devenv.exe" in vs:
    w(f"{p}: left, Visual Studio is open")
elif os.path.isdir(p):
    s = size(p); shutil.rmtree(p, onerror=onerr); w(f"{p}: {s/1e9:.1f} GB, gone: {not os.path.exists(p)}")
T = os.path.join(os.environ["LOCALAPPDATA"], "Temp"); cut = time.time() - 3 * 86400; n = b = 0
for r, d, f in os.walk(T, topdown=False):
    for x in f:
        q = os.path.join(r, x)
        try:
            st = os.lstat(q)
            if st.st_mtime < cut: os.remove(q); n += 1; b += st.st_size
        except OSError: pass
    for x in d:
        try: os.rmdir(os.path.join(r, x))
        except OSError: pass
w(f"Temp: {n} files older than 3 days, {b/1e9:.1f} GB")
w(f"C: free {free0/1e9:.1f} -> {shutil.disk_usage('C:\\').free/1e9:.1f} GB")
w("DONE")
