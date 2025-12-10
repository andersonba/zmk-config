default:
    @just --list

# Initialize ZMK workspace (run this first!)
init:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "🚀 Initializing ZMK workspace..."

    if [ ! -d .venv ]; then
        echo "📦 Creating Python virtual environment..."
        python3 -m venv .venv
    fi

    source .venv/bin/activate
    pip install --upgrade pip
    pip install west
    pip install keymap-drawer
    pip install yq
    pip install watchdog

    if [ ! -d zmk-workspace/zmk/.west ]; then
        echo "📥 Initializing ZMK workspace..."

        rm -rf zmk-workspace
        mkdir -p zmk-workspace

        (
            cd zmk-workspace
            git clone https://github.com/zmkfirmware/zmk.git
            cd zmk
            west init -l app/
            west config manifest.path ../../config
            west config manifest.file west.yml
            west update
            west zephyr-export

            echo "📦 Installing Zephyr Python requirements..."
            pip install -r zephyr/scripts/requirements.txt

            echo "🔧 Installing Zephyr SDK..."
            if [ ! -d ../zephyr-sdk-0.16.8 ]; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS
                    if [[ $(uname -m) == "arm64" ]]; then
                        SDK_ARCH="aarch64"
                    else
                        SDK_ARCH="x86_64"
                    fi
                    wget -O zephyr-sdk.tar.xz "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.16.8/zephyr-sdk-0.16.8_macos-${SDK_ARCH}.tar.xz"
                    cd ..
                    tar -xf zmk/zephyr-sdk.tar.xz
                    rm zmk/zephyr-sdk.tar.xz
                    cd zephyr-sdk-0.16.8
                    ./setup.sh -h -c
                fi
            else
                echo "✅ Zephyr SDK already installed"
            fi
        )
    else
        echo "✅ ZMK workspace already exists"
    fi

    echo "✨ Setup complete! Run 'just build' to build firmware"

# Update ZMK and dependencies
update:
    #!/usr/bin/env bash
    set -euo pipefail
    source .venv/bin/activate
    cd zmk-workspace/zmk
    west update
    west zephyr-export

_validate_args board side:
    #!/usr/bin/env bash
    set -euo pipefail

    case {{board}} in
        "urchin"|"corne"|"crosses")
            ;;
        *)
            echo "❌ Unknown board: {{board}}"
            echo "   Valid boards: urchin, corne, crosses"
            exit 1
            ;;
    esac

    case {{side}} in
        "left"|"right")
            ;;
        *)
            echo "❌ Invalid side: {{side}}"
            echo "   Valid sides: left, right"
            exit 1
            ;;
    esac

# Build firmware: board (default: urchin) and side (left/right/all)
build board="urchin" side="all":
    #!/usr/bin/env bash
    set -euo pipefail

    if [ "{{board}}" == "all" ]; then
        just build urchin {{side}}
        just build crosses {{side}}
        just build corne {{side}}
        exit 0
    fi

    if [ "{{side}}" == "all" ]; then
        echo "🔨 Building {{board}} (both sides)..."
        just build {{board}} left
        just build {{board}} right
        exit 0
    fi

    just _validate_args {{board}} {{side}}

    source .venv/bin/activate

    # Define shields and display adapters based on board
    case {{board}} in
        "urchin")
            SHIELD_NAME="urchin"
            EXTRA_MODULES="nice_view_adapter nice_view_gem"
            ;;
        "corne")
            SHIELD_NAME="corne"
            EXTRA_MODULES="nice_view_adapter nice_view"
            ;;
        "crosses")
            SHIELD_NAME="crosses"
            EXTRA_MODULES="" # Assuming no display for now
            ;;
    esac

    BOARD="nice_nano_v2"
    SHIELD="${SHIELD_NAME}_{{side}} ${EXTRA_MODULES}"

    echo "🔨 Building {{board}} {{side}} (${BOARD} + ${SHIELD})..."

    # Build from within the ZMK directory
    (
        cd zmk-workspace/zmk

        # Check if we're building a different target than last time
        if [ -f build/.last_shield ] && [ "$(cat build/.last_shield)" != "${SHIELD}" ]; then
            echo "🧹 Shield changed, cleaning build directory..."
            rm -rf build
        fi

        PROJECT_ROOT=$(cd ../.. && pwd)
        west build -b ${BOARD} app -- \
            -DSHIELD="${SHIELD}" \
            -DZMK_CONFIG="${PROJECT_ROOT}/config"

        # Save the current shield for next time
        echo "${SHIELD}" > build/.last_shield
    )

    mkdir -p firmware
    cp zmk-workspace/zmk/build/zephyr/zmk.uf2 firmware/{{board}}_{{side}}.uf2

    echo "✅ Firmware built: firmware/{{board}}_{{side}}.uf2"

# Flash firmware (requires keyboard in bootloader mode)
flash board side:
    #!/usr/bin/env bash
    set -euo pipefail

    just _validate_args {{board}} {{side}}

    FIRMWARE_FILE="firmware/{{board}}_{{side}}.uf2"
    if [ ! -f "$FIRMWARE_FILE" ]; then
        echo "No firmware found at $FIRMWARE_FILE. Building first..."
        just build {{board}} {{side}}
    fi

    echo "❯ Flashing {{board}} {{side}}..."

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

    # Copy firmware to keyboard
    echo "❯ Copying firmware to NICENANO..."
    error_msg=$(cp "$FIRMWARE_FILE" "$KEYBOARD/" 2>&1) || {
        if [[ $error_msg == *"fcopyfile failed: Input/output error"* ]]; then
            # macOS errors out on cp to the NICENANO, but it's actually successful
            :
        else
            echo "Error: $error_msg"
            exit 1
        fi
    }

    echo "Flashed {{board}} {{side}} 🚀"

draw board="urchin":
    #!/usr/bin/env bash
    set -euo pipefail
    source .venv/bin/activate

    if [ "{{board}}" == "all" ]; then
        just draw urchin
        just draw crosses
        just draw corne
        exit 0
    fi
    
    KEYMAP_FILE="config/{{board}}.keymap"
    YAML_FILE="draw/{{board}}.yaml"
    SVG_FILE="draw/{{board}}.svg"

    echo "🎨 Drawing keymap for {{board}}..."

    case {{board}} in
        "urchin") LAYOUT_ARGS="-k ferris/sweep";;
        "corne") LAYOUT_ARGS="-k crkbd/rev4_1/standard";;
        "crosses") LAYOUT_ARGS="-j draw/crosses_info.json";;
        *) echo "Unknown board: {{board}}"; exit 1;;
    esac

    keymap -c "draw/config.yaml" parse -z "$KEYMAP_FILE" --virtual-layers Combos >"$YAML_FILE"
    yq -Yi '.combos.[].l = ["Combos"]' "$YAML_FILE"
    keymap -c "draw/config.yaml" draw "$YAML_FILE" $LAYOUT_ARGS >"$SVG_FILE"
    
    echo "✅ Drawn to $SVG_FILE"

draw-debug board="urchin":
    #!/usr/bin/env bash
    set -euo pipefail
    source .venv/bin/activate
    
    KEYMAP_FILE="config/{{board}}.keymap"
    YAML_FILE="draw/{{board}}.yaml"
    SVG_FILE="draw/{{board}}.svg"
    
    case {{board}} in
        "urchin") LAYOUT_ARGS="-k ferris/sweep";;
        "corne") LAYOUT_ARGS="-k crkbd/rev4_1/standard";;
        "crosses") LAYOUT_ARGS="-j draw/crosses_info.json";;
        *) echo "Unknown board: {{board}}"; exit 1;;
    esac

    keymap -c "draw/config.yaml" parse -z "$KEYMAP_FILE" >"$YAML_FILE"
    keymap -c "draw/config.yaml" draw "$YAML_FILE" $LAYOUT_ARGS >"$SVG_FILE"

watch command='draw' board="urchin":
    #!/usr/bin/env bash
    set -euo pipefail
    source .venv/bin/activate
    just {{command}} {{board}}
    open "resources/watch-draw.html"
    watchmedo shell-command -R -w -v -c 'just {{command}} {{board}} && echo "¤ Updated"' config/ draw/config.yaml

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
