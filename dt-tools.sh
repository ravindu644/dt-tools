#!/bin/bash

# dt-tools.sh - DTB/DTBO unpack & decompile tool
# by ravindu644

SCRIPT_DIR="$(dirname $(readlink -fq $0))"
BINARIES_DIR="$SCRIPT_DIR/binaries"
WORKDIR_PREFIX="dt_workdir_"

# --- logging ---

log()    { echo "[*] $*"; }
success(){ echo "[+] $*"; }
warn()   { echo "[!] $*" >&2; }
error()  { echo "[-] $*" >&2; exit 1; }

# --- arch check ---

get_binary_name() {
    case $(uname -m) in
        aarch64|arm64) BINARY_NAME="imjtool.ELF64.aarch64" ;;
        x86_64)        BINARY_NAME="imjtool.ELF64.x64" ;;
        *) error "Unsupported architecture: $(uname -m)" ;;
    esac
}

# --- dependency check ---

check_deps() {
    local imjtool="$BINARIES_DIR/$BINARY_NAME"

    if [[ ! -f "$imjtool" ]]; then
        error "imjtool binary not found: $imjtool\n    Expected binaries in: $BINARIES_DIR/"
    fi

    if [[ ! -x "$imjtool" ]]; then
        log "Making $BINARY_NAME executable..."
        chmod +x "$imjtool"
    fi

    if ! command -v dtc &>/dev/null; then
        error "'dtc' not found. Install it with: sudo apt install device-tree-compiler"
    fi
}

# --- unpack ---

unpack() {
    local img="$1"
    local name="$2"

    if [[ -z "$img" ]]; then
        echo "Usage: ./dt-tools.sh unpack <image.img> [name]"
        echo "  name  optional suffix (e.g. 'galaxy_s10' -> dt_workdir_galaxy_s10)"
        exit 1
    fi

    [[ ! -f "$img" ]] && error "Image not found: $img"

    if [[ -z "$name" ]]; then
        name="$(basename "$img" | sed 's/\.[^.]*$//')"
    fi
    local work_dir="${WORKDIR_PREFIX}${name}"

    [[ -d "$work_dir" ]] && error "Work directory '$work_dir' already exists. Remove it first or use a different name."

    log "Unpacking '$img' -> $work_dir/"
    mkdir -p "$work_dir"

    local imjtool="$BINARIES_DIR/$BINARY_NAME"
    "$imjtool" "$img" extract

    if [[ ! -d "extracted" ]]; then
        rm -rf "$work_dir"
        error "imjtool produced no output."
    fi

    mv extracted/* "$work_dir"/
    rmdir extracted

    log "Decompiling DTBs -> DTS..."
    local count=0
    for file in "$work_dir"/*.dtb; do
        [[ -f "$file" ]] || continue
        local dts="${file%.dtb}.dts"
        if dtc -f -I dtb -O dts -o "$dts" "$file" 2>/dev/null; then
            log "decompiled: $(basename "$file")"
            rm -f "$file"
            (( count++ ))
        else
            warn "Failed to decompile: $(basename "$file")"
        fi
    done

    success "$count DTS file(s) ready in ./$work_dir/"
}

# --- repack ---

repack() {
    local work_dir="$1"

    if [[ -z "$work_dir" ]]; then
        echo "Usage: ./dt-tools.sh repack <path/to/dt_workdir_*>"
        exit 1
    fi

    [[ ! -d "$work_dir" ]] && error "Directory not found: $work_dir"

    # TODO: recompile DTS -> DTB, generate mkdtimg config, run mkdtimg cfg_create
    warn "repack is not implemented yet."
    exit 1
}

# --- clear ---

clear_workdirs() {
    local found=0
    for dir in "${WORKDIR_PREFIX}"*/; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            success "Removed: $dir"
            (( found++ ))
        fi
    done
    (( found == 0 )) && log "Nothing to clean."
}

# --- usage ---

usage() {
    echo "Usage:"
    echo "  ./dt-tools.sh unpack <image.img> [name]   Unpack + decompile DTB/DTBO image"
    echo "  ./dt-tools.sh repack <dt_workdir_*>        Recompile + repack (TODO)"
    echo "  ./dt-tools.sh clear                        Remove all dt_workdir_* folders"
}

# --- main ---

get_binary_name
check_deps

case "$1" in
    unpack) unpack "$2" "$3" ;;
    repack) repack "$2" ;;
    clear)  clear_workdirs ;;
    *)      usage; exit 1 ;;
esac
