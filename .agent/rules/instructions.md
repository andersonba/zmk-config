---
trigger: always_on
---

# ZMK Config

Multi-board ZMK keyboard firmware configuration (Raii, Urchin, Corne, Crosses, Viginti) with unified 34-key logical layout (exception: Viginti is 20-key and has its own self-contained keymap).

## Quick Reference

```bash
just build [board] [side]   # Build firmware (default: raii all)
just flash [board] [side]   # Flash to keyboard in bootloader mode
just draw [board]           # Generate keymap visualization
```

## Critical Rule

**Changes to `config/base.dtsi` affect ALL boards.** Test across boards before committing.

## Key Files

| File | Scope |
|------|-------|
| `config/base.dtsi` | Core keymap logic (all boards) |
| `config/[board].keymap` | Board-specific physical mapping |
| `config/default.conf` | Shared settings |
| `boards/shields/[board]/` | In-repo shields, hardware level (Crosses, Viginti) — repo is a Zephyr module via `zephyr/module.yml` |

## More Details

- [Architecture](docs/architecture.md) - File structure, extra keys system, conditional features
- [Development](docs/development.md) - Setup, commands, workflow
- [Coding Standards](docs/coding-standards.md) - ZMK helpers, urob patterns
