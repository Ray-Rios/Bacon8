#!/usr/bin/env python3
"""Package a Bacon8 plugin release from its git release branch, for the Bacon Store.

    python3 scripts/release/package_plugin.py bacon_world 1.0.0            # package an existing branch
    python3 scripts/release/package_plugin.py bacon_world 1.0.0 --cut main # first create the branch at main
    python3 scripts/release/package_plugin.py rays_space_sim 0.4.0 --notes "Holo-sim fixes"

What it does (BACON8.md §8 "Plugins for sale", BaconStore.Store.Releases):

* finds the plugin's repository: the hub's own for a plugin the hub ships (plugins/bacon_world is
  tracked by the hub), or the plugin's own nested repository for a private one
  (plugins/rays_space_sim/.git);
* checks that the branch release/<plugin>/<version> exists there (with --cut <ref>, creates it at
  <ref> first, refusing if it already exists); the version must match the plugin's
  `use Bacon8.Plugin, version: ...` on that branch;
* archives the plugin's folder AS COMMITTED ON THAT BRANCH (`git archive`, never the working tree:
  uncommitted work, gitignored files, models, secrets files and nested repositories stay out),
  under a top folder named after the plugin, so a buyer unzips it into their hub's plugins/;
* refuses if anything in it looks like a secret (secrets.yaml, .env, keys, certificates);
* adds RELEASE.json (plugin, version, branch, commit, built_at, notes) and writes
  tmp/releases/<plugin>-<version>.zip, printing its SHA-256.

Upload the zip on the product's admin page (/admin/bacon_store/products, "Download files"): the
store recognises it as a release of that branch and commit.

Needs git and Python 3.8+. It only reads the repository (and creates a branch with --cut); it
builds nothing and pushes nothing.
"""
import argparse
import datetime as dt
import fnmatch
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import zipfile

SECRET_PATTERNS = ["*secrets.yaml", "*secrets.yml", ".env", ".env.*", "*.key", "*.pem", "*.p12", "*.pfx", "*.crt", "id_rsa*", "*.sqlite", "*.db"]
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?$")
SLUG_RE = re.compile(r"^[a-z][a-z0-9_]*$")


def git(repo, *args, binary=False):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True)
    if r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed in {repo}: {r.stderr.decode(errors='replace').strip()}")
    return r.stdout if binary else r.stdout.decode().strip()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("plugin", help="the plugin's slug (its folder under plugins/)")
    ap.add_argument("version", help="the release's version, like 1.0.0")
    ap.add_argument("--hub", default=".", help="the hub's repository root (default: here)")
    ap.add_argument("--cut", metavar="REF", help="create the release branch at REF first (a commit, tag or branch)")
    ap.add_argument("--notes", default="", help="release notes for the store's records")
    ap.add_argument("--out", default="tmp/releases", help="where to write the zip (default tmp/releases, gitignored)")
    a = ap.parse_args()

    if not SLUG_RE.match(a.plugin):
        raise SystemExit("The plugin is its folder's name: lowercase letters, digits and underscores.")
    if not VERSION_RE.match(a.version):
        raise SystemExit("A version looks like 1.0.0 (or 1.0.0-beta.1).")

    hub = os.path.abspath(a.hub)
    folder = os.path.join(hub, "plugins", a.plugin)
    if not os.path.isdir(folder):
        raise SystemExit(f"No plugin folder {folder}.")

    # a private plugin is its own repository; a shipped one is a subtree of the hub's
    private = os.path.exists(os.path.join(folder, ".git"))
    repo, subtree = (folder, "") if private else (hub, f"plugins/{a.plugin}")
    branch = f"release/{a.plugin}/{a.version}"

    exists = subprocess.run(["git", "-C", repo, "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}"], capture_output=True).returncode == 0
    if a.cut and exists:
        raise SystemExit(f"{branch} already exists; a release branch is never moved. Use a new version.")
    if not a.cut and not exists:
        raise SystemExit(f"No branch {branch} in {repo}. Cut it with --cut <commit>, from committed, tested work.")

    # the plugin's declared version must match, where the branch is (or will be)
    at = a.cut or f"refs/heads/{branch}"
    plugin_ex = f"{subtree + '/' if subtree else ''}lib/{a.plugin}/plugin.ex"
    src = subprocess.run(["git", "-C", repo, "show", f"{at}:{plugin_ex}"], capture_output=True)
    if src.returncode == 0:
        m = re.search(rb'version:\s*"([^"]+)"', src.stdout)
        if m and m.group(1).decode() != a.version:
            raise SystemExit(f"{plugin_ex} at {at} says version {m.group(1).decode()}, not {a.version}. Bump it in a commit, then cut the branch there.")

    if a.cut:
        git(repo, "branch", branch, a.cut)
        print(f"created {branch} at {a.cut}")

    commit = git(repo, "rev-parse", f"refs/heads/{branch}")
    treeish = f"{branch}:{subtree}" if subtree else branch

    data = git(repo, "archive", "--format=zip", f"--prefix={a.plugin}/", treeish, binary=True)
    src_zip = zipfile.ZipFile(io.BytesIO(data))
    names = src_zip.namelist()

    risky = [n for n in names if any(fnmatch.fnmatch(os.path.basename(n), p) for p in SECRET_PATTERNS)]
    if risky:
        raise SystemExit("Refusing: these look like secrets and must not ship:\n  " + "\n  ".join(risky))

    manifest = {
        "plugin": a.plugin,
        "version": a.version,
        "branch": branch,
        "commit": commit,
        "built_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "notes": a.notes,
        "files": len([n for n in names if not n.endswith("/")]),
    }

    os.makedirs(os.path.join(hub, a.out), exist_ok=True)
    out = os.path.join(hub, a.out, f"{a.plugin}-{a.version}.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for info in src_zip.infolist():
            z.writestr(info, src_zip.read(info.filename))
        z.writestr("RELEASE.json", json.dumps(manifest, indent=2))

    sha = hashlib.sha256(open(out, "rb").read()).hexdigest()
    print(f"{out}\n  {manifest['files']} files from {branch} @ {commit[:12]}\n  sha256 {sha}\n  {os.path.getsize(out):,} bytes")


if __name__ == "__main__":
    sys.exit(main())
