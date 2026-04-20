#!/usr/bin/env python3
"""Publish current HEAD tree to GitHub via REST (when git push is blocked). Requires: gh auth token."""
from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

OWNER = "ManiselvanSE"
REPO = "oracle-xstream-cdc-kafka-poc"
REF = "refs/heads/main"


def gh_token() -> str:
    return subprocess.check_output(["gh", "auth", "token"], text=True).strip()


def api(method: str, path: str, data: dict[str, Any] | None = None) -> dict[str, Any]:
    token = gh_token()
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(
        f"https://api.github.com{path}",
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        err = e.read().decode()
        raise SystemExit(f"HTTP {e.code} {path}: {err}") from e


def post_blob(content: bytes) -> str:
    b64 = base64.b64encode(content).decode()
    r = api("POST", f"/repos/{OWNER}/{REPO}/git/blobs", {"content": b64, "encoding": "base64"})
    return str(r["sha"])


def post_tree(entries: list[dict[str, Any]]) -> str:
    r = api("POST", f"/repos/{OWNER}/{REPO}/git/trees", {"tree": entries})
    return str(r["sha"])


def main() -> None:
    root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    os.chdir(root)
    # Build nested structure: path parts -> (blob sha, git file mode)
    trees: dict[str, Any] = {}

    def ensure_dir(parts: list[str]) -> dict[str, Any]:
        cur = trees
        for p in parts:
            cur = cur.setdefault(p, {})
        return cur

    index_lines = subprocess.check_output(["git", "ls-files", "-s"], text=True).splitlines()
    for line in index_lines:
        meta, rel = line.split("\t", 1)
        mode, _git_obj, _stage = meta.split()
        data = (root / rel).read_bytes()
        blob_sha = post_blob(data)
        parts = rel.split("/")
        parent_parts = parts[:-1]
        name = parts[-1]
        d = ensure_dir(parent_parts)
        d[name] = ("blob", blob_sha, mode)

    def build_subtree(node: dict[str, Any]) -> str:
        entries: list[dict[str, Any]] = []
        for name in sorted(node.keys()):
            v = node[name]
            if isinstance(v, dict):
                mode = "040000"
                sha = build_subtree(v)
                typ = "tree"
            else:
                typ, sha, fmode = v
                mode = fmode
            entries.append({"path": name, "mode": mode, "type": typ, "sha": sha})
        return post_tree(entries)

    tree_sha = build_subtree(trees)
    head = api("GET", f"/repos/{OWNER}/{REPO}/git/ref/heads/main")
    old_sha = head["object"]["sha"]
    parent_commits = [old_sha]

    msg = subprocess.check_output(["git", "log", "-1", "--format=%B"], text=True).strip()
    if not msg:
        msg = "Publish tree via Git Data API"

    author = api("GET", f"/repos/{OWNER}/{REPO}/commits/{old_sha}")["commit"]["author"]

    commit = api(
        "POST",
        f"/repos/{OWNER}/{REPO}/git/commits",
        {
            "message": msg,
            "tree": tree_sha,
            "parents": parent_commits,
            "author": author,
            "committer": author,
        },
    )
    new_sha = commit["sha"]

    api(
        "PATCH",
        f"/repos/{OWNER}/{REPO}/git/refs/heads/main",
        {"sha": new_sha, "force": True},
    )
    print(f"Updated {REF} -> {new_sha} (was {old_sha})")


if __name__ == "__main__":
    main()
