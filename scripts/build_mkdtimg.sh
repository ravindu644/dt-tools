#!/bin/bash

# build.sh - Static mkdtimg builder for x86_64 and aarch64
# by ravindu644

OUT_DIR="../binaries"
BUILD_DIR="../.build"

LIBUFDT_REPO="https://github.com/LineageOS/android_system_libufdt.git"
DTC_REPO="https://github.com/dgibson/dtc.git"

LIBUFDT_DIR="$BUILD_DIR/libufdt"
DTC_DIR="$BUILD_DIR/dtc"
LIBFDT_DIR="$DTC_DIR/libfdt"

# --- logging ---

log()    { echo "[*] $*"; }
success(){ echo "[+] $*"; }
warn()   { echo "[!] $*"; }
error()  { echo "[-] $*" >&2; exit 1; }

# --- dependency check ---

check_deps() {
    local missing=()
    for cmd in gcc aarch64-linux-gnu-gcc git ar; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing tools: ${missing[*]}\n    Install with: sudo apt install gcc gcc-aarch64-linux-gnu git binutils"
    fi
}

# --- fetch sources ---

fetch_sources() {
    mkdir -p "$BUILD_DIR"

    if [[ ! -d "$LIBUFDT_DIR" ]]; then
        log "Cloning libufdt..."
        git clone --depth=1 "$LIBUFDT_REPO" "$LIBUFDT_DIR" || error "Failed to clone libufdt"
    else
        log "libufdt already fetched, skipping."
    fi

    if [[ ! -d "$DTC_DIR" ]]; then
        log "Cloning dtc (for libfdt)..."
        git clone --depth=1 "$DTC_REPO" "$DTC_DIR" || error "Failed to clone dtc"
    else
        log "dtc already fetched, skipping."
    fi
}

# --- inject libacpi stub ---

inject_acpi_stub() {
    cat > "$LIBUFDT_DIR/utils/src/libacpi.h" << 'EOF'
#pragma once
#include <stdint.h>
#include <stddef.h>

/* Minimal ACPI stub - DTB-only build, no ACPI support needed */
#define ACPI_TABLE_MAGIC 0x41435049

static inline uint32_t acpi_length(const void *acpi) {
    (void)acpi; return 0;
}
static inline uint8_t acpi_csum(const void *acpi, size_t size) {
    (void)acpi; (void)size; return 0;
}
EOF
}

# --- build libfdt.a ---

build_libfdt() {
    local cc="$1"
    local out="$2"
    local obj_dir
    obj_dir="$(dirname "$out")/fdt_objs_$(basename "$out" .a)"
    local fdt_objs=()

    [[ -d "$LIBFDT_DIR" ]] || error "libfdt source not found at: $LIBFDT_DIR"

    log "Building libfdt.a with $cc..."
    mkdir -p "$obj_dir"

    for src in fdt.c fdt_addresses.c fdt_check.c fdt_empty_tree.c \
               fdt_overlay.c fdt_ro.c fdt_rw.c fdt_strerror.c fdt_sw.c fdt_wip.c; do
        local obj="$obj_dir/${src%.c}.o"
        if ! $cc -O2 -w -I"$LIBFDT_DIR" -c "$LIBFDT_DIR/$src" -o "$obj"; then
            error "Failed to compile $src"
        fi
        fdt_objs+=("$obj")
    done

    if ! ar rcs "$out" "${fdt_objs[@]}"; then
        error "ar failed for $out"
    fi
    rm -rf "$obj_dir"
    success "libfdt.a → $out"
}

# --- build mkdtimg ---

build_mkdtimg() {
    local cc="$1"
    local libfdt_a="$2"
    local out="$3"

    local srcs=(
        "$LIBUFDT_DIR/utils/src/mkdtimg.c"
        "$LIBUFDT_DIR/utils/src/mkdtimg_core.c"
        "$LIBUFDT_DIR/utils/src/mkdtimg_create.c"
        "$LIBUFDT_DIR/utils/src/mkdtimg_cfg_create.c"
        "$LIBUFDT_DIR/utils/src/mkdtimg_dump.c"
        "$LIBUFDT_DIR/utils/src/dt_table.c"
        "$LIBUFDT_DIR/sysdeps/libufdt_sysdeps_posix.c"
    )

    if ! $cc -O2 -w -static \
        -I"$LIBUFDT_DIR/utils/src" \
        -I"$LIBUFDT_DIR/sysdeps/include" \
        -I"$LIBFDT_DIR" \
        "${srcs[@]}" \
        "$libfdt_a" \
        -o "$out" 2>&1; then
        error "Compilation failed for $(basename $out)"
    fi

    success "$(basename $out) → $out ($(du -h $out | cut -f1))"
}

# --- main ---

check_deps
fetch_sources
inject_acpi_stub

mkdir -p "$OUT_DIR"

log "Building x86_64..."
LIBFDT_X86="$BUILD_DIR/libfdt_x86_64.a"
build_libfdt "gcc" "$LIBFDT_X86"
build_mkdtimg "gcc" "$LIBFDT_X86" "$OUT_DIR/mkdtimg.x86_64"

log "Building aarch64..."
LIBFDT_ARM64="$BUILD_DIR/libfdt_aarch64.a"
build_libfdt "aarch64-linux-gnu-gcc" "$LIBFDT_ARM64"
build_mkdtimg "aarch64-linux-gnu-gcc" "$LIBFDT_ARM64" "$OUT_DIR/mkdtimg.aarch64"

success "All done!"
echo ""
echo "    binaries/mkdtimg.x86_64"
echo "    binaries/mkdtimg.aarch64"
