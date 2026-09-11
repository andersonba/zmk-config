boards := "raii urchin corne crosses viginti"
board_pattern := "^(" + replace(boards, " ", "|") + ")$"

board_file := justfile_directory() / ".default-board"
saved_board := if path_exists(board_file) == "true" { trim(read(board_file)) } else { "" }
default_board := if saved_board =~ board_pattern { saved_board } else { "raii" }

default:
    @echo "▸ default board: {{default_board}}   (change with 'just use <board>')"
    @just --list

# Show the default board, or set it for this machine
use board="":
    #!/usr/bin/env bash
    set -euo pipefail
    b={{quote(board)}}

    if [ -z "$b" ]; then
        echo "▸ default board: {{default_board}}"
        exit 0
    fi

    case " {{boards}} " in
        *" $b "*)
            ;;
        *)
            echo "❌ Unknown board: $b"
            echo "   Valid boards: {{boards}}"
            exit 1
            ;;
    esac

    printf '%s\n' "$b" > {{quote(board_file)}}
    echo "▸ default board: $b"

# Initialize ZMK workspace (run this first!)
init:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "🚀 Initializing ZMK workspace..."

    # Step 0: Versioned git hooks (auto-format keymaps on commit)
    git config core.hooksPath .githooks

    # Step 1: Python environment
    if [ ! -d .venv ]; then
        echo "📦 Creating Python virtual environment..."
        python3 -m venv .venv
    else
        echo "✅ Python venv already exists"
    fi

    source .venv/bin/activate

    # Step 2: Python packages (with version checks)
    echo "📦 Installing/updating Python packages..."
    pip install --upgrade pip --quiet

    # Only install what's missing — use `just update` to upgrade
    for package in west keymap-drawer yq watchdog; do
        if pip show $package &>/dev/null; then
            echo "  ✓ $package already installed"
        else
            echo "  Installing $package..."
            pip install $package
        fi
    done

    # Step 3: ZMK workspace
    mkdir -p zmk-workspace

    if [ ! -d zmk-workspace/zmk ]; then
        echo "📥 Cloning ZMK repository..."
        (
            cd zmk-workspace
            git clone -b main https://github.com/zmkfirmware/zmk.git || {
                echo "⚠️  Git clone failed, trying to recover..."
                rm -rf zmk
                git clone -b main https://github.com/zmkfirmware/zmk.git
            }
        )
    else
        echo "✅ ZMK repository already exists"
    fi

    # Step 4: West initialization
    if [ ! -d zmk-workspace/zmk/.west ]; then
        echo "🔧 Initializing West workspace..."
        (
            cd zmk-workspace/zmk
            west init -l app/
            west config manifest.path ../../config
            west config manifest.file west.yml
        )
    else
        echo "✅ West workspace already initialized"
    fi

    # Step 5: West update
    echo "📥 Updating West modules..."
    (
        cd zmk-workspace/zmk
        # Ensure we are on main branch for existing repos
        git fetch origin main && git checkout main || echo "⚠️  Could not checkout main, continuing..."
        west update || {
            echo "⚠️  West update failed, retrying..."
            sleep 2
            west update
        }
        west zephyr-export
    )

    # Step 6: Zephyr Python requirements
    if [ -f zmk-workspace/zmk/zephyr/scripts/requirements.txt ]; then
        echo "📦 Installing Zephyr Python requirements..."
        pip install -q -r zmk-workspace/zmk/zephyr/scripts/requirements.txt
    fi

    # Step 7: Zephyr SDK with retry and resume
    echo "🔧 Installing Zephyr SDK (this may take a while)..."
    SDK_VERSION="0.17.0"
    SDK_DIR="zmk-workspace/zephyr-sdk-${SDK_VERSION}"

    if [ ! -d "$SDK_DIR" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            if [[ $(uname -m) == "arm64" ]]; then
                SDK_ARCH="aarch64"
            else
                SDK_ARCH="x86_64"
            fi

            SDK_URL="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${SDK_VERSION}/zephyr-sdk-${SDK_VERSION}_macos-${SDK_ARCH}.tar.xz"
            SDK_FILE="zmk-workspace/zephyr-sdk.tar.xz"

            # Download with resume capability
            download_with_retry() {
                local url=$1
                local output=$2
                local max_retries=3
                local retry=0

                while [ $retry -lt $max_retries ]; do
                    echo "  Downloading SDK (attempt $((retry+1))/$max_retries)..."

                    # Use curl with resume capability
                    if command -v curl &> /dev/null; then
                        curl -L -C - --progress-bar -o "$output" "$url" && return 0
                    elif command -v wget &> /dev/null; then
                        wget -c --progress=bar:force -O "$output" "$url" && return 0
                    else
                        echo "❌ Neither curl nor wget found. Please install one."
                        exit 1
                    fi

                    retry=$((retry + 1))
                    if [ $retry -lt $max_retries ]; then
                        echo "  ⚠️  Download failed, retrying in 5 seconds..."
                        sleep 5
                    fi
                done

                echo "❌ Failed to download SDK after $max_retries attempts"
                echo "  You can manually download from: $url"
                echo "  And place it at: $output"
                return 1
            }

            # Check if partial download exists
            if [ -f "$SDK_FILE" ]; then
                echo "  Found partial SDK download, resuming..."
            fi

            # Download SDK with retry
            if download_with_retry "$SDK_URL" "$SDK_FILE"; then
                echo "  Extracting SDK..."
                (
                    cd zmk-workspace
                    tar -xf zephyr-sdk.tar.xz || {
                        echo "❌ Extraction failed. The archive might be corrupted."
                        echo "  Removing partial download..."
                        rm -f zephyr-sdk.tar.xz
                        exit 1
                    }
                    rm -f zephyr-sdk.tar.xz
                    cd "zephyr-sdk-${SDK_VERSION}"
                    ./setup.sh -h -c
                )
                echo "✅ Zephyr SDK installed successfully"
            else
                echo "⚠️  SDK installation incomplete. Run 'just init' again to retry."
                exit 1
            fi
        else
            echo "⚠️  Non-macOS systems need manual SDK installation"
            echo "  Download from: https://github.com/zephyrproject-rtos/sdk-ng/releases"
        fi
    else
        echo "✅ Zephyr SDK already installed"
    fi

    echo "✨ Setup complete! Run 'just build' to build firmware"

# Sync dependencies: Python tools + ZMK/modules at their west.yml pins
update:
    #!/usr/bin/env bash
    set -euo pipefail
    source .venv/bin/activate

    echo "📦 Upgrading Python packages..."
    pip install --upgrade pip --quiet
    for package in west keymap-drawer yq watchdog; do
        echo "  Upgrading $package..."
        pip install --upgrade $package --quiet
    done

    echo "📥 Syncing ZMK and modules to west.yml pins..."
    cd zmk-workspace/zmk
    west update
    west zephyr-export

    echo "✅ In sync with west.yml (to move the pins forward, use 'just bump')"

# Bump west.yml pins to each tracked branch's head; pass --dry-run to preview
bump *flags="":
    #!/usr/bin/env bash
    set -euo pipefail
    source .venv/bin/activate

    python3 scripts/bump_pins.py {{flags}}

    case " {{flags}} " in *" --dry-run "*) exit 0 ;; esac

    cd zmk-workspace/zmk
    west update
    west zephyr-export
    echo "✅ Pins bumped and synced — run 'just verify' before committing"

# Full validation ritual: regenerate diagrams, then clean-build every target
verify:
    just draw all
    just clean
    just build all

_validate_args board target part="":
    #!/usr/bin/env bash
    set -euo pipefail

    b={{quote(board)}}
    t={{quote(target)}}
    p={{quote(part)}}

    case " {{boards}} all " in
        *" $b "*)
            ;;
        *)
            echo "❌ Unknown board: $b"
            echo "   Valid boards: {{boards}}"
            exit 1
            ;;
    esac

    case "$t" in
        "left"|"right"|"all")
            ;;
        "dongle")
            case "$p" in
                ""|"left"|"right"|"peripheral"|"all")
                    ;;
                *)
                    echo "❌ Invalid dongle part: $p"
                    echo "   Valid parts: (empty for dongle only), left, right, peripheral, all"
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "❌ Invalid target: $t"
            echo "   Valid targets: left, right, all, dongle"
            exit 1
            ;;
    esac

# Internal: Build firmware with West. One build directory per shield keeps
# every target incremental and makes cross-shield cache clashes impossible.
_west_build board shield flags="":
    #!/usr/bin/env bash
    set -euo pipefail
    source .venv/bin/activate

    echo "🔨 Building {{board}} {{shield}}..."

    (
        cd zmk-workspace/zmk
        shield="{{shield}}"
        PROJECT_ROOT=$(cd ../.. && pwd)
        # zmk/app is the west-managed checkout, honoring the west.yml pin;
        # the outer clone only hosts the workspace and is never built.
        west build -b {{board}} -d "build/${shield%% *}" zmk/app -- \
            -DSHIELD="{{shield}}" \
            -DZMK_CONFIG="${PROJECT_ROOT}/config" \
            -DZMK_EXTRA_MODULES="${PROJECT_ROOT}" \
            {{flags}}
    )

    mkdir -p firmware

# Internal: Flash UF2 file to NICENANO
_flash_uf2 file_path:
    #!/usr/bin/env bash
    set -euo pipefail

    if [ ! -f "{{file_path}}" ]; then
        echo "❌ Firmware file not found: {{file_path}}"
        exit 1
    fi

    # Function to find NICENANO mount point
    find_keyboard() {
        local disk_id
        local mount_point
        disk_id=$(diskutil list | grep NICENANO | awk '{print $NF}')
        if [ -z "$disk_id" ]; then
            echo "Error: NICENANO disk not found. Make sure the keyboard is in bootloader mode (double-tap reset)." >&2
            exit 1
        fi
        mount_point=$(diskutil info "$disk_id" | grep "Mount Point" | cut -d ':' -f2 | xargs)
        echo "$mount_point"
    }

    # Find the keyboard
    KEYBOARD=$(find_keyboard)
    echo "Keyboard found at: $KEYBOARD"

    echo "❯ Copying firmware to NICENANO..."
    error_msg=$(cp "{{file_path}}" "$KEYBOARD/" 2>&1) || {
        if [[ $error_msg == *"fcopyfile failed"* ]] || [[ $error_msg == *"could not copy extended attributes"* ]]; then
            # Expected behavior - microcontroller resets mid-transfer
            :
        else
            echo "Error: $error_msg"
            exit 1
        fi
    }

# Build firmware: board (defaults to `just use`) and target (left/right/all/dongle)
build board=default_board target="all" part="":
    #!/usr/bin/env bash
    set -euo pipefail

    if [ "{{board}}" == "all" ]; then
        for b in {{boards}}; do just build "$b" {{target}} {{part}}; done
        just build-reset
        exit 0
    fi

    just _validate_args {{board}} {{target}} {{part}}

    # Handle dongle builds
    if [ "{{target}}" == "dongle" ]; then
        case {{board}} in
            "raii")
                BOARD_TARGET="nice_nano//zmk"
                DONGLE_SHIELD="cradio_dongle"
                PERIPHERAL_SIDE="left"
                PERIPHERAL_SHIELD="cradio_left"
                ;;
            "urchin")
                BOARD_TARGET="nice_nano//zmk"
                DONGLE_SHIELD="urchin_dongle"
                PERIPHERAL_SIDE="left"
                PERIPHERAL_SHIELD="urchin_left nice_view_adapter nice_view_gem"
                ;;
            "corne")
                BOARD_TARGET="nice_nano//zmk"
                DONGLE_SHIELD="corne_dongle"
                PERIPHERAL_SIDE="left"
                PERIPHERAL_SHIELD="corne_left nice_view_adapter nice_view"
                ;;
            "crosses")
                BOARD_TARGET="nice_nano//zmk"
                DONGLE_SHIELD="crosses_dongle"
                PERIPHERAL_SIDE="right"
                PERIPHERAL_SHIELD="crosses_right"
                ;;
            "viginti")
                BOARD_TARGET="nice_nano//zmk"
                DONGLE_SHIELD="viginti_dongle"
                PERIPHERAL_SIDE="left"
                PERIPHERAL_SHIELD="viginti_left"
                ;;
        esac

        p="{{part}}"

        # Build dongle itself when part is empty or "all"
        if [ -z "$p" ] || [ "$p" == "all" ]; then
            echo "🔨 Building {{board}} dongle..."
            PROJECT_ROOT=$(pwd)
            just _west_build "$BOARD_TARGET" "$DONGLE_SHIELD" "-DEXTRA_CONF_FILE=${PROJECT_ROOT}/config/dongle.conf"
            cp "zmk-workspace/zmk/build/${DONGLE_SHIELD%% *}/zephyr/zmk.uf2" firmware/{{board}}_dongle.uf2
            echo "✅ Dongle firmware built: firmware/{{board}}_dongle.uf2"
        fi

        # Build peripheral when part is requested
        if [ "$p" == "$PERIPHERAL_SIDE" ] || [ "$p" == "peripheral" ] || [ "$p" == "all" ]; then
            echo "🔨 Building {{board}} $PERIPHERAL_SIDE peripheral for dongle..."
            just _west_build "$BOARD_TARGET" "$PERIPHERAL_SHIELD" "-DCONFIG_ZMK_SPLIT=y -DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=n"
            cp "zmk-workspace/zmk/build/${PERIPHERAL_SHIELD%% *}/zephyr/zmk.uf2" firmware/{{board}}_${PERIPHERAL_SIDE}_peripheral.uf2
            echo "✅ Peripheral firmware built: firmware/{{board}}_${PERIPHERAL_SIDE}_peripheral.uf2"
        elif [ -n "$p" ] && [ "$p" != "all" ]; then
            echo "ℹ️ Note: For {{board}}, the side converted to peripheral is '$PERIPHERAL_SIDE' (use 'just build {{board}} dongle $PERIPHERAL_SIDE' or 'peripheral')."
        fi
        exit 0
    fi

    # Standard split builds (both sides)
    if [ "{{target}}" == "all" ]; then
        echo "🔨 Building {{board}} (both sides)..."
        just build {{board}} left
        just build {{board}} right
        exit 0
    fi

    # Define shields based on board
    case {{board}} in
        "raii")
            BOARD_TARGET="nice_nano//zmk"
            SHIELD="cradio_{{target}}"
            ;;
        "urchin")
            BOARD_TARGET="nice_nano//zmk"
            SHIELD="urchin_{{target}} nice_view_adapter nice_view_gem"
            ;;
        "corne")
            BOARD_TARGET="nice_nano//zmk"
            SHIELD="corne_{{target}} nice_view_adapter nice_view"
            ;;
        "crosses")
            BOARD_TARGET="nice_nano//zmk"
            SHIELD="crosses_{{target}}"
            ;;
        "viginti")
            BOARD_TARGET="nice_nano//zmk"
            SHIELD="viginti_{{target}}"
            ;;
    esac

    just _west_build "$BOARD_TARGET" "$SHIELD"

    cp "zmk-workspace/zmk/build/${SHIELD%% *}/zephyr/zmk.uf2" firmware/{{board}}_{{target}}.uf2
    echo "✅ Firmware built: firmware/{{board}}_{{target}}.uf2"

# Build settings reset firmware
build-reset:
    just _west_build "nice_nano//zmk" "settings_reset"
    cp zmk-workspace/zmk/build/settings_reset/zephyr/zmk.uf2 firmware/settings_reset.uf2
    echo "✅ Firmware built: firmware/settings_reset.uf2"

# Flash settings reset firmware
flash-reset:
    #!/usr/bin/env bash
    set -euo pipefail
    FIRMWARE_FILE="firmware/settings_reset.uf2"
    if [ ! -f "$FIRMWARE_FILE" ]; then
        echo "No firmware found at $FIRMWARE_FILE. Building first..."
        just build-reset
    fi
    echo "❯ Flashing settings_reset..."
    just _flash_uf2 "$FIRMWARE_FILE"
    echo "✅ Flashed settings_reset"

# Flash firmware (requires keyboard in bootloader mode)
flash board target part="":
    #!/usr/bin/env bash
    set -euo pipefail
    just _validate_args {{board}} {{target}} {{part}}

    if [ "{{target}}" == "dongle" ]; then
        case {{board}} in
            "crosses") PERIPHERAL_SIDE="right" ;;
            *) PERIPHERAL_SIDE="left" ;;
        esac

        p="{{part}}"
        if [ -z "$p" ]; then
            FIRMWARE_FILE="firmware/{{board}}_dongle.uf2"
            if [ ! -f "$FIRMWARE_FILE" ]; then
                echo "No firmware found at $FIRMWARE_FILE. Building first..."
                just build {{board}} dongle
            fi
            echo "❯ Flashing {{board}} dongle..."
            just _flash_uf2 "$FIRMWARE_FILE"
            echo "✅ Flashed {{board}} dongle"
            exit 0
        elif [ "$p" == "$PERIPHERAL_SIDE" ] || [ "$p" == "peripheral" ]; then
            FIRMWARE_FILE="firmware/{{board}}_${PERIPHERAL_SIDE}_peripheral.uf2"
            if [ ! -f "$FIRMWARE_FILE" ]; then
                echo "No firmware found at $FIRMWARE_FILE. Building first..."
                just build {{board}} dongle "$p"
            fi
            echo "❯ Flashing {{board}} ${PERIPHERAL_SIDE} peripheral..."
            just _flash_uf2 "$FIRMWARE_FILE"
            echo "✅ Flashed {{board}} ${PERIPHERAL_SIDE} peripheral"
            exit 0
        else
            echo "❌ For {{board}}, the peripheral side is '$PERIPHERAL_SIDE'. Use 'just flash {{board}} dongle $PERIPHERAL_SIDE'"
            exit 1
        fi
    fi

    FIRMWARE_FILE="firmware/{{board}}_{{target}}.uf2"
    if [ ! -f "$FIRMWARE_FILE" ]; then
        echo "No firmware found at $FIRMWARE_FILE. Building first..."
        just build {{board}} {{target}}
    fi
    echo "❯ Flashing {{board}} {{target}}..."
    just _flash_uf2 "$FIRMWARE_FILE"
    echo "✅ Flashed {{board}} {{target}}"

draw board=default_board method="default":
    #!/usr/bin/env bash
    set -euo pipefail
    source .venv/bin/activate

    if [ "{{board}}" == "all" ]; then
        for b in {{boards}}; do just draw "$b"; done
        exit 0
    fi

    case {{board}} in
        "raii") KEYMAP_FILE="config/cradio.keymap";;
        *) KEYMAP_FILE="config/{{board}}.keymap";;
    esac
    YAML_FILE="draw/{{board}}.yaml"
    SVG_FILE="draw/{{board}}.svg"

    echo "🎨 Drawing keymap for {{board}}..."

    case {{board}} in
        "raii") LAYOUT_ARGS="-j draw/raii_info.json";;
        "urchin") LAYOUT_ARGS="-k ferris/sweep";;
        "corne") LAYOUT_ARGS="-k crkbd/rev4_1/standard";;
        "crosses") LAYOUT_ARGS="-j draw/crosses_info.json";;
        "viginti") LAYOUT_ARGS="-j draw/viginti_info.json";;
        *) echo "Unknown board: {{board}}"; exit 1;;
    esac

    case {{method}} in
        "default")
            keymap -c "draw/config.yaml" parse -z "$KEYMAP_FILE" >"$YAML_FILE"
        ;; "combine-combos")
            keymap -c "draw/config.yaml" parse -z "$KEYMAP_FILE" --virtual-layers Combos >"$YAML_FILE"
            yq -Yi '.combos.[].l = ["Combos"]' "$YAML_FILE"
        ;;
        *) echo "Unknown method: {{method}}"; exit 1;;
    esac

    if [ "{{board}}" == "crosses" ]; then
        # del(.layers.A, .layers.B, ...etc)
        yq -y 'del(.layers.Scroll)' "$YAML_FILE" > "${YAML_FILE}.tmp"
        mv "${YAML_FILE}.tmp" "$YAML_FILE"
    fi

    # Hide Alpha layers from all boards (learning layout, not needed in docs).
    # Prefix match, so a layout split across Alpha1/Alpha2 is caught as well.
    # First remove them from combo layer references, then delete the layers.
    yq -y '(.combos[].l) |= map(select(startswith("Alpha") | not)) | .layers |= with_entries(select(.key | startswith("Alpha") | not))' "$YAML_FILE" > "${YAML_FILE}.tmp"
    mv "${YAML_FILE}.tmp" "$YAML_FILE"

    keymap -c "draw/config.yaml" draw "$YAML_FILE" $LAYOUT_ARGS >"$SVG_FILE"
    
    echo "✅ Drawn to $SVG_FILE"

# Align keymap layer grids (ZMK_*LAYER blocks); pass --check to verify only
fmt *files="config/base.dtsi config/*.keymap":
    python3 scripts/format_keymap.py {{files}}

# Re-run a command on every change; takes one or more boards, or `all`
watch command='draw' *boards=default_board:
    #!/usr/bin/env bash
    set -euo pipefail
    source .venv/bin/activate

    run="for b in {{boards}}; do just {{command}} \$b || exit 1; done"
    eval "$run"
    watchmedo shell-command -R -w -v -c "$run && echo '¤ Updated'" config/ draw/config.yaml

watch-browser command='draw' *boards=default_board:
    open "resources/watch-draw.html"
    just watch {{command}} {{boards}}

# Clean build artifacts
clean:
    rm -rf zmk-workspace/zmk/build
    rm -rf firmware

# Clean everything (including zmk-workspace)
clean-all: clean
    rm -rf zmk-workspace
    rm -rf .venv

# Check if environment is properly set up
check:
    #!/usr/bin/env bash
    echo "🔍 Checking environment..."

    # Check mise
    if command -v mise &> /dev/null; then
        echo "✅ mise installed"
    else
        echo "❌ mise not found"
    fi

    # Check Python
    if [ -d .venv ]; then
        echo "✅ Python venv exists"
    else
        echo "❌ Python venv missing (run 'just init')"
    fi

    # Check West
    if [ -d .venv ] && source .venv/bin/activate && command -v west &> /dev/null; then
        echo "✅ West installed"
    else
        echo "❌ West not found"
    fi

    # Check workspace
    if [ -d zmk-workspace ]; then
        echo "✅ ZMK workspace exists"
    else
        echo "❌ ZMK workspace missing (run 'just init')"
    fi
