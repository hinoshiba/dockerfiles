# Package install "cooldown" (supply-chain hardening)

To reduce exposure to supply-chain attacks — where a freshly published, and
possibly compromised, package version is pulled in the moment it appears — all
third-party package resolution in these images only adopts releases that have
been **public for at least 14 days** (`COOLDOWN_DAYS`).

A two-week quarantine gives the wider community time to detect and pull a
malicious release before it lands in our images.

## What is covered

| Ecosystem | Where | Mechanism |
| --- | --- | --- |
| PyPI (pip) | `workbench`, `claude-codex`, `python`, `cvemaker`, `templates/python` | `cooldown-pip` resolves each package to the newest stable release uploaded ≥ `COOLDOWN_DAYS` ago and pins it before `pip install`. |
| npm | `workbench`, `claude-codex` | `npm install --before=<today − COOLDOWN_DAYS>` so only versions published before the cutoff are eligible. |
| vim plugins (git) | `workbench` | `vim-plugin-cooldown` rolls every NeoBundle plugin back to the newest commit that is ≥ `COOLDOWN_DAYS` days old. |

`cooldown-pip` and `vim-plugin-cooldown` live in
`dockerfiles/workbench/scripts/`. `cooldown-pip` is duplicated into each image
build context (`claude-codex`, `python`, `cvemaker`) because every image is
built with its own Docker context directory; keep the copies in sync.

## Tuning the window

Every image accepts a `COOLDOWN_DAYS` build argument (default `14`):

```sh
docker build --build-arg COOLDOWN_DAYS=21 ...
```

`cooldown-pip` also reads `COOLDOWN_DAYS` from the environment and accepts
`--days N`; `vim-plugin-cooldown` reads `COOLDOWN_DAYS` from the environment.

## Out of scope / known limitations

- **Transitive pip dependencies** are resolved by pip in the usual way; the
  cooldown pins the explicitly requested (direct) packages.
- **Go modules** and **Cargo crates** (used in the `go`/`rust` templates) have
  no native release-age filter, so they are not currently cooled down.
- **apt** packages come from the distribution archive, which already applies
  its own review/stabilisation process.
