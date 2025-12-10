# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a multi-board ZMK (Zephyr-based Mechanical Keyboard) configuration repository supporting three keyboards:
- **Urchin** (34 keys) - Primary board with Nice!Nano v2 and Nice!View displays
- **Corne** (42 keys) - 3x6+3 layout
- **Crosses** (36 keys) - 3x5+3 layout

Features a unified logical layout with board-specific physical mappings.

## Local Development Setup

### Prerequisites

- [mise](https://mise.jdx.dev/) for tool version management and environment auto-activation
- System dependencies: `cmake`, `dtc` (device tree compiler)

### First-time Setup

```bash
# Initialize local development environment
mise exec -- just init
```

This will:

- Create Python virtual environment
- Install West (Zephyr meta-tool)
- Download ZMK, modules, and dependencies
- Install Zephyr SDK
- Install Python requirements

### Essential Commands

#### Multi-Board Build & Flash

```bash
# Build firmware (supports multiple boards)
mise exec -- just build [board] [side]  # board: urchin (default), corne, crosses
                                        # side: left, right, all (default)

# Examples:
mise exec -- just build                # Build Urchin both sides
mise exec -- just build corne left     # Build Corne left side
mise exec -- just build crosses all    # Build Crosses both sides

# Flash firmware (requires keyboard in bootloader mode)
mise exec -- just flash [board] [side] # board: urchin, corne, crosses
                                       # side: left, right (left is default)

# Examples:
mise exec -- just flash               # Flash Urchin left side
mise exec -- just flash corne right   # Flash Corne right side

# Utility commands
mise exec -- just draw [board]        # Generate keymap visualization
mise exec -- just clean               # Clean build artifacts
mise exec -- just clean-all           # Clean everything (workspace + venv)
mise exec -- just update              # Update ZMK and dependencies
mise exec -- just check               # Check environment setup
```

## Architecture

The repository uses a **modular architecture** to share keymap logic across different keyboards:

### Core Files
- **`config/base.dtsi`** - Core keymap logic for 34 logical keys (layers, combos, behaviors, timings)
- **`config/default.conf`** - Shared configuration settings (Bluetooth, sleep, debouncing, ZMK Studio)

### Board-Specific Files
- **`config/urchin.keymap`** - Maps 34 logical keys to Urchin's physical layout (direct mapping)
- **`config/corne.keymap`** - Maps 34 logical keys + 8 edge keys to Corne's 42-key layout
- **`config/crosses.keymap`** - Maps 34 logical keys + 2 thumb keys to Crosses's 36-key layout
- **Board configs** - `urchin.conf`, `corne.conf`, `crosses.conf` for board-specific settings

### Logical Layout (34 keys)
```
/*                KEY POSITIONS
 * ╭─────────────────────╮ ╭─────────────────────╮
 * │ LT4 LT3 LT2 LT1 LT0 │ │ RT0 RT1 RT2 RT3 RT4 │
 * │ LM4 LM3 LM2 LM1 LM0 │ │ RM0 RM1 RM2 RM3 RM4 │
 * │ LB4 LB3 LB2 LB1 LB0 │ │ RB0 RB1 RB2 RB3 RB4 │
 * ╰───────────╮ LH1 LH0 │ │ RH0 RH1 ╭───────────╯
 *             ╰─────────╯ ╰─────────╯
 */
```

## Key Dependencies

This repository uses **vanilla ZMK** (official zmkfirmware/zmk) with urob's module ecosystem:

- `duckyb/urchin-zmk-module` - Urchin keyboard definition
- `urob/zmk-helpers` - Convenience macros for ZMK configuration
- `urob/zmk-adaptive-key` - Adaptive key behaviors (magic shift, context-aware keys)
- `urob/zmk-auto-layer` - Auto-layer functionality (num-word, smart layers)
- `urob/zmk-tri-state` - Tri-state behaviors (swapper, smart mouse)
- `urob/zmk-unicode` - Unicode character support
- `nice-view-gem` - Custom Nice!View display theme

## Development Workflow

### Local Development

1. Edit configuration files:
   - **Core logic**: `config/base.dtsi` (affects all boards)
   - **Board-specific**: `config/[board].keymap` (affects single board)
   - **Settings**: `config/default.conf` or `config/[board].conf`

2. Build and test: `mise exec -- just build [board]`
3. Flash directly: `mise exec -- just flash [board] [side]`
4. Visualize: `mise exec -- just draw [board]`

### Multi-Board Testing

Test changes across all supported boards:
```bash
just build urchin && just build corne && just build crosses
```

## Features

Current implementation includes:

- **Home Row Mods**: "Timeless" configuration based on urob's layout (280/150/175ms timings)
- **Smart Combos**: Horizontal combos (Esc, Enter, Cut/Copy/Paste, brackets)
- **Vertical Combos**: urob-style vertical combos for symbols (@, #, $, %, +, -, =, etc.)
- **Dual Layouts**: QWERTY and Graphite layouts (unique feature)
- **Smart Numbers**: num_word functionality with auto-layer
- **AI Integration**: Custom ChatGPT and Translate macros (unique feature)
- **Both-hand Symbols**: Simultaneous combos for paired symbols ((), [], {})
- **Swapper**: Alt+Tab functionality with tri-state
- **Unicode Support**: Enabled for special characters
- **ZMK Studio**: Enabled for real-time configuration

## Important Notes

- The keyboard requires bootloader mode for flashing (double-tap reset or "bootloader" button)
- Both halves must be flashed separately for split keyboards
- All boards share the same logical layout but have different physical key counts
- Changes to `base.dtsi` affect all boards; test thoroughly
- Uses urob's module ecosystem for maximum compatibility and features

## Coding Standards

- **Use ZMK Helpers**: Prefer using `urob/zmk-helpers` macros (e.g., `ZMK_MOD_MORPH`, `ZMK_HOLD_TAP`, `ZMK_BEHAVIOR`) over raw DeviceTree syntax
- **Follow urob patterns**: When adding features, reference urob's implementations as the gold standard
- **Maintain 34-key logic**: Keep core functionality within the 34-key logical layout for cross-board compatibility
- **Document board-specific additions**: If adding board-specific keys, document clearly in the board's keymap file