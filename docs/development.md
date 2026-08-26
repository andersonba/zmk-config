# Development

## Prerequisites

- [mise](https://mise.jdx.dev/) for tool version management
- System dependencies: `cmake`, `dtc` (device tree compiler)

## First-time Setup

```bash
just init
```

This initializes the Python venv, installs West, downloads ZMK/modules, and installs the Zephyr SDK.

## Commands

### Build & Flash

```bash
just build [board] [side]   # board: raii|urchin|corne|crosses|viginti (default: see `just use`)
                            # side: left|right|all (default: all)

just flash [board] [side]   # side default: left
```

Examples:
```bash
just build                  # Build the default board, both sides
just build corne left       # Build Corne left side only
just flash corne right      # Flash Corne right side
```

### Utilities

```bash
just draw [board]           # Generate keymap visualization
just fmt [files]            # Align keymap layer grids (default: base.dtsi + keymaps)
                            # Also runs on commit via .githooks/pre-commit
                            # (enabled by `just init` → core.hooksPath)
just clean                  # Clean build artifacts
just clean-all              # Clean everything (workspace + venv)
just update                 # Sync Python tools + ZMK/modules to west.yml pins
just bump [--dry-run]       # Move west.yml pins to each tracked branch's head
just verify                 # Full validation: draw all, clean, build all
just check                  # Check environment setup
```

## Dependency Pinning

`west.yml` pins every module to a commit; the comment on each pin
(`# <branch> @ <date>`) names the branch it tracks. `just update` never moves
pins — it syncs to them, so local builds match CI. To take newer upstream:

```bash
just bump --dry-run   # preview what would move
just bump             # rewrite pins + west update
just verify           # full build battery before committing the bump
```

## Workflow

1. Edit config files:
   - `config/base.dtsi` for core logic (affects all boards)
   - `config/[board].keymap` for board-specific changes
   - `config/default.conf` or `config/[board].conf` for settings
   - `boards/shields/[board]/` for hardware-level changes (kscan, overlays, trackball)

2. Build: `just build [board]`

3. Flash: Put keyboard in bootloader mode (double-tap reset), then `just flash [board] [side]`

4. Visualize: `just draw [board]`

## Multi-Board Testing

When changing `base.dtsi`, test all boards:

```bash
just build all
```

## Flashing Notes

- Keyboard must be in bootloader mode (double-tap reset or bootloader button)
- Both halves of split keyboards must be flashed separately
