# Package install "cooldown" (supply-chain hardening)

To reduce exposure to supply-chain attacks — where a freshly published, and
possibly compromised, package version is pulled in the moment it appears — all
third-party package resolution in these images only adopts releases that have
been **public for at least 14 days** (`COOLDOWN_DAYS`).

A two-week quarantine gives the wider community time to detect and pull a
malicious release before it lands in our images. Each ecosystem is handled with
its **native** mechanism wherever one exists, so there is no bespoke tooling to
maintain.

## What is covered

| Ecosystem | Where | Mechanism |
| --- | --- | --- |
| PyPI (pip) | `workbench`, `claude-codex`, `python`, `cvemaker`, `templates/python` | `pip install --uploaded-prior-to P<COOLDOWN_DAYS>D` — pip's native flag (ISO-8601 duration) limits the **whole** resolution, including transitive dependencies, to releases uploaded at least `COOLDOWN_DAYS` days ago. |
| npm | `workbench`, `claude-codex` | `npm install --before=<today − COOLDOWN_DAYS>` — npm's native flag; only versions published before the cutoff are eligible. |
| vim plugins (git) | `workbench` | `vim-plugin-cooldown` rolls every NeoBundle plugin back to the newest commit that is ≥ `COOLDOWN_DAYS` days old (git has no native release-age flag). |

`pip` self-upgrade is bootstrapped first (`pip install --upgrade pip`) so that
the resolver is new enough to understand `--uploaded-prior-to`; the subsequent
install then re-pins pip itself within the cooldown window.

`vim-plugin-cooldown` lives in `dockerfiles/workbench/scripts/`.

## Tuning the window

Every image accepts a `COOLDOWN_DAYS` build argument (default `14`):

```sh
docker build --build-arg COOLDOWN_DAYS=21 ...
```

The project templates accept it as a make variable: `make d-test COOLDOWN_DAYS=21`.

## Out of scope

- **Go modules** and **Cargo crates** (used in the `go`/`rust` templates) have
  no native release-age filter — Go's is still a
  [proposal](https://github.com/golang/go/issues/76485) and Cargo only has a
  third-party wrapper — so they are intentionally **not** cooled down here.
  Their lock files (`go.sum`, `Cargo.lock`) already pin exact versions
  (including transitive ones), so new releases are never pulled in implicitly.
  Revisit once upstream ships native support.
- **apt** packages come from the distribution archive, which already applies
  its own review/stabilisation process.
