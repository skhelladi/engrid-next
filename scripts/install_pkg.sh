#!/usr/bin/env bash
# install_pkg.sh — Install system deps, Qt env vars and build VTK (Qt6 support)
# Supports macOS and Linux. See README.md for VTK requirements (VTK 9.5 recommended with Qt6 support).
# Also installs CGAL (required) and optionally builds Netgen (for tetrahedral meshing).
# All downloaded sources, builds and installations are in ./3rdparty/ relative to the project root.
# Incremental builds: only downloads/clones if not present, rebuilds only if configuration changed.
# Usage:
#   ./scripts/install_pkg.sh [--quiet] [--clean] [--prefix ./3rdparty] [--qt-dir /path/to/Qt] [--vtk-version 9.5.0]
#   ./scripts/install_pkg.sh --help
# Features:
#  - Detects OS (Linux/macOS)
#  - Checks for CMake availability (uses existing installation)
#  - Installs common build dependencies (apt/brew) including CGAL
#  - Builds VTK from source with Qt6 support, optimized flags (incremental)
#  - Optionally builds Netgen for tetrahedral meshing support (incremental)
#  - Sets environment variables for Qt and VTK and prints verification steps
#  - Supports --clean to remove install dirs (preserves sources/builds) and --quiet for non-verbose mode
#  - Detailed logging and error messages

set -euo pipefail
IFS=$' \n\t'

# Default configuration
QUIET=0
CLEAN=0
NO_SUDO=0
PREFIX="$(pwd)/3rdparty"
QT_DIR=""
VTK_VERSION="9.5.2"
SKIP_VTK=0
SKIP_NETGEN=0
BUILD_JOBS=0
TMPDIR="/tmp/engrid_install_$$"

# Default macOS Qt path requested by user
DEFAULT_MAC_QT_DIR="/Users/khelladi/Qt/6.10.0/macos"

usage() {
  cat <<EOF
Usage: $0 [options]
Options:
  --quiet            : run silently (minimal output)
  --clean            : remove install directories (preserves sources and builds for faster rebuilds)
  --prefix DIR       : installation prefix for libraries (default: $(pwd)/3rdparty)
  --qt-dir DIR       : path to Qt6 (default on macOS: $DEFAULT_MAC_QT_DIR)
  --vtk-version VER  : VTK version to build (default: $VTK_VERSION)
  --skip-vtk         : skip building VTK (useful when you have VTK preinstalled)
  --skip-netgen      : skip building Netgen (useful when you have Netgen preinstalled)
  --no-sudo          : don't use sudo even if available
  --help             : show this help and exit
EOF
}

log() { if [ "$QUIET" -eq 0 ]; then echo "[INFO]" "$@"; fi }
err() { echo "[ERROR]" "$@" >&2; }
fail() { err "$@"; exit 1; }

# parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1; shift ;;
    --clean) CLEAN=1; shift ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --qt-dir) QT_DIR="$2"; shift 2 ;;
    --vtk-version) VTK_VERSION="$2"; shift 2 ;;
    --skip-vtk) SKIP_VTK=1; shift ;;
    --skip-netgen) SKIP_NETGEN=1; shift ;;
    --no-sudo) NO_SUDO=1; shift ;;
    --help) usage; exit 0 ;;
    *) err "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

# helper to detect OS
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *) fail "Unsupported OS: $(uname -s)" ;;
  esac
}

OS=$(detect_os)
log "Detected OS: $OS"

# number of build threads
if [ $BUILD_JOBS -eq 0 ]; then
  if [ "$OS" = "macos" ]; then
    BUILD_JOBS=$(sysctl -n hw.ncpu)
  else
    BUILD_JOBS=$(nproc 2>/dev/null || echo 4)
  fi
fi

# sudo wrapper
SUDO=""
if [ "$OS" != "macos" ] && [ "$NO_SUDO" -eq 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO=sudo
  fi
fi

# cleanup routine
cleanup() {
  log "Cleaning temporary directories..."
  rm -rf "$TMPDIR"
}

trap cleanup EXIT

if [ "$CLEAN" -eq 1 ]; then
  log "Cleaning requested..."
  rm -rf "$TMPDIR"
  # Remove installed libraries but keep source and build directories for incremental builds
  rm -rf "$PREFIX/vtk-$VTK_VERSION" "$PREFIX/netgen" || true
  log "Clean complete. Source and build directories preserved in $PREFIX for faster rebuilds."
  exit 0
fi

mkdir -p "$TMPDIR"

# check for brew on macOS
check_brew() {
  if ! command -v brew >/dev/null 2>&1; then
    err "Homebrew not found. Please install Homebrew (https://brew.sh/) or run with --no-sudo and install packages manually."
    return 1
  fi
  return 0
}

# compare semver
version_ge() {
  # returns 0 if $1 >= $2
  printf "%s\n%s\n" "$1" "$2" | sort -V -C
}

check_cmake() {
  if command -v cmake >/dev/null 2>&1; then
    CMAKE_VER_RAW=$(cmake --version | head -n1 | awk '{print $3}')
    log "Found CMake $CMAKE_VER_RAW"
    return 0
  else
    log "CMake not found. Please install CMake manually."
    fail "CMake is required but not found"
  fi
}

install_system_deps() {
  log "Installing system dependencies..."
  if [ "$OS" = "macos" ]; then
    check_brew || fail "Homebrew is required for macOS operation."
    $SUDO brew update >/dev/null 2>&1 || true
    $SUDO brew install -q git wget pkg-config openssl zlib libpng jpeg cmake python3 cgal netgen || true
    # Install Qt6 via brew if user hasn't provided an explicit Qt dir
    if [ -z "$QT_DIR" ]; then
      log "Installing Qt (brew package qt@6)"
      $SUDO brew install -q qt@6 || true
      # Homebrew path for qt@6 — do not assume exact versioned path
      QT_BREW_DIR=$(brew --prefix qt@6 2>/dev/null || true)
      if [ -n "$QT_BREW_DIR" ]; then
        QT_DIR="$QT_BREW_DIR"
        log "Detected Qt from Homebrew: $QT_DIR"
      fi
    fi
  else
    # Linux apt-based install
    if command -v apt-get >/dev/null 2>&1; then
      $SUDO apt-get update -qq
      $SUDO apt-get install -y -qq build-essential git wget curl pkg-config ca-certificates \ 
        libgl1-mesa-dev libx11-dev libxrandr-dev libxcb1-dev libx11-xcb-dev libxcb-render0-dev libxcb-shm0-dev \ 
        libxcb-xfixes0-dev libxkbcommon-dev libfontconfig1-dev libssl-dev zlib1g-dev libjpeg-dev libtiff-dev \ 
        libcgal-dev || true
    elif command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y gcc gcc-c++ make git wget pkgconfig libX11-devel libXrandr-devel libxcb-devel libX11-xcb libXcursor-devel CGAL-devel || true
    else
      err "Unsupported package manager. Install build essentials, X11/OpenGL headers, and CGAL manually."
    fi

    if [ -z "$QT_DIR" ]; then
      log "No QT_DIR provided. Please install Qt6 and pass --qt-dir /path/to/Qt6 or set QT_DIR env var."
    fi
  fi

  # Final quick sanity checks
  if [ -n "$QT_DIR" ]; then
    if [ -d "$QT_DIR" ]; then
      log "Using Qt dir: $QT_DIR"
    else
      err "QT_DIR specified ($QT_DIR) does not exist. Please install Qt6 or pass correct path with --qt-dir."
    fi
  fi
}

build_vtk() {
  if [ "$SKIP_VTK" -eq 1 ]; then
    log "Skipping VTK build as requested (--skip-vtk)."
    return 0
  fi

  VTK_INSTALL="$PREFIX/vtk-$VTK_VERSION"

  # Check if VTK is already installed with correct configuration
  NEED_REBUILD=0
  VTK_INSTALL_TMP="$VTK_INSTALL.new"
  if [ -d "$VTK_INSTALL" ]; then
    log "VTK installation found at $VTK_INSTALL. Checking configuration..."
    if [ -d "$VTK_INSTALL/lib/cmake" ] && ls "$VTK_INSTALL/lib/cmake" 2>/dev/null | grep -i vtk >/dev/null 2>&1; then
      # Detect Qt GUI support by checking for GUISupportQt libs or cmake markers
      if ls "$VTK_INSTALL/lib" 2>/dev/null | grep -i "libvtkGUISupportQt" >/dev/null 2>&1 || grep -r "VTK_GUISupportQt" "$VTK_INSTALL/lib/cmake" >/dev/null 2>&1; then
        log "VTK already built with Qt support. Skipping build."
        return 0
      else
        log "VTK found but Qt support not detected. Will build new VTK into temporary dir ($VTK_INSTALL_TMP) and keep existing install until the new one is verified."
        NEED_REBUILD=1
      fi
    else
      log "VTK directory exists but configuration incomplete. Will build into temporary dir ($VTK_INSTALL_TMP)."
      NEED_REBUILD=1
    fi
  else
    log "No existing VTK installation found. Will build into temporary dir ($VTK_INSTALL_TMP)."
    NEED_REBUILD=1
  fi
  # If no rebuild needed we already returned above, otherwise continue to build into $VTK_INSTALL_TMP

  log "Building VTK $VTK_VERSION from source in 3rdparty/"

  VTK_SRC="$PREFIX/vtk-src"
  VTK_BUILD="$PREFIX/vtk-build"

  # Only clone if source doesn't exist
  if [ ! -d "$VTK_SRC" ]; then
    git clone --depth 1 --branch "v$VTK_VERSION" https://github.com/Kitware/VTK.git "$VTK_SRC" || fail "Failed to clone VTK repo"
  else
    log "VTK source already exists at $VTK_SRC"
  fi

  # Prepare VTK build dir: reuse if configuration matches, otherwise recreate
  if [ -d "$VTK_BUILD" ]; then
    log "VTK build dir exists at $VTK_BUILD. Checking CMakeCache..."
    if [ -f "$VTK_BUILD/CMakeCache.txt" ]; then
      if grep -q "VTK_GROUP_ENABLE_Qt:BOOL=YES" "$VTK_BUILD/CMakeCache.txt" || grep -q "VTK_MODULE_ENABLE_VTK_GUISupportQt:BOOL=YES" "$VTK_BUILD/CMakeCache.txt"; then
        log "Existing build appears configured for Qt support; reusing build dir."
      else
        log "Existing build dir configuration does not match desired Qt support. Removing build dir."
        rm -rf "$VTK_BUILD"
        mkdir -p "$VTK_BUILD"
      fi
    else
      log "Existing build dir found but no CMakeCache.txt; recreating build dir."
      rm -rf "$VTK_BUILD"
      mkdir -p "$VTK_BUILD"
    fi
  else
    mkdir -p "$VTK_BUILD"
  fi

  QT_CMAKE_DIR=""
  # Try to discover Qt6 CMake dir
  if [ -n "$QT_DIR" ]; then
    # Common layout: <QT_DIR>/lib/cmake/Qt6
    if [ -d "$QT_DIR/lib/cmake/Qt6" ]; then
      QT_CMAKE_DIR="$QT_DIR/lib/cmake/Qt6"
    elif [ -d "$QT_DIR/lib/cmake/Qt6" ]; then
      QT_CMAKE_DIR="$QT_DIR/lib/cmake/Qt6"
    elif [ -d "$QT_DIR/6" ]; then
      # e.g. /Users/.../Qt/6.10.0/macos
      if [ -d "$QT_DIR/6/lib/cmake/Qt6" ]; then
        QT_CMAKE_DIR="$QT_DIR/6/lib/cmake/Qt6"
      fi
    fi
  fi

  if [ -z "$QT_CMAKE_DIR" ]; then
    log "Could not automatically discover Qt CMake dir. You may need to set --qt-dir to a Qt6 installation that contains lib/cmake/Qt6."
  else
    log "Using Qt CMake dir: $QT_CMAKE_DIR"
  fi

  cd "$VTK_BUILD"
  cmake -S "$VTK_SRC" -B . \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$VTK_INSTALL_TMP" \
    -DVTK_GROUP_ENABLE_Qt=YES \
    -DVTK_MODULE_ENABLE_VTK_GUISupportQt=YES \
    -DQt6_DIR="$QT_CMAKE_DIR" \
    -DVTK_WRAP_PYTHON=OFF \
    -DVTK_ENABLE_TESTING=OFF \
    -DVTK_DEFAULT_RENDERING_BACKEND=OpenGL2 \
    -DCMAKE_INSTALL_RPATH="\$ORIGIN/.." || fail "CMake configuration for VTK failed"

  log "Compiling VTK (jobs: $BUILD_JOBS)..."
  cmake --build . -- -j$BUILD_JOBS || fail "Building VTK failed"

  log "Installing VTK into temporary directory $VTK_INSTALL_TMP"
  cmake --install . --prefix "$VTK_INSTALL_TMP" || fail "VTK install failed"

  # Post-install verification in temp dir
  if [ -d "$VTK_INSTALL_TMP/lib/cmake/vtk-$VTK_VERSION" ] || ls "$VTK_INSTALL_TMP/lib/cmake/" | grep -i vtk >/dev/null 2>&1; then
    log "VTK successfully installed into $VTK_INSTALL_TMP"
    # Swap into place, keeping existing install as backup
    if [ -d "$VTK_INSTALL" ]; then
      BACKUP="$VTK_INSTALL.bak.$(date +%s)"
      log "Backing up existing VTK install to $BACKUP"
      mv "$VTK_INSTALL" "$BACKUP" || fail "Failed to backup previous VTK install"
    fi
    log "Moving new VTK into final location $VTK_INSTALL"
    mv "$VTK_INSTALL_TMP" "$VTK_INSTALL" || fail "Failed to move VTK into final location"
    log "VTK installed at $VTK_INSTALL"
    log "Set VTK_DIR to $VTK_INSTALL/lib/cmake/vtk-$VTK_VERSION (or existing subdir)"
  else
    err "VTK not found in expected install location ($VTK_INSTALL_TMP). Check build output."
  fi

  # export environment hints
  echo "# Add to your shell profile (e.g., ~/.bashrc or ~/.zshrc):"
  echo "# export VTK_DIR=$VTK_INSTALL/lib/cmake/<vtk-version-folder>"
  echo "# export CMAKE_PREFIX_PATH=\$VTK_INSTALL/\$CMAKE_PREFIX_PATH"
}

build_netgen() {
  if [ "$SKIP_NETGEN" -eq 1 ]; then
    log "Skipping Netgen build as requested (--skip-netgen)."
    return 0
  fi

  log "Building Netgen from source in 3rdparty/"

  NETGEN_SRC="$PREFIX/netgen-src"
  NETGEN_BUILD="$PREFIX/netgen-build"
  NETGEN_INSTALL="$PREFIX/netgen"
  NETGEN_INSTALL_TMP="$NETGEN_INSTALL.new"

  # Non-destructive check: if a correctly-configured build+install exists, skip; otherwise plan to build
  NEED_REBUILD=0
  if [ -d "$NETGEN_SRC" ]; then
    log "Netgen source found at $NETGEN_SRC. Checking build configuration..."
    if [ -f "$NETGEN_SRC/build/CMakeCache.txt" ]; then
      if grep -q "USE_PYTHON:BOOL=ON" "$NETGEN_SRC/build/CMakeCache.txt" && grep -q "USE_GUI:BOOL=OFF" "$NETGEN_SRC/build/CMakeCache.txt"; then
        log "Netgen already built with Python support and GUI disabled. Checking installation..."
        if [ -d "$NETGEN_INSTALL/lib" ] || [ -d "$NETGEN_INSTALL/lib64" ] || [ -d "$NETGEN_INSTALL/Contents/MacOS" ]; then
          log "Netgen already installed at $NETGEN_INSTALL. Skipping build."
          return 0
        else
          log "Netgen built but not installed. Installing into temporary dir $NETGEN_INSTALL_TMP"
          cd "$NETGEN_SRC/build" || fail "Cannot cd to $NETGEN_SRC/build"
          cmake --install . --prefix "$NETGEN_INSTALL_TMP" || fail "Netgen install failed"
          if [ -d "$NETGEN_INSTALL_TMP/lib" ] || [ -d "$NETGEN_INSTALL_TMP/lib64" ] || [ -d "$NETGEN_INSTALL_TMP/Contents/MacOS" ]; then
            if [ -d "$NETGEN_INSTALL" ]; then
              BACKUP="$NETGEN_INSTALL.bak.$(date +%s)"
              log "Backing up existing Netgen install to $BACKUP"
              mv "$NETGEN_INSTALL" "$BACKUP" || fail "Failed to backup previous Netgen install"
            fi
            log "Moving new Netgen into final location $NETGEN_INSTALL"
            mv "$NETGEN_INSTALL_TMP" "$NETGEN_INSTALL" || fail "Failed to move Netgen into final location"
            log "Netgen installed at $NETGEN_INSTALL"
            return 0
          else
            err "Netgen install into $NETGEN_INSTALL_TMP didn't produce expected files. Check build output."
          fi
        fi
      else
        log "Netgen build configuration does not match requirements (Python ON, GUI OFF). Reconfiguring build..."
        NEED_REBUILD=1
        rm -rf "$NETGEN_SRC/build"
      fi
    else
      log "No Netgen build directory found or incomplete. Will configure and build into temporary install dir $NETGEN_INSTALL_TMP"
      NEED_REBUILD=1
    fi
  else
    log "Cloning Netgen source..."
    git clone --depth 1 https://github.com/NGSolve/netgen.git "$NETGEN_SRC" || fail "Failed to clone Netgen repo"
    NEED_REBUILD=1
  fi

  # Prepare build dir: reuse if already configured with required flags
  if [ "$NEED_REBUILD" -eq 1 ]; then
    if [ -d "$NETGEN_BUILD" ]; then
      log "Netgen build dir exists at $NETGEN_BUILD. Checking CMakeCache..."
      if [ -f "$NETGEN_BUILD/CMakeCache.txt" ] && grep -q "USE_PYTHON:BOOL=ON" "$NETGEN_BUILD/CMakeCache.txt" && grep -q "USE_GUI:BOOL=OFF" "$NETGEN_BUILD/CMakeCache.txt"; then
        log "Existing build appears configured for Python and GUI=OFF; reusing build dir."
      else
        log "Existing build dir configuration does not match desired flags. Recreating build dir."
        rm -rf "$NETGEN_BUILD"
        mkdir -p "$NETGEN_BUILD"
      fi
    else
      mkdir -p "$NETGEN_BUILD"
    fi

    cd "$NETGEN_BUILD" || fail "Cannot cd to $NETGEN_BUILD"

    cmake "$NETGEN_SRC" -S "$NETGEN_SRC" -B . \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$NETGEN_INSTALL_TMP" \
      -DUSE_GUI=OFF \
      -DUSE_PYTHON=ON \
      -DUSE_MPI=ON \
      -DPYTHON_EXECUTABLE=$(which python3 2>/dev/null || which python) || fail "CMake configuration for Netgen failed"

    log "Compiling Netgen (jobs: $BUILD_JOBS)..."
    cmake --build . -- -j$BUILD_JOBS || fail "Building Netgen failed"

    log "Installing Netgen into temporary directory $NETGEN_INSTALL_TMP"
    cmake --install . --prefix "$NETGEN_INSTALL_TMP" || fail "Netgen install failed"

    # Post-install verification in temp dir and swap into place
    if [ -d "$NETGEN_INSTALL_TMP/lib" ] || [ -d "$NETGEN_INSTALL_TMP/lib64" ] || [ -d "$NETGEN_INSTALL_TMP/Contents/MacOS" ]; then
      if [ -d "$NETGEN_INSTALL" ]; then
        BACKUP="$NETGEN_INSTALL.bak.$(date +%s)"
        log "Backing up existing Netgen install to $BACKUP"
        mv "$NETGEN_INSTALL" "$BACKUP" || fail "Failed to backup previous Netgen install"
      fi
      log "Moving new Netgen into final location $NETGEN_INSTALL"
      mv "$NETGEN_INSTALL_TMP" "$NETGEN_INSTALL" || fail "Failed to move Netgen into final location"
      log "Netgen installed at $NETGEN_INSTALL"
    else
      err "Netgen not found in expected install location ($NETGEN_INSTALL_TMP). Check build output."
    fi
  fi

  # Post-install verification
  if [ -d "$NETGEN_INSTALL/lib" ] || [ -d "$NETGEN_INSTALL/lib64" ] || [ -d "$NETGEN_INSTALL/Contents/MacOS" ]; then
    log "Netgen installed at $NETGEN_INSTALL"
    log "Set CMAKE_PREFIX_PATH to include $NETGEN_INSTALL for Netgen support"
  else
    err "Netgen not found in expected install location ($NETGEN_INSTALL). Check build output."
  fi

  # export environment hints
  echo "# Add to your shell profile (e.g., ~/.bashrc or ~/.zshrc):"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "# export CMAKE_PREFIX_PATH=\$CMAKE_PREFIX_PATH:$NETGEN_INSTALL/Contents/Resources"
  else
    echo "# export CMAKE_PREFIX_PATH=\$CMAKE_PREFIX_PATH:$NETGEN_INSTALL"
  fi
}

verify_install() {
  log "Verifying core tools..."
  command -v git >/dev/null 2>&1 || fail "git not found"
  command -v cmake >/dev/null 2>&1 || fail "cmake not found"
  if [ -n "$QT_DIR" ]; then
    if [ -f "$QT_DIR/bin/qmake" ] || [ -d "$QT_DIR/lib/cmake/Qt6" ] ; then
      log "Qt OK: found under $QT_DIR"
    else
      err "Qt not found at $QT_DIR (no qmake or lib/cmake/Qt6)."
    fi
  fi
}

# Main flow
log "Starting installation (prefix: $PREFIX, VTK: $VTK_VERSION, Netgen: $([ "$SKIP_NETGEN" -eq 0 ] && echo "yes" || echo "skipped")"

check_cmake
install_system_deps
verify_install

if [ "$SKIP_VTK" -eq 0 ]; then
  build_vtk
else
  log "VTK build skipped by user request."
fi

if [ "$SKIP_NETGEN" -eq 0 ]; then
  build_netgen
else
  log "Netgen build skipped by user request."
fi

log "Installation complete. Temporary build files are in $TMPDIR (auto-removed on exit)."
log "All sources, builds and libraries are in: $PREFIX"
log "Recommended post-install steps:"
log "  - Add Qt to your environment: export QT_DIR=${QT_DIR:-<your-qt-dir>}"
log "  - For building enGrid, use CMAKE_PREFIX_PATH:"
if [ "$SKIP_VTK" -eq 0 ]; then
  log "    export CMAKE_PREFIX_PATH=\"$PREFIX/vtk-$VTK_VERSION:$CMAKE_PREFIX_PATH\""
fi
if [ "$SKIP_NETGEN" -eq 0 ]; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    log "    export CMAKE_PREFIX_PATH=\"$PREFIX/netgen/Contents/Resources:$CMAKE_PREFIX_PATH\""
  else
    log "    export CMAKE_PREFIX_PATH=\"$PREFIX/netgen:$CMAKE_PREFIX_PATH\""
  fi
fi
log "  - Then run: mkdir build && cd build && cmake -DUSE_NETGEN=ON ../src"
log "  - Add $PREFIX/bin and $PREFIX/cmake/bin to your PATH if you installed cmake under prefix"

exit 0
