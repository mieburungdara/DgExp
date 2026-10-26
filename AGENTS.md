# AGENTS.md

Operating rules for AI coding assistants in this repository.

## Shell searches on Windows (Git Bash)

Never run `find /` — or any search rooted at `/` — from Git Bash. `/` here is the
MSYS root (`C:\Program Files\Git`), which contains `/proc`: a pseudo-filesystem
rebuilt from the live process table, so it never caches. Measured on this machine,
every real subtree under `/` (11,462 entries) walks in ~2 s while `/proc` alone
(2,243 entries) takes 42 s — one `find /` pins a whole core for many minutes. It
also cannot reach any project on `C:` or `D:`, because drives are lazy automounts
(`/c`, `/d`) that `ls /` does not even list.

- Use the agent's Glob/Grep tools (ripgrep, honours `.gitignore`), or scope the
  command to a real path: `find src -name '*.js'`.
- Quote patterns — `-path '*foo*'`, not `-path *foo*` — and bound anything that
  could walk: `timeout 20 find …`.
- A shell killed on tool timeout does **not** take its MSYS children with it (no
  job object), so a timed-out search leaves an orphan burning CPU. Retrying it with
  a different pattern multiplies full walks; if searches keep timing out, reap the
  leftovers (`Get-CimInstance Win32_Process -Filter "Name='find.exe'"`) and fix the
  search root.
