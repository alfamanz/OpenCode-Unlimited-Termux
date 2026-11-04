# OpenCode-Unlimited — Termux port

**Gets you past OpenCode's free message limit, and tells you when it's back.**

Termux/Android port of [Tazmyan/OpenCode-Unlimited](https://github.com/Tazmyan/OpenCode-Unlimited).
The original is Windows/PowerShell; this is the same mechanism rewritten in bash + node, no PowerShell, no Windows APIs.

OpenCode gives you a fixed number of free messages per day and then shows:

```
You've used today's free messages. They reset at 2:00 AM - 10/27/2026
```

This tool checks whether that limit is still biting, gives you a fresh project identity when you need one, and can push OpenCode through a proxy if you want a different connection.

---

## Quick start

Native Termux (aarch64), one command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alfamanz/OpenCode-Unlimited-Termux/main/setup.sh)
```

It clones the repo to `~/.local/share/ocu-src`, then:

1. checks `opencode --version` — if v1 exists, it goes straight to `ocu install`
2. otherwise checks `opencode2 --version` — if v2 exists, same
3. if neither exists, asks whether to install **v1 (stable)** or **v2 (preview)**

The `ocu` plugin only loads in `opencode2` (v2), so pick 2 if you want the header rewrite. v1 still gets the CLI, just without the plugin.

After it finishes:

```bash
ocu status
ocu test -live
```

Manual steps are below if you want to see each part.

---

## Repo layout

```
ocu                     bash CLI, the whole tool
setup.sh                one-shot bootstrap: opencode2 (if missing) + ocu
setup/install-opencode.sh   OpenCode v2 installer for Termux (guysoft/opencode-termux)
lib/ocu-db.js           project id rotation + limit-row cleanup (node:sqlite)
lib/proxy-bridge.js     local SOCKS5/HTTP bridge for the app
plugin/unlimited-shield.js   opencode2 plugin, sets x-opencode-project
upstream/               original Windows implementation, kept for reference
README.md
```

---

## Before you start: OpenCode itself

`ocu` is not a standalone app — it patches OpenCode. The plugin targets **opencode2 (v2)**; the v1 `opencode` binary does not load it.

Check what you have:

```bash
command -v opencode  && opencode --version
command -v opencode2 && opencode2 --version
```

If v2 is missing, install it on native Termux (aarch64, no root) — `setup.sh` asks which version when neither exists:

```bash
bash /sdcard/opencode-install/install-opencode.sh --v2
```

That script comes from [guysoft/opencode-termux](https://github.com/guysoft/opencode-termux). It pulls the `opencode2-*-android-aarch64.zip` release asset and installs:

```
$PREFIX/bin/opencode2
$PREFIX/libexec/opencode2/opencode2.bin
$PREFIX/libexec/opencode2/libopentui.so
```

v1 and v2 install side by side — nothing is overwritten. The installer refuses proot/chroot and non-aarch64.

If the sdcard copy is gone, grab `install-opencode.sh` from that repo, then:

```bash
pkg install curl unzip ripgrep
bash install-opencode.sh --v2
```

Verify before touching `ocu`:

```bash
opencode2 --version
bash ocu install
```

---

## Install

```bash
git clone https://github.com/alfamanz/OpenCode-Unlimited-Termux.git
cd OpenCode-Unlimited-Termux
bash ocu install
```

Or from the sdcard copy:

```bash
bash /sdcard/ocu/ocu install
```

`/sdcard` is mounted noexec, so the installer copies the runtime to `~/.local/share/ocu`, deploys the plugin to `~/.config/opencode/plugin/`, writes the slash commands, and links `$PREFIX/bin/ocu`.

Requirements: Termux, `node` 22.5+ (for `node:sqlite`), `curl`, and root (KernelSU/`su`) only for `ocu rotate`.

---

## How to use it

### 1. You hit the limit

Change your internet connection first — VPN, hotspot, airplane-mode toggle, router restart. A new egress IP is what usually brings the messages back.

### 2. Check whether you're clear

```bash
ocu test -live
```

It asks the app for one tiny reply.

- `WORKING` — you're free to prompt again.
- `EMPTY` — the app is still blocked on this connection.

`ocu test` without `-live` is a free direct probe; it does not see your app quota.

### 3. Reset one project, not the whole install

```bash
ocu reset ~/projects/my-app
```

That project gets a fresh identity. Its sessions, messages and history stay where they are — only the id moves.

That's the whole workflow. Everything else is optional.

---

## Commands

| Command | What it does |
| --- | --- |
| `ocu install` | Deploy plugin, slash commands, identity, PATH link |
| `ocu status` | Project id, plugin, database, egress IP |
| `ocu id` | New project id, all projects move to fresh ids |
| `ocu id ~/projects/my-app` | New project id for that one folder |
| `ocu id ~/projects/my-app -Db` | Same, and rewrite that project's rows in the database |
| `ocu reset` | Rotates every project, clears the stale "out of messages" error |
| `ocu reset ~/projects/my-app` | Same, but only that folder |
| `ocu test` | Free check of the direct API. Fast, but it does not see your app quota. |
| `ocu test -live` | Real check through the app. Costs one message. |
| `ocu rotate` | Airplane mode on/off until the egress IP changes (root) |
| `ocu rotate 6` | Same, up to 6 attempts |
| `ocu on` / `ocu off` | Turn the plugin on or off |
| `ocu proxy set socks5://host:port` | Route OpenCode through a proxy |
| `ocu proxy off` | Back to a direct connection |
| `ocu proxy status` | Current upstream, bridge state, direct and proxied IP |
| `ocu run` | Run `opencode2` through the configured proxy |
| `ocu doctor` | Check node, sqlite, curl, plugin, identity |
| `ocu uninstall` | Remove plugin, slash commands, state |

Inside OpenCode's chat you get the same thing as slash commands:

```
/ocu
/ocu-test
/ocu-reset ~/projects/my-app
/ocu-id ~/projects/my-app
```

The two that rotate take an optional folder. Leave it out and every project moves to a fresh id.

---

## Connection rotation

`ocu rotate` toggles airplane mode through `su`:

```
airplane-mode enable   -> wait 3s
airplane-mode disable  -> wait 5s
check egress IP, repeat if unchanged
```

Defaults to 4 attempts. It stops as soon as the IP changes and prints the next step (`ocu reset`).

CGNAT will happily hand you the same public IP for hours. If `ocu rotate` never sees a change, move between Wi-Fi and mobile data, or put a VPN in front.

---

## Proxy

```bash
ocu proxy set 'socks5://user:pass@host:port'
ocu proxy status
ocu run
```

`ocu proxy set` tests the upstream before saving it. Dead host, wrong protocol or rejected credentials fail immediately and leave no state behind.

The bridge listens on `127.0.0.1:8899` and speaks SOCKS5 or HTTP upstream. `ocu run` exports `HTTPS_PROXY`/`ALL_PROXY` and execs `opencode2`; opening `opencode2` normally stays direct.

---

## "It says EMPTY but my messages work"

That's expected, and it's the one confusing part.

`ocu test` without `-live` sends a bare request to OpenCode's API. That endpoint answers `429` for anything that isn't the OpenCode app itself — same answer for a random project id, a valid key or no key at all. So it can't see your real quota.

The app is the only thing that knows. Use `ocu test -live` when it matters, or simply send a message and see if it lands.

---

## Sessions are safe

Your chats live in `opencode.db` (the active one on this build is `opencode-android-termux.db`), and rotating an id never deletes a row.

- The plugin only sets one header on outgoing requests.
- `id` and `reset` rewrite the project id on a project and its rows. Sessions, messages and history follow the new id and stay attached to their folder.
- `reset` also deletes the stored "you're out of messages" error rows, nothing else.
- Restarting the background service never touches sessions.

`ocu` detects the active database automatically. Override with `OPENCODE_DB=/path/opencode.db`.

After a `-Db` rotation, close and reopen `opencode2` — the running service keeps the old project id in memory.

---

## What changed from upstream

| Upstream (Windows) | This port (Termux) |
| --- | --- |
| `install.ps1`, `bin\opencode-unlimited.ps1` | single bash script `ocu`, no PowerShell |
| plugin directory `~/.config/opencode/plugins` | `~/.config/opencode/plugin` (singular — what opencode2 loads) |
| `%APPDATA%`, `Get-Command`, `Start-Process` | `$PREFIX/bin`, `command -v`, `nohup` |
| PATH via `[Environment]::SetEnvironmentVariable` | symlink `$PREFIX/bin/ocu`, noexec handling for `/sdcard` |
| fixed `opencode.db` path | auto-detects `opencode-android-termux.db`, honours `OPENCODE_DB` |
| `opencode service set env` for proxy | `ocu run` exports proxy env and execs the app |
| manual connection change | `ocu rotate` toggles airplane mode via root |
| upstream probe via `curl.exe` | `curl`, with fail-fast check before saving a proxy |
| `opencode api get /api/provider` for org id | direct probe against the gateway |

Plugin API target: opencode2 `2.0.0-android-termux.2` (`session.hook("model.request")` and `session.hook("http.request")`). The v1 `opencode` 1.17.9 binary does not load this plugin.

---

## Credits

- Original tool, mechanism and PowerShell implementation: [Tazmyan](https://github.com/Tazmyan).
- Termux port and maintenance: [alfamanz](https://github.com/alfamanz).

If you want the Windows version, use upstream — it is the reference implementation.

---

## License

Upstream ships no license file, so this port carries none either. Do not assume MIT or any other grant. If the upstream author adds a license, mirror it here.
