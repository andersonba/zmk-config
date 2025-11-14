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

# Build firmware: specific target (left/right) or both if no target specified
build target="":
    #!/usr/bin/env bash
    set -euo pipefail

    if [ -z "{{target}}" ]; then
        echo "🔨 Building both targets..."
        just build left
        just build right
        exit 0
    fi

    source .venv/bin/activate

    case {{target}} in
        "left")
            BOARD="nice_nano_v2"
            SHIELD="urchin_left nice_view_adapter nice_view_gem"
            ;;
        "right")
            BOARD="nice_nano_v2"
            SHIELD="urchin_right nice_view_adapter nice_view_gem"
            ;;
        *)
            echo "Unknown target: {{target}}"
            echo "Available targets: left, right"
            exit 1
            ;;
    esac

    echo "🔨 Building {{target}} (${BOARD} + ${SHIELD})..."

    # Build from within the ZMK directory (where .west is)
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
    cp zmk-workspace/zmk/build/zephyr/zmk.uf2 firmware/{{target}}.uf2

    echo "✅ Firmware built: firmware/{{target}}.uf2"

# Flash firmware (requires keyboard in bootloader mode)
flash target:
    #!/usr/bin/env bash
    set -euo pipefail

    if [ ! -f firmware/{{target}}.uf2 ]; then
        echo "No firmware found. Building first..."
        just build {{target}}
    fi

    echo "❯ Flashing the {{target}} side..."

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
    echo "❯ Copying {{target}} side firmware to NICENANO..."
    error_msg=$(cp firmware/{{target}}.uf2 "$KEYBOARD/" 2>&1) || {
        if [[ $error_msg == *"fcopyfile failed: Input/output error"* ]]; then
            # macOS errors out on cp to the NICENANO, but it's actually successful
            :
        else
            echo "Error: $error_msg"
            exit 1
        fi
    }

    echo "Flashed the {{target}} side 🚀"

draw:
    #!/usr/bin/env bash
    set -euo pipefail
    source .venv/bin/activate
    keymap -c "draw/config.yaml" parse -z "config/urchin.keymap" --virtual-layers Combos >"draw/urchin.yaml"
    yq -Yi '.combos.[].l = ["Combos"]' "draw/urchin.yaml"
    keymap -c "draw/config.yaml" draw "draw/urchin.yaml" -k "ferris/sweep" >"draw/urchin.svg"

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
