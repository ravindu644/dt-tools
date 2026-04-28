#!/bin/bash

# dt-tools.sh - DTB/DTBO unpack, decompile, recompiled, repack tool
#
# Based on:
#    https://ravindu644.medium.com/editing-android-dtb-and-dtbo-images-without-needing-the-kernel-source-8abce427b7e8
#    https://www.youtube.com/watch?v=HyGtnaBHzNM
#
# Copyright (C) 2026 ravindu644 <droidcasts@protonmail.com>
# SPDX-License-Identifier: Apache-2.0

SCRIPT_DIR="$(dirname $(readlink -fq $0))"
BINARIES_DIR="$SCRIPT_DIR/binaries"
WORKDIR_PREFIX="dt_workdir_"

# --- logging ---

log()    { echo "[*] $*"; }
success(){ echo "[+] $*"; }
warn()   { echo "[!] $*" >&2; }
error()  { echo "[-] $*" >&2; exit 1; }

# --- arch check ---

get_binary_names() {
    case $(uname -m) in
        aarch64|arm64)
            IMJTOOL_BIN="imjtool.ELF64.aarch64"
            MKDTIMG_BIN="mkdtimg.aarch64"
            ;;
        x86_64)
            IMJTOOL_BIN="imjtool.ELF64.x64"
            MKDTIMG_BIN="mkdtimg.x86_64"
            ;;
        *) error "Unsupported architecture: $(uname -m)" ;;
    esac
}

# --- dependency check ---

check_deps() {
    local imjtool="$BINARIES_DIR/$IMJTOOL_BIN"
    local mkdtimg="$BINARIES_DIR/$MKDTIMG_BIN"

    if [[ ! -f "$imjtool" ]]; then
        error "imjtool binary not found: $imjtool"
    fi
    if [[ ! -x "$imjtool" ]]; then
        log "Making $IMJTOOL_BIN executable..."
        chmod +x "$imjtool"
    fi

    if [[ ! -f "$mkdtimg" ]]; then
        error "mkdtimg binary not found: $mkdtimg"
    fi
    if [[ ! -x "$mkdtimg" ]]; then
        log "Making $MKDTIMG_BIN executable..."
        chmod +x "$mkdtimg"
    fi

    if ! command -v dtc &>/dev/null; then
        error "'dtc' not found. Install it with: sudo apt install device-tree-compiler"
    fi
}

# --- generate config.cfg from mkdtimg dump output ---

generate_config() {
    local img="$1"
    local work_dir="$2"
    local mkdtimg="$BINARIES_DIR/$MKDTIMG_BIN"

    log "Generating config.cfg from image metadata..."

    local dump_output
    dump_output=$("$mkdtimg" dump "$img" 2>/dev/null) || error "mkdtimg dump failed on '$img'"

    # collect sorted stem names from dts files into a temp filelist
    local filelist
    filelist=$(mktemp)
    ls "$work_dir"/*.dts 2>/dev/null | sort | while read -r f; do
        basename "${f%.dts}"
    done > "$filelist"

    if [[ ! -s "$filelist" ]]; then
        rm -f "$filelist"
        error "No DTS files found in $work_dir to generate config from."
    fi

    # NR==FNR reads filelist first, then parses dump output
    # avoids awk split() length limits on -v string for 100+ entries
    awk '
NR == FNR {
    files[NR-1] = $0
    next
}
/^dt_table_entry\[/ {
    split($0, a, /[\[\]]/)
    current = a[2]+0
    if (current > max_idx) max_idx = current
    next
}
/custom\[/ {
    split($1, a, /[\[\]]/)
    cnum = a[2]
    val = $3
    customs[current "_" cnum] = val
    next
}
END {
    for (i = 0; i <= max_idx; i++) {
        print files[i] ".dtb"
        for (c = 0; c <= 3; c++) {
            printf "\tcustom%d=0x%s\n", c, customs[i "_" c]
        }
        print ""
    }
}
' "$filelist" - <<< "$dump_output" > "$work_dir/config.cfg"

    rm -f "$filelist"

    success "config.cfg saved to $work_dir/config.cfg"
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

    local imjtool="$BINARIES_DIR/$IMJTOOL_BIN"
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

    generate_config "$img" "$work_dir"

    success "$count DTS file(s) + config.cfg ready in ./$work_dir/"
}

# --- repack ---

repack() {
    local work_dir="$1"

    if [[ -z "$work_dir" ]]; then
        echo "Usage: ./dt-tools.sh repack <path/to/dt_workdir_*>"
        exit 1
    fi

    [[ ! -d "$work_dir" ]] && error "Directory not found: $work_dir"
    [[ ! -f "$work_dir/config.cfg" ]] && error "config.cfg not found in $work_dir. Was this unpacked with dt-tools?"

    local mkdtimg="$BINARIES_DIR/$MKDTIMG_BIN"

    # recompile DTS -> DTB
    log "Recompiling DTS -> DTB..."
    local count=0
    for file in "$work_dir"/*.dts; do
        [[ -f "$file" ]] || continue
        local dtb="${file%.dts}.dtb"
        if dtc -f -I dts -O dtb -o "$dtb" "$file" 2>/dev/null; then
            log "compiled: $(basename "$file")"
            (( count++ ))
        else
            error "Failed to compile: $(basename "$file")"
        fi
    done

    [[ $count -eq 0 ]] && error "No DTS files found in $work_dir"

    local work_dir_clean="${work_dir%/}"  # strip trailing slash
    local out_name="${work_dir_clean#$WORKDIR_PREFIX}"
    local out_img="${out_name}_repacked.img"

    log "Packing -> $out_img..."
    "$mkdtimg" cfg_create "$out_img" "$work_dir/config.cfg" -d "$work_dir/" \
        || error "mkdtimg cfg_create failed"

    # clean up recompiled dtbs, keep dts files intact
    rm -f "$work_dir"/*.dtb

    success "Repacked image: $out_img"
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
    echo "  ./dt-tools.sh repack <dt_workdir_*>        Recompile + repack into .img"
    echo "  ./dt-tools.sh clear                        Remove all dt_workdir_* folders"
}

# --- main ---

get_binary_names
check_deps

case "$1" in
    unpack) unpack "$2" "$3" ;;
    repack) repack "$2" ;;
    clear)  clear_workdirs ;;
    *)      usage; exit 1 ;;
esac
