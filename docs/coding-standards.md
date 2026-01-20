# Coding Standards

## Use ZMK Helpers

Prefer `urob/zmk-helpers` macros over raw DeviceTree syntax:

```c
// Preferred
ZMK_MOD_MORPH(name, ...)
ZMK_HOLD_TAP(name, ...)
ZMK_BEHAVIOR(name, ...)

// Avoid raw DeviceTree when helpers exist
```

## Follow urob Patterns

When adding features, reference [urob's zmk-config](https://github.com/urob/zmk-config) as the gold standard for implementation patterns.

## Maintain 34-Key Logic

Keep core functionality within the 34-key logical layout for cross-board compatibility.

- New behaviors, combos, and layers go in `config/base.dtsi`
- Only board-specific physical mappings go in `config/[board].keymap`

## Board-Specific Additions

If adding keys beyond the 34-key base (e.g., Corne's extra 8 keys):

1. Add mappings only in the specific board's keymap file
2. Document what the extra keys do in comments within that file
