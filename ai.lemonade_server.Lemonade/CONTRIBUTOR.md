# Lemonade Flatpak Packaging Guide

This repository contains the Flatpak packaging files for [Lemonade](https://github.com/lemonade-sdk/lemonade).

## Component Directory

| Path / Binary | Description |
| --- | --- |
| `ai.lemonade_server.Lemonade.yaml` | Main Flatpak build manifest. |
| `ai.lemonade_server.Lemonade.appdata.xml` | AppStream metadata and release history. |
| `lemonade-supervisor.sh` | Entrypoint script managing background process lifecycles. |
| `Makefile` | Routine developer workflow shortcuts. |
| `modules/` | C++ dependency manifests missing from GNOME 50 (`nlohmann_json`, `CLI11`, `cpp-httplib`, `libwebsockets`). |
| `shared-modules/` | Git submodule providing GTK3 `libayatana-appindicator`. |
| `tests/` | BATS lifecycle test suite for the supervisor script. |
| `generated-*.json` | Pin files for offline npm and cargo dependency resolution. |

## Prerequisites

- Flatpak, flatpak-builder, and the Flathub remote.
- Git submodules:
  ```bash
  git submodule update --init
  ```
- Container engine (`podman` or `docker`) for running tests and resource generation.
- `shellcheck` for script linting.

## Developer Targets

Run `make` or `make help` to see all available shortcuts.

```bash
make build       # Local compilation (output to build-dir)
make install     # Build and install to the local user space
make uninstall   # Remove user installation
make test        # Execute BATS integration tests inside a runtime container
make lint        # Run shellcheck against the supervisor script
make clean       # Flush build caches and generated environments
```

### Direct Sandbox Execution

Pass arguments to specific sandboxed binaries by appending them after `--`:

```bash
make run                       # Launch complete supervisor stack
make run/lemond -- --help      # Execute background server with flags
make run/tray                  # Execute system tray module only
make run/desktop               # Execute Tauri frontend application only
```

## Engineering & Architecture Notes

* **Dual Module Patching:** Both local patches (`0001-...` and `0002-...`) are registered under both `lemonade-cpp` and `lemonade-app` modules because they share the same source checkout anchor (`&lemonade-source`).
* **CMake Post-Install:** Upstream CMake scripts attempt to write unconditionally to read-only paths (`/usr/bin`). Manifest targets use `no-make-install: true` and manually migrate targets via `post-install`.
* **Resource Symlinking:** `lemond` looks for assets relative to its execution path or `/usr/share`. Since Flatpak relies on `/app`, a symlink from `/app/bin/resources` to `/app/share/lemonade-server/resources` satisfies path resolution.
* **Tauri Custom Protocol:** Compiling the Tauri frontend via raw cargo requires explicitly passing `--features tauri/custom-protocol` to prevent webview asset load failures.
* **Single-Instance Enforcement:** Single-instance control and deep-linking depend on a local file descriptor lock (`flock`) on `$XDG_RUNTIME_DIR`. If a lock exists, subsequent instances immediately forward arguments to the open window and exit.

## Maintenance Tasks

### Upstream Version Upgrades

1. Update the `tag` and `commit` fields inside the `&lemonade-source` YAML block.
2. Refresh structural dependencies:
   ```bash
   make sources LEMONADE_REF=vX.Y.Z
   ```
3. Verify that local patches apply cleanly against the new codebase.
4. Compare dependency requirements in upstream `CMakeLists.txt` against submodules pinned in `modules/`.
5. Append a strict release metadata tag to `ai.lemonade_server.Lemonade.appdata.xml`.
