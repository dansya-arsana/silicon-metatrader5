# This fork

A fork of [SiliconMetaTrader5](https://github.com/bahadirumutiscimen/silicon-metatrader5) by Bahadır Umut İşcimen,
kept for Radar (a private, non-commercial trading app). Same license: PolyForm Noncommercial 1.0.0 (see LICENSE and
NOTICE); the changes below are offered under the same terms.

## Changes

### Several MT5 terminals side by side (native mode, macOS and Linux)
Upstream runs one native instance per computer. Here each broker account can have its own instance: its own MT5
(login, history), Python bridge, status API, ports and background job, all at the same time.

```
runtime/macos/instances.sh add exness-demo            # bridge 8011, status API 8012 (next free pair from 8011)
runtime/macos/instances.sh start exness-demo          # then log in to the broker in its MT5 window
runtime/macos/instances.sh list
```
Python: `MetaTrader5(host="127.0.0.1", port=8011)`.

- `native.sh`: the launchd label / systemd unit come from `SMT5_LABEL` / `SMT5_UNIT` (defaults unchanged), the Wine
  folder from `SMT5_WINE_HOME`, and the background job gets the instance's variables (launchd `EnvironmentVariables`,
  systemd `--setenv`). An instance never downloads into or deletes the shared Wine; `reset-all` of the default instance
  keeps Wine while other instances exist.
- `instances.sh` (new): add, start, stop, restart, status, list, start-all, stop-all, remove, env.
- The default instance, the `smt5` command line and the desktop app are unchanged: they manage the default instance.
- Each instance: about 1.2 GB on disk (its Wine prefix with MT5 and Windows Python) and about 600 MB of memory.

Checked on 2026-11-26 (macOS, Apple Silicon, Wine 11.21, MT5 build 6332): a second instance installed, started and
ran next to the default one, each with its own launchd job, terminal and bridge; the default instance's account kept
answering through its bridge. Trading through the second instance after a broker login: not checked yet.

## Install over an existing 1.3.0
Copy `runtime/macos/native.sh` and `runtime/macos/instances.sh` into the installed runtime folder (Homebrew:
`$(brew --prefix)/share/siliconmt5/runtime/macos/`, and the app's `Contents/Resources/runtime/macos/`), then re-sign
the app (`codesign --force --sign - SiliconMetaTrader5.app`). The running default instance picks the new script up at
its next start.
