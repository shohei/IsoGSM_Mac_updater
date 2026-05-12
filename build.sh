#!/bin/sh
#
#  IsoGSM macOS arm64 MPI build script
#  Run from anywhere: sh /path/to/IsoGSM_Mac/build.sh
#
set -e

# Detect IsoGSM_Mac directory from script location (works for any user/path)
ISOGSM_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "IsoGSM_Mac directory: $ISOGSM_DIR"
echo ""

echo "=== Step 1: Configure libs (regenerates Makefiles with correct paths) ==="
( cd "$ISOGSM_DIR/libs" && ./configure-libs ) || exit 1

echo ""
echo "=== Step 2: Apply source patches ==="
cd "$ISOGSM_DIR"
patch -p1 -N < fix_segfault_macos_arm64.patch  || echo "(already applied or partial - continuing)"
patch -p1 -N < fix_mpi_parallel_macos.patch     || echo "(already applied or partial - continuing)"

echo ""
echo "=== Step 3: Build libraries and utilities (arm64) ==="
# make clean removes stale x86_64 objects; make rebuilds as arm64 and
# copies each .a to libs/lib/ and each .x to libs/etc/.
( cd "$ISOGSM_DIR/libs" && make clean && make ) || exit 1

echo ""
echo "=== Step 4: Fix symlinks in _par source directories ==="
# Must run BEFORE configure-model: makedefine scans src/*_par/*.F to build
# OBJS_GSML etc. in define.h -> mdlvars.sed -> Makefile substitution.
for pardir in fcst gsml sfcl; do
    SRCDIR="$ISOGSM_DIR/gsm/src/${pardir}"
    PARDIR="$ISOGSM_DIR/gsm/src/${pardir}_par"
    echo "  fixing ${pardir}_par ..."
    find "$PARDIR" -name "*.F" -size 0 -delete 2>/dev/null || true
    rm -f "$PARDIR"/*.o "$PARDIR"/*.for "$PARDIR"/*.s 2>/dev/null || true
    for f in "$SRCDIR"/*.F; do
        [ -f "$f" ] && ln -fs "$f" "$PARDIR/${f##*/}"
    done
done
echo "  done"

echo ""
echo "=== Step 5: Configure gsm (regenerates Makefiles under gsm/src/) ==="
( cd "$ISOGSM_DIR/gsm" && ./configure-model ) || exit 1

echo ""
echo "=== Step 6: Build gsm model binaries ==="
# make clean removes stale objects and broken symlinks from gsm/bin/.
# make builds in the correct order:
#   share -> ... -> gsml -> fcst  (GSM_PROGS, includes sfc0)
#   mpi -> sfcl_par -> gsml_par -> fcst_par  (GSM_MP_PROGS)
( cd "$ISOGSM_DIR/gsm" && make clean && make ) || exit 1

echo ""
echo "=== Step 7: Code-sign binaries (macOS arm64) ==="
codesign --sign - --force "$ISOGSM_DIR/gsm/bin/fcst_t62k28_n8.x"
codesign --sign - --force "$ISOGSM_DIR/gsm/bin/sfc0.x"

echo ""
echo "=== Step 8: Generate run scripts ==="
( cd "$ISOGSM_DIR/gsm_runs" && ./configure-scr gsm ) || exit 1

echo ""
echo "=== Build complete. To run: ==="
echo "  cd $ISOGSM_DIR/gsm_runs && ./gsm"
