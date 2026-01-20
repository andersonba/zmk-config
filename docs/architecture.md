# Architecture

## Board Support

| Board | Keys | Layout | Notes |
|-------|------|--------|-------|
| Urchin | 34 | Direct mapping | Primary board, Nice!Nano v2 + Nice!View |
| Corne | 42 | 34 logical + 8 edge | 3x6+3 layout |
| Crosses | 36 | 34 logical + 2 thumb | 3x5+3 layout |

## Modular Design

The repository shares keymap logic across boards via a base include:

```
config/base.dtsi          # Core 34-key logic (layers, combos, behaviors)
    ↓ included by
config/[board].keymap     # Physical layout mapping
```

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
- `config/extra.dtsi` - Extra key macros for boards with >34 keys (LH2/RH2)
- `config/default.conf` - Shared settings (Bluetooth, sleep, debouncing, ZMK Studio)
- `config/combos.dtsi` - Combo definitions
- `config/macros.dtsi` - Macro definitions

### Board-Specific Files
- `config/urchin.keymap` - Direct 34-key mapping
- `config/corne.keymap` - 34 logical + 8 edge keys
- `config/crosses.keymap` - 34 logical + 2 thumb keys
- `config/[board].conf` - Board-specific settings

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
