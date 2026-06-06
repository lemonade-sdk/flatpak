# Lemonade Flatpak

A self-contained Flatpak packaging for [Lemonade](https://github.com/lemonade-sdk/lemonade), bundling the local LLM runtime engine, system tray controller, and desktop client.

## Included Runtimes

| Target | Description |
| --- | --- |
| `lemond` | Core LLM engine. Default endpoint: `127.0.0.1:13305`. |
| `lemonade-tray` | StatusNotifier system tray interface. |
| `lemonade-app` | Tauri-based desktop graphical client. |
| `lemonade-supervisor` | Internal orchestration launcher managing startup and teardown bounds. |

## Installation & Execution

Build and register locally:

```bash
flatpak-builder --force-clean --user --install --install-deps-from=flathub build-dir ai.lemonade_server.Lemonade.yaml
```

Execute via CLI:

```bash
flatpak run ai.lemonade_server.Lemonade
```

## Lifecycle Behavior

1. **Initialization:** On invocation, the supervisor checks `http://127.0.0.1:13305/api/v1/health`. If an active host server is discovered, the sandbox connects to it directly. If no endpoint responds, it boots the bundled background `lemond` instance.
2. **Termination:** Closing the application UI preserves the background server and system tray process states. Triggering "Quit" from the tray menu tells the supervisor to kill the companion processes it spawned.
3. **Ownership Boundary:** The supervisor will never shut down an external host server process that it did not explicitly initialize during the startup loop.

## Data Volatility & Storage

* **Bundled State:** Config, models, and run states persist strictly within the isolated runtime container cache path: `~/.var/app/ai.lemonade_server.Lemonade/cache/lemonade/`. Bypassed via passing `LEMONADE_DATA_DIR` at launch.
* **External State:** When connecting to a pre-existing host server daemon, database management and file access stay subject to the host service parameters. The Flatpak acts purely as a local network client.

### Hugging Face Cache Sharing

By default, the runtime isolates model downloads to the container filesystem. To reuse a host-level `~/.cache/huggingface` structure, apply an explicit file override:

```bash
flatpak override --user --filesystem=xdg-cache/huggingface:rw ai.lemonade_server.Lemonade
```

To bind an arbitrary non-standard directory block:

```bash
flatpak override --user --filesystem=/path/to/cache:rw --env=HF_HOME=/path/to/cache ai.lemonade_server.Lemonade
```

## Runtime Environment Settings

| Variable | Function |
| --- | --- |
| `LEMONADE_PORT` | Sets target communication port (Default: `13305`). |
| `LEMONADE_HOST` | Sets target binding address (Default: `127.0.0.1`). |
| `LEMONADE_DATA_DIR` | Sets explicit working directory overrides for the engine runtime. |
| `LEMONADE_FLATPAK_FORCE_BUNDLED=1` | Forces initiation of the bundled engine, skipping host discovery checks. |
| `HF_HOME` | Redirects the internal Hugging Face cache layer path. |

Example using custom variables:

```bash
flatpak run --env=LEMONADE_FLATPAK_FORCE_BUNDLED=1 ai.lemonade_server.Lemonade
```

## Troubleshooting

Run standard error tracking directly from a local shell instance:

```bash
flatpak run ai.lemonade_server.Lemonade 2>&1 | tee /tmp/lemonade.log
```

Alternatively, filter systemic output logs via journald:

```bash
journalctl --user --since "5 min ago" | grep -i lemonade
```
