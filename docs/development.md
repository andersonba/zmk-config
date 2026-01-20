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
just build [board] [side]   # board: urchin|corne|crosses (default: urchin)
                            # side: left|right|all (default: all)

just flash [board] [side]   # side default: left
```

Examples:
```bash
just build                  # Build Urchin both sides
just build corne left       # Build Corne left side only
just flash corne right      # Flash Corne right side
```

### Utilities

```bash
just draw [board]           # Generate keymap visualization
just clean                  # Clean build artifacts
just clean-all              # Clean everything (workspace + venv)
just update                 # Update ZMK and dependencies
just check                  # Check environment setup
```

## Workflow

1. Edit config files:
   - `config/base.dtsi` for core logic (affects all boards)
   - `config/[board].keymap` for board-specific changes
   - `config/default.conf` or `config/[board].conf` for settings

2. Build: `just build [board]`

3. Flash: Put keyboard in bootloader mode (double-tap reset), then `just flash [board] [side]`

4. Visualize: `just draw [board]`

## Multi-Board Testing

When changing `base.dtsi`, test all boards:

```bash
just build urchin && just build corne && just build crosses
```

## Flashing Notes

- Keyboard must be in bootloader mode (double-tap reset or bootloader button)
- Both halves of split keyboards must be flashed separately
