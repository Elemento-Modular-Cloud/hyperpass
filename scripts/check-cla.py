#!/usr/bin/env python3
# Copyright (C) Elemento S.r.l.
#
# Check that every GitHub user who authored or committed a pull-request
# change has signed the Elemento CLA (cla/SIGNERS on the PR head).

"""Verify pull-request contributors have signed the Elemento CLA."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.github.com"
SIGNERS_PATH = "cla/SIGNERS"
BOT_ALLOWLIST = {
    "dependabot[bot]",
    "github-actions[bot]",
    "renovate[bot]",
    "pre-commit-ci[bot]",
    "web-flow",
}
ORG_ASSOCIATIONS = {"OWNER", "MEMBER"}


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(1)


def request(url: str, token: str, accept: str = "application/vnd.github+json") -> tuple[int, bytes, str]:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": accept,
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "elemento-cla-check",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, resp.read(), resp.headers.get("Link", "")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read(), ""


def paginated(url: str, token: str) -> list[dict]:
    items: list[dict] = []
    while url:
        status, body, link = request(url, token)
        if status != 200:
            fail(f"GitHub API error {status} for {url}: {body.decode('utf-8', 'replace')}")
        payload = json.loads(body.decode("utf-8"))
        if not isinstance(payload, list):
            fail(f"Unexpected GitHub API payload for {url}")
        items.extend(payload)
        url = next_link(link)
    return items


def next_link(link_header: str) -> str:
    for part in link_header.split(","):
        section = part.strip()
        if 'rel="next"' in section:
            start = section.find("<") + 1
            end = section.find(">")
            return section[start:end]
    return ""


def parse_signers(text: str) -> set[str]:
    signers: set[str] = set()
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        signers.add(line.lstrip("@").lower())
    return signers


def load_signers(repo: str, sha: str, token: str) -> set[str]:
    encoded = urllib.parse.quote(SIGNERS_PATH)
    url = f"{API}/repos/{repo}/contents/{encoded}?ref={urllib.parse.quote(sha)}"
    status, body, _ = request(url, token, accept="application/vnd.github.raw")
    if status == 404:
        print(f"::warning::{SIGNERS_PATH} not found on {sha}; treating signer list as empty")
        return set()
    if status != 200:
        fail(f"Failed to read {SIGNERS_PATH} at {sha}: HTTP {status}: {body.decode('utf-8', 'replace')}")
    return parse_signers(body.decode("utf-8"))


def commit_logins(commit: dict) -> tuple[set[str], list[str]]:
    logins: set[str] = set()
    missing: list[str] = []
    sha = commit.get("sha", "?")[:12]
    for role in ("author", "committer"):
        account = commit.get(role) or {}
        login = account.get("login")
        if login:
            logins.add(login)
            continue
        git_user = (commit.get("commit") or {}).get(role) or {}
        name = git_user.get("name") or "unknown"
        email = git_user.get("email") or "unknown"
        if email.endswith("@users.noreply.github.com") or name == "GitHub":
            continue
        missing.append(f"{sha} {role} {name} <{email}>")
    return logins, missing


def main() -> int:
    token = os.environ.get("GITHUB_TOKEN", "")
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    head_repo = os.environ.get("PR_HEAD_REPO", "") or repo
    pr_number = os.environ.get("PR_NUMBER", "")
    head_sha = os.environ.get("PR_HEAD_SHA", "")
    pr_author = os.environ.get("PR_AUTHOR", "")
    association = os.environ.get("PR_AUTHOR_ASSOCIATION", "")

    if not all([token, repo, pr_number, head_sha]):
        fail("GITHUB_TOKEN, GITHUB_REPOSITORY, PR_NUMBER, and PR_HEAD_SHA are required")

    signers = load_signers(head_repo, head_sha, token)
    commits = paginated(f"{API}/repos/{repo}/pulls/{pr_number}/commits?per_page=100", token)

    unsigned: set[str] = set()
    missing_accounts: list[str] = []
    checked: set[str] = set()

    for commit in commits:
        logins, missing = commit_logins(commit)
        missing_accounts.extend(missing)
        for login in logins:
            key = login.lower()
            if key in checked:
                continue
            checked.add(key)
            if login in BOT_ALLOWLIST or key in {bot.lower() for bot in BOT_ALLOWLIST}:
                continue
            if key in signers:
                continue
            if login == pr_author and association in ORG_ASSOCIATIONS:
                continue
            unsigned.add(login)

    if missing_accounts:
        print("Commits are not linked to a GitHub account:")
        for item in missing_accounts:
            print(f"  - {item}")
        print("Use an email associated with your GitHub account, then re-push.")
        return 1

    if unsigned:
        names = ", ".join(sorted(unsigned, key=str.lower))
        print(f"The following GitHub users have not signed the Elemento CLA: {names}")
        print("Read docs/legal/CLA.md and add your username to cla/SIGNERS in this pull request.")
        return 1

    print("All pull request contributors have signed the Elemento CLA.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
