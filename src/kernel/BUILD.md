# Building t9015rate.ko

The box runs the GKI kernel `5.15.196-android14-11-g3d26c188ef7e-ab14657224`
(full LTO, Clang CFI, MODVERSIONS). You don't need onn's exact source: build
against the `android14-5.15` branch of the Android common kernel with the
box's own config, and borrow the symbol CRCs from the vendor modules already
on the box.

1. Source and config:

   ```sh
   git clone --depth 1 -b android14-5.15 https://android.googlesource.com/kernel/common src
   adb shell su -c 'zcat /proc/config.gz' > src/.config
   cd src
   sed -i 's/^CONFIG_TRIM_UNUSED_KSYMS=y/# CONFIG_TRIM_UNUSED_KSYMS is not set/' .config
   make ARCH=arm64 LLVM=1 LLVM_IAS=1 olddefconfig
   ```

2. `kernel/time/timeconst.bc` wants `bc`. If you don't have it, generate the
   header with the script here and fake `bc` out:

   ```sh
   python3 ../timeconst.py 250 > include/generated/timeconst.h
   mkdir -p ../bin && printf '#!/bin/sh\ncat >/dev/null; cat %s\n' "$PWD/include/generated/timeconst.h" > ../bin/bc && chmod +x ../bin/bc
   PATH="$PWD/../bin:$PATH" make ARCH=arm64 LLVM=1 LLVM_IAS=1 modules_prepare
   ```

3. Symbol CRCs. `device.symvers` already has the ones this kernel expects for
   every symbol the helper uses. To redo them, pull `/vendor/lib/modules/*.ko`
   off the box into a folder and run:

   ```sh
   python3 crcs.py <folder> module_layout param_ops_ulong _printk __ubsan_handle_cfi_check_fail_abort
   ```

4. Build, then copy the result to `module/kernel/`:

   ```sh
   make -C <kernel src> ARCH=arm64 LLVM=1 LLVM_IAS=1 M=$PWD KBUILD_EXTRA_SYMBOLS=$PWD/device.symvers modules
   llvm-strip --strip-debug t9015rate.ko
   ```

## Offsets

`PLAY_OFF` and `CAP_OFF` are where the playback and capture
`struct snd_soc_pcm_stream` sit inside the `.data` section of
`amlogic-snd-codec-t9015.ko` (sha256 `a8d99a85…0e324a`). For a different
firmware, dump it with `readelf -x .data` and look for the `0x7fe` rate mask
next to the channel limits 2/8 and 2/16. Update the offsets here and add the
build to `module/common/compat.sh`.
