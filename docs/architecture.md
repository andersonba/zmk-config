# Architecture

## Board Support

| Board | Keys | Layout | Notes |
|-------|------|--------|-------|
| Raii | 34 | Direct mapping | Primary board, Sweep BLING LP variant, Nice!Nano v2 |
| Urchin | 34 | Direct mapping | Nice!Nano v2 + Nice!View |
| Corne | 42 | 34 logical + 8 edge | 3x6+3 layout |
| Crosses | 36 | 34 logical + 2 thumb | 3x5+3 layout |
| Viginti | 20 | Own layers (2x4+2) | Custom split, does **not** use `base.dtsi` |

## Modular Design

The repository shares keymap logic across boards via a base include:

```
config/base.dtsi          # Core 34-key logic (layers, combos, behaviors)
    ↓ included by
config/[board].keymap     # Physical layout mapping
```

### Exception: Viginti (20 keys)

The Viginti has fewer keys than the 34-key logical layout, so it cannot include
`base.dtsi`. Its keymap (`config/viginti.keymap`) is self-contained.

Each alpha layout is split across two layers: the home and bottom rows of the
four outer columns, plus a shift layer holding the top row and the dropped
index-inner column, momentary on the left inner thumb. QWERTY sits on
`BASE1`/`BASE2` and Gallium on `ALPHA1`/`ALPHA2`, toggled from Sys — the same
role split `base.dtsi` uses, so swapping either layout is a content change
rather than a rename.

`Num`, `Sym`, `Fn` and `Sys` mirror the `base.dtsi` layers, with `Fn` and `Sys`
on the same thumb pairs. Symbols that do not fit the Sym layer (`@ # $ % ^`)
live on Num, on the fingers `base.dtsi` assigns them.

It shares `config/default.conf` and the behaviors in `config/macros.dtsi`, and
follows the zmk-helpers coding standards.

## Extra Keys System

Boards with more than 34 keys use the `extra.dtsi` macro system for additional keys.

### How it works

1. `extra.dtsi` defines `_LH2_*` and `_RH2_*` macros with transparent defaults (`___`)
2. Each board can override these per-layer before including `base.dtsi`
3. The `ZMK_BASE_LAYER` macro is redefined by each board to place extra keys

### Adding extra key behavior

In the board's keymap file, define the macro **before** including `base.dtsi`:

```c
// Define extra thumb key for Base layer
#define _LH2_Base &kp LGUI
#define _RH2_Base &kp RGUI

// Define extra key for Num layer only
#define _RH2_Num &kp RET

#include "base.dtsi"
```

### Available positions

| Macro | Position | Used by |
|-------|----------|---------|
| `_LH2_*` | Left thumb outer | Crosses, Corne |
| `_RH2_*` | Right thumb outer | Crosses, Corne |

Layer suffixes: `Base`, `Sym`, `Num`, `Fn`, `Sys`, `Mouse`, `Scroll`

## Logical Layout (34 keys)

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

## File Reference

### Core Files
- `config/base.dtsi` - Keymap logic for 34 logical keys (layers, combos, behaviors, timings)
- `config/behaviors.dtsi` - Position-independent behaviors shared with the Viginti keymap
- `config/extra.dtsi` - Extra key macros for boards with >34 keys (LH2/RH2)
- `config/layers.h` - Symbolic layer indices (shared with shield overlays)
- `config/default.conf` - Shared settings (Bluetooth, sleep, debouncing, ZMK Studio)
- `config/combos.dtsi` - Combo definitions
- `config/macros.dtsi` - Macro definitions

### Board-Specific Files
- `config/cradio.keymap` - Direct 34-key mapping (Raii)
- `config/urchin.keymap` - Direct 34-key mapping
- `config/corne.keymap` - 34 logical + 8 edge keys
- `config/crosses.keymap` - 34 logical + 2 thumb keys
- `config/viginti.keymap` - Self-contained 20-key keymap (no `base.dtsi`)
- `config/[board].conf` - Board-specific settings

### In-Repo Shields (Zephyr module)

The Crosses and Viginti shields are defined in this repo, under
`boards/shields/[board]/` (kscan, matrix transform, physical layout, and the
Crosses trackball overlay). `zephyr/module.yml` at the repo root makes the
repo a Zephyr module so ZMK discovers them — the deprecated `config/boards`
mechanism is not used. Wiring is automatic: locally the justfile passes
`-DZMK_EXTRA_MODULES`, and in CI the `build-user-config` workflow detects
`zephyr/module.yml` on its own.

## Conditional Features

Some features are opt-in via preprocessor flags defined in board keymaps:

| Flag | Purpose | Example |
|------|---------|---------|
| `ENABLE_MOUSE_LAYER` | Adds Mouse/Scroll layers with pointing device support | `crosses.keymap` |

Define flags **before** `#include "base.dtsi"`.

## Quick Lookup

| Looking for... | Check |
|----------------|-------|
| Layer definitions & structure | `base.dtsi` → search `ZMK_BASE_LAYER` |
| Timing constants | `base.dtsi` → top of file |
| Custom behaviors (HRMs, mod-morphs) | `base.dtsi` |
| Combos | `combos.dtsi` |
| Macros | `macros.dtsi` |

## Dependencies

Uses vanilla ZMK with urob's module ecosystem. See `west.yml` for module list.
