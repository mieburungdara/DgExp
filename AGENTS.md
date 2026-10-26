# AGENTS.md

Operating rules for AI coding assistants in this repository.

## Shell searches on Windows (Git Bash)

Never root a recursive shell search above this repository. Two shapes have cost
this machine real CPU: `find /`, and `grep -r <pattern> /c/Users/<name>` (or `~`).

- `/` in Git Bash is the MSYS root (`C:\Program Files\Git`), which contains `/proc`:
  a pseudo-filesystem rebuilt from the live process table, so it never caches.
  Measured here, every real subtree under `/` (11,462 entries) walks in ~2 s while
  `/proc` alone (2,243 entries) takes 42 s — one `find /` pins a whole core. It also
  cannot reach any project on this machine: drives are lazy automounts (`/c`, `/d`)
  that `ls /` does not even list.
- `grep -r` over a home directory is worse in wall-clock because it reads file
  *contents*: three such greps ran 18 minutes at 207–301 CPU-seconds each over
  AppData, caches, and `~/.qoder`, and never finished. Never use `~/.qoder` as a
  search root — those session transcripts are the developer's own data.

Rules:

- Prefer the agent's Glob/Grep tools (ripgrep, honours `.gitignore`) over shell
  searches.
- Scope a shell search to a real path inside this repo:
  `grep -rn "pattern" src --exclude-dir=node_modules`.
- Quote patterns — `-path '*foo*'`, not `-path *foo*` — and bound anything that
  could walk: `timeout 20 find …`.
- A shell killed on tool timeout does **not** take its MSYS children with it (no job
  object), so a timed-out search leaves an orphan burning CPU, and its pipe partner
  (`… | grep -v node_modules`) waits at 0% forever so the pipeline never dies on its
  own. Retrying with a different pattern multiplies full walks. If searches keep
  timing out, reap the leftovers (`Get-CimInstance Win32_Process -Filter
  "Name='grep.exe' OR Name='find.exe'"`, kill only those whose parent is gone) and
  fix the search root instead.
