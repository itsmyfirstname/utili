---
description: Local-only PR review — report critical/high bugs and vulnerabilities to the terminal only
argument-hint: "<PR-URL>"
---
Perform a **local-only** review of the pull request at: $1

## Hard constraints

- **Read-only.** Never edit, create, or delete any file. Never commit, push,
  merge, or post anything to GitHub.
- **gh CLI** is the only tool for talking to GitHub, and only read
  subcommands are allowed: `gh pr view`, `gh pr diff`, `gh pr checks`,
  `gh run list`, `gh run view`, `gh repo view`, and `gh api <GET route>`
  (no `-X POST/PUT/PATCH/DELETE`, no `-f`/`-F` fields). Forbidden: `gh pr
  merge`, `gh pr close`, `gh pr comment`, `gh pr review`, `gh pr edit`,
  `gh pr update-branch`, `gh issue` writes, `gh release` writes, and any
  other gh command that mutates state. No curl or web requests to GitHub.
- **Local git** is read-only: `git diff`, `git show`, `git grep`, `git log`,
  `git cat-file`, `git status`. Never check out, create branches, commit,
  rebase, or modify the working tree. The only exception is the
  conditional fetch in step 2.
- **rg/grep** search the working tree. In the common case you are checked
  out on the PR branch, so the working tree is the head and rg/grep are
  valid. When HEAD is not the head OID, search with
  `git grep <pattern> <headRefOid>` instead.
- **Output goes to the terminal only** (your reply). The report is never
  posted, commented, or saved.

## Step 1 — Validate the URL and resolve the PR

$1 must be a full http(s) URL to a pull request. If it is missing or not a
PR URL, stop and ask the user for the full PR URL. Do not guess a repo.

Run `gh pr view <url> --json number,title,state,baseRefName,headRefName,headRefOid,additions,deletions,files`.
If this fails, stop and report the error. Record: PR number, title, state,
base branch, head OID.

## Step 2 — Pin the review to OIDs

From the repository the URL points at (or with the full
`repos/<owner>/<repo>` route), get the merge-base exactly as GitHub
computes it:

```bash
gh api repos/<owner>/<repo>/compare/<baseRefName>...<headRefName> \
  --jq .merge_base_commit.sha
```

Make sure the head OID is in the local object store. This is a no-op when
you are checked out on the PR branch; the fetch only runs otherwise and
stores the head as the remote-tracking ref `origin/pr-<number>/head` (no
local branch, nothing to clean up):

```bash
git cat-file -e <headRefOid>^{commit} || git fetch origin pull/<number>/head
```

From here on, pin everything to the head OID and the merge-base OID. Every
line reference in the report must be valid against the head OID.

## Step 3 — Review the diff

- `git diff <merge-base>...<headRefOid> --stat`, then per-file diffs.
- Read whole files where a hunk needs surrounding context:
  `git show <headRefOid>:<path>`. For the pre-PR version of a file, use
  the merge-base the same way.
- Search the head with `git grep <pattern> <headRefOid>`; rg/grep on the
  working tree is fine when HEAD == headRefOid.
- You may run the project's existing test suite or type checker in the
  working tree to confirm a suspected finding, but only when HEAD ==
  headRefOid, so it is actually testing the head. Never modify tracked
  files to test a theory.

Hunt, in this order:
1. **Security** — authn/authz gaps, injection, secrets in code or logs,
   missing input validation, unsafe deserialization, SSRF/path traversal.
2. **Correctness** — logic errors, state corruption, error handling that
   swallows or misreports failures, races on shared state.
3. **Data integrity** — non-transactional multi-statement writes, constraint
   violations, migration mismatches.
4. **Contract breaks** — changed response shapes or status codes that break
   existing clients.

## Step 4 — Severity gate (critical and high only)

Report a finding **only** if it is critical or high:

- **Critical** — actively exploitable vulnerability (auth bypass, injection,
  RCE, secret exposure), silent data loss or corruption, or a guaranteed
  crash of a primary flow.
- **High** — wrong behavior in a primary flow under realistic conditions, a
  security weakness with high impact behind a specific condition, a broken
  API contract, or a race that corrupts shared state.

Every finding must state a **concrete trigger** — the inputs or steps that
reproduce it. If you cannot state a trigger, the finding does not meet the
bar. Drop it. Do not report style, naming, performance nits, missing tests,
speculative risks, or improvement suggestions, at any severity.

## Step 5 — Report (terminal only)

Output exactly this shape as your reply:

```
PR <number>: <title>  (<state>)
Head: <head OID>   Base: <baseRefName> @ <merge-base OID>
Diff: <N> files, +<additions> / -<deletions>

VERDICT: <"No critical or high findings." | "N finding(s): X critical, Y high.">

## Findings

### [<CRITICAL|HIGH>] <short name>
- Where: <file> L<start>-L<end> (endpoint/route if relevant)
- What: <2-4 sentences, concrete>
- Trigger: <exact inputs or steps that reproduce it>
- Impact: <who or what is harmed, and under what conditions>
- Evidence: <the offending lines, quoted>
- Fix: <one line>
```

Repeat the finding block above for each finding. If there are none, write
"None." under Findings. Print the finished report to the terminal as your
reply — save nothing, post nothing.
