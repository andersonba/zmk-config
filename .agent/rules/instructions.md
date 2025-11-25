---
trigger: always_on
---

# Agent Instructions

This file provides guidance to Agents when working with code in this repository.

## Overview

This is a ZMK (Zephyr-based Mechanical Keyboard) configuration repository for a Urchin split keyboard (named "Urchin") with Nice!Nano v2 controllers and Nice!View displays.

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

#### Local Build & Flash

```bash
# Build firmware
mise exec -- just build          # Build both sides (default)
mise exec -- just build left     # Build left side only
mise exec -- just build right    # Build right side only

# Flash firmware (requires keyboard in bootloader mode)
mise exec -- just flash left     # Flash left side
mise exec -- just flash right    # Flash right side

# Utility commands
mise exec -- just clean          # Clean build artifacts
mise exec -- just clean-all      # Clean everything (workspace + venv)
mise exec -- just update         # Update ZMK and dependencies
mise exec -- just check          # Check environment setup
mise exec -- just draw           # Draw keymap in draw/urchin.svg
```

## Architecture

The repository uses a modular configuration approach:

- `config/urchin.keymap` - Main keymap file with some layers
- `config/modules/` - Modular configuration files:
  - `behaviors.dtsi` - Custom key behaviors
  - `combos.dtsi` - Key combinations
  - `hrm.dtsi` - Homerow mods configuration
  - `macros.dtsi` - Macros configuration
  - `apps/` - Application-specific bindings

## Key Dependencies

This repository uses **vanilla ZMK** (official zmkfirmware/zmk) with additional modules:

- `duckyb/urchin-zmk-module` - Urchin ZMK module
- `urob/zmk-helpers` - Convenience macros for ZMK configuration
- `urob/zmk-adaptive-key` - Adaptive key module
- `urob/zmk-auto-layer` - Auto-layer module
- `urob/zmk-tri-state` - Tri-state module
- `urob/zmk-unicode` - Unicode module
- `nice-view-gem` - Custom Nice!View display theme

## Development Workflow

### Local Development

1. Edit configuration files (primarily `urchin.keymap` or module files)
2. Build locally: `mise exec -- just build` (builds both sides)
3. Flash directly: `mise exec -- just flash left`

## Important Notes

- The keyboard requires bootloader mode for flashing (double-tap reset or "bootloader" button)
- Both halves must be flashed separately
- Mouse support is enabled (`CONFIG_ZMK_POINTING=y`)
- Uses custom Nice!View display theme (nice-view-gem)
- All features work with vanilla ZMK (mouse, display, helpers)

## Coding Standards

- **Use ZMK Helpers**: Prefer using \`urob/zmk-helpers\` macros (e.g., \`ZMK_MOD_MORPH\`, \`ZMK_HOLD_TAP\`, \`ZMK_BEHAVIOR\`) over raw DeviceTree syntax. This improves readability and consistency.