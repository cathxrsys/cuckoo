# cuckoo

A tiny macOS menu bar widget that shows your current **Claude** and **Codex** usage limits.

![cuckoo in the menu bar](docs/screenshot.png)

- **Claude**: two lines, the 5-hour window on top and the weekly window below
- **Codex**: the weekly window
- Click it to open a panel with progress bars, reset times, a refresh button and a "launch at login" toggle

The menu bar image is a template, so it follows the light/dark appearance automatically.

## How it works

It reads the credentials the official CLIs already store on your Mac, and asks the same usage endpoints the CLIs use:

| Service | Credentials | Endpoint |
|---|---|---|
| Claude | Keychain item `Claude Code-credentials` (read via `/usr/bin/security`) | `api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/auth.json` | `chatgpt.com/backend-api/wham/usage` |

Tokens are only read, never refreshed or written back, and are sent nowhere except these two endpoints.

Limits are refreshed every 90 seconds, 3 seconds after a network change (VPN on/off, Wi-Fi switch), after waking from sleep, or manually from the panel.

### Region check

Before every refresh the app looks up the country of your current public IP (`api.country.is`, falling back to `ipinfo.io` and `ipapi.co`).

- **RU**: no requests are made to Anthropic or OpenAI; the menu bar shows `RU ⏸`
- **Country unknown**: also paused, shown as `IP? ⏸`
- **Anything else**: limits are fetched as usual

## Requirements

- macOS 14+
- Swift toolchain (Xcode or Command Line Tools)
- Logged in to [Claude Code](https://claude.com/claude-code) and/or [Codex CLI](https://github.com/openai/codex)

## Build & run

```sh
git clone git@github.com:cathxrsys/cuckoo.git
cd cuckoo
./build.sh
```

`build.sh` builds a release binary, wraps it into `~/Applications/LimitsBar.app` (ad-hoc signed, no Dock icon) and launches it. Run it again to update.

## Caveats

Both usage endpoints are undocumented and may change without notice. If your Claude Code token has expired, run `claude` once to refresh it.

## License

[Apache 2.0](LICENSE)
