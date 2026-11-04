#!/bin/bash
# build.sh — build SMCNvidiaGPU.kext (VirtualSMC plugin, OpenCore-injected) without Xcode or a KDK.
#
# It needs nothing from the NVRM binary: the kext asks NVRM for its entry points and offsets at run time.
#
# Needs VirtualSMC + Lilu sources for the plugin SDK headers. They are not in this repository; point
# VSMCDIR/LILUDIR at them (LILUDIR can be a Lilu.kext's Contents/Resources), or place them next to the repository
# as vsmc/VirtualSMC-master and vsmc/Lilu-master. MACKERNELSDK= takes the kernel headers and kmod libraries from
# acidanthera's MacKernelSDK instead of the macOS SDK.
#
#     kext/build.sh [output-directory]        (default: kext/build)
#
# MODE=debug builds an unoptimised kext that logs every polling tick (handy when troubleshooting);
# MODE=release (default) is the one to install.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SDK=$(xcrun --show-sdk-path)
KHDR="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
KLIB=()
if [ -n "${MACKERNELSDK:-}" ]; then
    KHDR="$MACKERNELSDK/Headers"
    KLIB=(-L"$MACKERNELSDK/Library/universal")
fi
VSMCDIR=${VSMCDIR:-$ROOT/../vsmc/VirtualSMC-master}
LILUDIR=${LILUDIR:-$ROOT/../vsmc/Lilu-master/Lilu}
OUT=${1:-$HERE/build}
MODE=${MODE:-release}
case "$MODE" in
    release) OPT_FLAGS="-O2" ; DEBUG_DEFINE="" ; FLAVOR="release" ;;
    debug)   OPT_FLAGS="-O0 -g" ; DEBUG_DEFINE="-DSMCNVG_DEBUG=1" ; FLAVOR="debug" ;;
    *) echo "STOP: MODE must be release or debug"; exit 2 ;;
esac

[ -d "$KHDR" ] || { echo "STOP: no kernel headers in $SDK"; exit 1; }
[ -d "$VSMCDIR/VirtualSMCSDK" ] || { echo "STOP: VirtualSMC SDK not found at $VSMCDIR (set VSMCDIR)"; exit 1; }
[ -d "$LILUDIR/Headers" ] || { echo "STOP: Lilu headers not found at $LILUDIR (set LILUDIR)"; exit 1; }


KEXT="$OUT/SMCNvidiaGPU.kext"
rm -rf "$KEXT"
mkdir -p "$KEXT/Contents/MacOS"

echo "== compile"
xcrun clang++ -arch x86_64 -fapple-kext -mkernel -nostdinc -I"$KHDR" -I"$HERE" -I"$VSMCDIR" -I"$LILUDIR" \
    -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT \
    -std=c++17 -fno-rtti -fno-exceptions -fno-builtin -fno-common $OPT_FLAGS $DEBUG_DEFINE \
    -Wall -Wno-unused-parameter -Wno-sign-conversion -Wno-shadow \
    -c "$HERE/SMCNvidiaGPU.cpp" -o "$OUT/smcngpu.o"

echo "== link"
xcrun clang++ -arch x86_64 -fapple-kext -nostdlib -Xlinker -kext ${KLIB[@]+"${KLIB[@]}"} \
    -lkmodc++ -lkmod -lcc_kext \
    "$OUT/smcngpu.o" -o "$KEXT/Contents/MacOS/SMCNvidiaGPU"

cp "$HERE/Info.plist" "$KEXT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SMCNvidiaGPUFlavor string $FLAVOR" "$KEXT/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :SMCNvidiaGPUFlavor $FLAVOR" "$KEXT/Contents/Info.plist"
chmod 644 "$KEXT/Contents/Info.plist"
chmod 755 "$KEXT" "$KEXT/Contents" "$KEXT/Contents/MacOS" "$KEXT/Contents/MacOS/SMCNvidiaGPU"
xattr -cr "$KEXT" 2>/dev/null || true
codesign --force --sign - "$KEXT"
codesign --verify --strict "$KEXT"

echo "SMCNvidiaGPU.kext [$FLAVOR]  $(stat -f %z "$KEXT/Contents/MacOS/SMCNvidiaGPU") B  version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$KEXT/Contents/Info.plist")  uuid $(dwarfdump --uuid "$KEXT/Contents/MacOS/SMCNvidiaGPU" | awk '{print $2}')"
echo "$KEXT"
