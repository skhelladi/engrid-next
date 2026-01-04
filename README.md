# enGrid
*enGrid* is a mesh generation software with CFD applications in mind. It supports automatic prismatic boundary layer grids for Navier-Stokes simulations and has a Qt based GUI.

A [Doxygen](http://www.stack.nl/~dimitri/doxygen/index.html) created source code documentation can be found here:

http://todtnau.engits.de/engrid-doc/master/html

The documentation is updated automatically and should contain the correct documentation latest one day after a commit to the **master branch**.

## Building enGrid

Due to significant changes to the *enGrid* codebase, only the master branch version of *enGrid* is actively supported. The code now makes use of the CMake build system, which should simplify compilation.

The main dependencies for *enGrid* are:

* Qt 6
* VTK 9.5 (with Qt support)
* CMake
* CGAL
* Netgen (optional, for tetrahedral meshing)

VTK needs to be compiled with Qt support, as *enGrid* depends on QVTKOpenGLNativeWidget for Qt6 integration.

*enGrid* was successfully compiled on **Ubuntu 24.04** with the following dependency versions:

* Qt 6.9.1
* CMake 3.28.3
* VTK 9.5 (compiled with Qt6 support)
* CGAL 5.6
* Netgen 6.2

### Building VTK with Qt6 support

Download and build VTK 9.5 with Qt6 support:

```bash
git clone https://gitlab.kitware.com/vtk/vtk.git
cd vtk
git checkout v9.5.2
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release \
      -DVTK_GROUP_ENABLE_Qt=YES \
      -DVTK_MODULE_ENABLE_VTK_GUISupportQt=YES \
      -DCMAKE_INSTALL_PREFIX=/path/to/vtk-install \
      ..
make -j$(nproc)
make install
```

### Optional: Building Netgen for tetrahedral meshing

If you want tetrahedral meshing support, you can build Netgen:

```bash
git clone https://github.com/NGSolve/netgen.git
cd netgen
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release \
      -DUSE_GUI=OFF \
      -DUSE_PYTHON=OFF \
      -DUSE_OCC=OFF \
      -DCMAKE_INSTALL_PREFIX=/path/to/netgen-install \
      ..
make -j$(nproc)
make install
```

### Optional: Building Netgen for tetrahedral meshing

If you want tetrahedral meshing support, you can build Netgen:

```bash
git clone https://github.com/NGSolve/netgen.git
cd netgen
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release \
      -DUSE_GUI=OFF \
      -DUSE_PYTHON=OFF \
      -DUSE_OCC=OFF \
      -DCMAKE_INSTALL_PREFIX=/path/to/netgen-install \
      ..
make -j$(nproc)
make install
```

Then configure enGrid with Netgen support:

```bash
cmake -DUSE_NETGEN=ON \
      -DCMAKE_PREFIX_PATH="/path/to/qt6;/path/to/vtk-install;/path/to/netgen-install" \
      ../src
```

Alternatively, use the provided `install_pkg.sh` script which installs all dependencies in the `3rdparty/` directory:

```bash
./scripts/install_pkg.sh --qt-dir /path/to/Qt6
```

This will install VTK, Netgen, and other dependencies in `3rdparty/` and set up the environment for building enGrid.

### Configuring and Compiling enGrid

*enGrid* can be configured and compiled in a separate build directory using:

```bash
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH="/path/to/qt6;/path/to/vtk-install" \
      ../src
make -j$(nproc)
make install
```

If you used `install_pkg.sh`, the dependencies are in `3rdparty/` and you can build with:

```bash
mkdir build && cd build
export CMAKE_PREFIX_PATH="$(pwd)/../3rdparty/netgen:$(pwd)/../3rdparty/vtk-9.5.2:$CMAKE_PREFIX_PATH"
cmake -DUSE_NETGEN=ON ../src
make -j$(nproc)
```

Or use ccmake for interactive configuration:

```bash
ccmake ../src
```

Press `[c]` to configure, `[c]` again to accept changes, and `[g]` to generate Makefiles and exit. Then compile:

```bash
make -j$(nproc) install
```

### Running enGrid

After installation, you can run enGrid with:

```bash
export LD_LIBRARY_PATH=/path/to/vtk-install/lib:$LD_LIBRARY_PATH
./engrid
```

Make sure VTK libraries are in your LD_LIBRARY_PATH.
