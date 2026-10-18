"""Fetch datasets: `fetch.py list` | `fetch.py get <key>|all [--include-large]`.

Files land in datasets/raw/<type>-<id>/ with a manifest.json (name, size, hash)
that validate.py re-checks. Archives are extracted into <dir>/extracted/.
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass, replace
from pathlib import Path
from urllib.parse import quote

import requests

from registry import BY_KEY, SOURCES, Source

ROOT = Path(__file__).parent
RAW = ROOT / "raw"
WORKERS = 6
UA = {"User-Agent": "Mozilla/5.0 (dubhacks-datasets)"}


@dataclass(frozen=True)
class RemoteFile:
    name: str  # path relative to the source dir
    size: int
    algo: str  # "md5" or "sha256"
    digest: str
    url: str


def source_dir(src: Source) -> Path:
    return RAW / src.dirname


def hash_file(path: Path, algo: str) -> str:
    """Hex digest of a file, read in 1 MiB chunks."""
    h = hashlib.new(algo)
    with path.open("rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def list_zenodo(src: Source) -> list[RemoteFile]:
    """File list + md5 from the Zenodo REST API."""
    r = requests.get(f"https://zenodo.org/api/records/{src.record_id}", headers=UA, timeout=60)
    r.raise_for_status()
    out = []
    for f in r.json()["files"]:
        algo, digest = f["checksum"].split(":", 1)
        url = f"https://zenodo.org/records/{src.record_id}/files/{quote(f['key'])}?download=1"
        out.append(RemoteFile(f["key"], f["size"], algo, digest, url))
    return sorted(out, key=lambda f: f.name)


def list_mendeley(src: Source) -> list[RemoteFile]:
    """File list + sha256 from Mendeley's public API; unnamed folders become label dirs."""
    r = requests.get(f"https://data.mendeley.com/public-api/datasets/{src.record_id}", headers=UA, timeout=60)
    r.raise_for_status()
    files = r.json()["files"]
    counts: dict[str, int] = {}
    for f in files:
        counts[f["folder_id"]] = counts.get(f["folder_id"], 0) + 1
    out = []
    for f in files:
        cd = f["content_details"]
        label = src.folder_labels_by_count.get(counts[f["folder_id"]])
        name = f"{label}/{f['filename']}" if label else f["filename"]
        out.append(RemoteFile(name, cd["size"], "sha256", cd["sha256_hash"], cd["download_url"]))
    return sorted(out, key=lambda f: f.name)


def list_github_raw(src: Source) -> list[RemoteFile]:
    """Direct URLs with no published checksum (digest filled in after download)."""
    return [RemoteFile(u.rsplit("/", 1)[1], -1, "sha256", "", u) for u in src.raw_urls]


def list_remote(src: Source) -> list[RemoteFile]:
    match src.type:
        case "zenodo":
            return list_zenodo(src)
        case "mendeley":
            return list_mendeley(src)
        case _:
            return list_github_raw(src)


def looks_like_html(path: Path, content_type: str) -> bool:
    """True if a download is an HTML page (bot check / error) instead of data."""
    if "text/html" in content_type.lower():
        return True
    with path.open("rb") as f:
        head = f.read(512).lstrip().lower()
    return head.startswith((b"<!doctype html", b"<html"))


def download(rf: RemoteFile, dest: Path) -> str:
    """Download one file to dest. Returns 'ok', 'skipped' or raises. Idempotent via hash."""
    if rf.digest == "":  # no published checksum: trust an existing file
        if dest.exists():
            return "skipped"
    elif dest.exists() and dest.stat().st_size == rf.size and hash_file(dest, rf.algo) == rf.digest:
        return "skipped"
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_name(dest.name + ".part")
    last: Exception | None = None
    for _ in range(3):
        try:
            with requests.get(rf.url, headers=UA, stream=True, timeout=60) as r:
                r.raise_for_status()
                with part.open("wb") as f:
                    for chunk in r.iter_content(1 << 20):
                        f.write(chunk)
                ctype = r.headers.get("content-type", "")
            if not rf.name.lower().endswith((".html", ".htm")) and looks_like_html(part, ctype):
                raise ValueError(f"got HTML instead of data (content-type {ctype!r})")
            got = hash_file(part, rf.algo)
            if rf.digest and got != rf.digest:
                raise ValueError(f"{rf.algo} mismatch: expected {rf.digest}, got {got}")
            part.rename(dest)
            return "ok"
        except (requests.RequestException, ValueError) as e:
            last = e
    part.unlink(missing_ok=True)
    raise RuntimeError(f"{rf.name}: {last}")


def extract(archive: Path, out_dir: Path) -> None:
    """Extract .zip (zipfile) or .rar (bsdtar) into out_dir; skip if already populated."""
    if out_dir.exists() and any(out_dir.iterdir()):
        return
    out_dir.mkdir(parents=True, exist_ok=True)
    if archive.suffix.lower() == ".zip":
        with zipfile.ZipFile(archive) as z:
            z.extractall(out_dir)
    elif archive.suffix.lower() == ".rar":
        # bsdtar (libarchive, built into macOS) handles the RAR v6 method that 7zz 26.04 rejects.
        tool = shutil.which("bsdtar")
        if not tool:
            raise RuntimeError("bsdtar not found (ships with macOS)")
        subprocess.run([tool, "-xf", str(archive), "-C", str(out_dir)], check=True, capture_output=True)


def get_source(src: Source, include_large: bool) -> dict:
    """Fetch one source. Returns a summary row."""
    row = {"key": src.key, "files": 0, "ok": 0, "skipped": 0, "failed": 0, "bytes": 0, "errors": []}
    d = source_dir(src)
    remote = list_remote(src)
    wanted = [f for f in remote if include_large or f.name not in src.large_files]
    d.mkdir(parents=True, exist_ok=True)
    def work(rf: RemoteFile) -> tuple[RemoteFile, str]:
        try:
            return rf, download(rf, d / rf.name)
        except Exception as e:  # noqa: BLE001 - report and continue with other files
            return rf, f"error: {e}"

    with ThreadPoolExecutor(WORKERS) as pool:
        for rf, res in pool.map(work, wanted):
            row["files"] += 1
            if res in ("ok", "skipped"):
                row[res] += 1
                row["bytes"] += (d / rf.name).stat().st_size
            else:
                row["failed"] += 1
                row["errors"].append(res)

    # Unpublished checksums/sizes: record what we observed so validate.py can re-check.
    wanted = [
        rf if rf.digest else replace(rf, size=(d / rf.name).stat().st_size, digest=hash_file(d / rf.name, rf.algo))
        for rf in wanted
        if rf.digest or (d / rf.name).exists()
    ]
    (d / "manifest.json").write_text(
        json.dumps({"source": src.key, "files": [asdict(f) for f in wanted],
                    "skipped_large": [f.name for f in remote if f.name in src.large_files and not include_large]}, indent=1)
    )
    for rf in wanted:
        p = d / rf.name
        if p.suffix.lower() in (".zip", ".rar") and p.exists():
            try:
                extract(p, d / "extracted" / p.stem)
            except Exception as e:  # noqa: BLE001
                row["errors"].append(f"extract {rf.name}: {e}")
    return row


def cmd_list() -> None:
    print(f"{'key':24} {'type':9} {'on disk':8} status")
    for s in SOURCES:
        on_disk = "yes" if s.type != "manual" and (source_dir(s) / "manifest.json").exists() else "-"
        print(f"{s.key:24} {s.type:9} {on_disk:8} {s.status}")


def cmd_get(target: str, include_large: bool) -> int:
    if target == "all":
        keys = [s.key for s in SOURCES if s.type != "manual"]
    elif target in BY_KEY and BY_KEY[target].type != "manual":
        keys = [target]
    elif target in BY_KEY:
        sys.exit(f"{target} is manual: {BY_KEY[target].status}\n{BY_KEY[target].url}")
    else:
        sys.exit(f"unknown key {target!r}; try `fetch.py list`")
    rows = []
    for k in keys:
        print(f"fetching {k} ...", flush=True)
        rows.append(get_source(BY_KEY[k], include_large))
    print(f"\n{'key':24} {'files':>6} {'ok':>6} {'skip':>6} {'fail':>6} {'MB':>9}")
    for r in rows:
        print(f"{r['key']:24} {r['files']:6} {r['ok']:6} {r['skipped']:6} {r['failed']:6} {r['bytes'] / 1e6:9.1f}")
        for e in r["errors"]:
            print(f"    ! {e}")
    return 1 if any(r["errors"] for r in rows) else 0


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    g = sub.add_parser("get")
    g.add_argument("target", help="source key or 'all'")
    g.add_argument("--include-large", action="store_true", help="also fetch large files (treadmill_data.mat)")
    a = p.parse_args()
    if a.cmd == "list":
        cmd_list()
    else:
        sys.exit(cmd_get(a.target, a.include_large))


if __name__ == "__main__":
    main()
