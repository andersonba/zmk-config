default:
    @just --list

# Initialize ZMK workspace (run this first!)
init:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "🚀 Initializing ZMK workspace..."

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
        # Install ZMK Studio dependencies
        pip install protobuf grpcio-tools
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
            BOARD="nice_nano"
            SHIELD_NAME="urchin"
            EXTRA_MODULES="nice_view_adapter nice_view_gem"
            ;;
        "corne")
            BOARD="nice_nano"
            SHIELD_NAME="corne"
            EXTRA_MODULES="nice_view_adapter nice_view"
            ;;
        "crosses")
            BOARD="nice_nano"
            SHIELD_NAME="crosses"
            EXTRA_MODULES="" # Assuming no display for now
            ;;
    esac

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
    # Note: The microcontroller resets before the OS confirms the transfer,
    # causing harmless errors that we can safely ignore.
    echo "❯ Copying firmware to NICENANO..."
    error_msg=$(cp "$FIRMWARE_FILE" "$KEYBOARD/" 2>&1) || {
        if [[ $error_msg == *"fcopyfile failed"* ]] || [[ $error_msg == *"could not copy extended attributes"* ]]; then
            # Expected behavior - microcontroller resets mid-transfer
            :
        else
            echo "Error: $error_msg"
            exit 1
        fi
    }

    echo "✅ Flashed {{board}} {{side}}"

draw board="urchin" method="default":
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

    # Hide Graph layer from all boards (learning layout, not needed in docs)
    # First remove Graph from combo layer references, then delete the layer
    yq -y '(.combos[].l) |= map(select(. != "Graph")) | del(.layers.Graph)' "$YAML_FILE" > "${YAML_FILE}.tmp"
    mv "${YAML_FILE}.tmp" "$YAML_FILE"

    keymap -c "draw/config.yaml" draw "$YAML_FILE" $LAYOUT_ARGS >"$SVG_FILE"
    
    echo "✅ Drawn to $SVG_FILE"

watch command='draw' board="urchin":
    #!/usr/bin/env bash
    set -euo pipefail
    source .venv/bin/activate
    just {{command}} {{board}}
    watchmedo shell-command -R -w -v -c 'just {{command}} {{board}} && echo "¤ Updated"' config/ draw/config.yaml

watch-browser command='draw' board="urchin":
    open "resources/watch-draw.html"
    just watch {{command}} {{board}}

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
