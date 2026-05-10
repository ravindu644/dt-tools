# dt-tools

Android DTB and DTBO unpack, decompile, recompile, and repack tool for Linux.

This tool automates the manual process of editing Device Tree Blobs (DTB) and Device Tree Blob Overlays (DTBO) described in these resources made by me:
- [Medium Article](https://ravindu644.medium.com/editing-android-dtb-and-dtbo-images-without-needing-the-kernel-source-8abce427b7e8)
- [YouTube Tutorial](https://www.youtube.com/watch?v=HyGtnaBHzNM)

## Prerequisites

Install the device tree compiler:

```bash
sudo apt install device-tree-compiler
```

The script expects imjtool and mkdtimg binaries to be present in the binaries directory for table based image operations. These are optional for raw DTB operations.

## Usage

### Table Based Images (DTB/DTBO)

1. Unpack and decompile:
   ```bash
   ./dt-tools.sh unpack dtbo.img
   ```
   This creates a dt_workdir_dtbo folder containing decompiled .dts files and a config.cfg.

2. Repack:
   ```bash
   ./dt-tools.sh repack dt_workdir_dtbo
   ```
   This recompiles the .dts files and packs them back into a new image.

### Raw DTB Files

1. Decompile raw DTB:
   ```bash
   ./dt-tools.sh unpack kernel_dtb
   ```
   Automatically detects raw DTB magic and decompiles to .dts.

2. Recompile raw DTB:
   ```bash
   ./dt-tools.sh repack dt_workdir_kernel_dtb
   ```
   Recompiles to a standard raw DTB file.

### Cleanup

Remove all work directories:
```bash
./dt-tools.sh clear
```

## Credits

Binary credits:
- [imjtool by Jonathan Levin](https://newandroidbook.com/tools/imjtool.html)
- [mkdtimg (Google AOSP)](https://android.googlesource.com/platform/system/libufdt/)

## License

This project is licensed under the Apache License 2.0. See the LICENSE file for details.
