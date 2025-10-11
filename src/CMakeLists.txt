# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# +                                                                      +
# + This file is part of enGrid.                                         +
# +                                                                      +
# + Copyright 2008-2014 enGits GmbH                                      +
# +                                                                      +
# + enGrid is free software: you can redistribute it and/or modify       +
# + it under the terms of the GNU General Public License as published by +
# + the Free Software Foundation, either version 3 of the License, or    +
# + (at your option) any later version.                                  +
# +                                                                      +
# + enGrid is distributed in the hope that it will be useful,            +
# + but WITHOUT ANY WARRANTY; without even the implied warranty of       +
# + MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the        +
# + GNU General Public License for more details.                         +
# +                                                                      +
# + You should have received a copy of the GNU General Public License    +
# + along with enGrid. If not, see <http://www.gnu.org/licenses/>.       +
# +                                                                      +
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


cmake_minimum_required(VERSION 3.16)

# Hint for custom Qt6 location
set(QT_DIR "/opt/Qt/6.9.1/gcc_64")
list(APPEND CMAKE_PREFIX_PATH ${QT_DIR})

# limit configuration types (must be done before project() statement)
set(CMAKE_CONFIGURATION_TYPES "Debug;Release" CACHE STRING "limited config" FORCE)

project(ENGRID)

# --- Qt6 Configuration ---
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# ---

set(CMAKE_VERBOSE_MAKEFILE no)

# export build setup for development environment
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(ENGRID_MAJOR_VERSION 2)
set(ENGRID_MINOR_VERSION 0)
set(ENGRID_PATCH_VERSION 0)
set(ENGRID_VERSION ${ENGRID_MAJOR_VERSION}.${ENGRID_MINOR_VERSION}.${ENGRID_PATCH_VERSION})

exec_program(
    "git"
    ${CMAKE_CURRENT_SOURCE_DIR}
    ARGS "describe"
    OUTPUT_VARIABLE GIT_SHA1)
string(REGEX MATCH "-g.*$" GIT_SHA1 "${GIT_SHA1}")
string(REGEX REPLACE "[-g]" "" GIT_SHA1 "${GIT_SHA1}" )
add_definitions( -DGIT_SHA1="${GIT_SHA1}" )

execute_process(
    COMMAND git symbolic-ref --short HEAD
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    OUTPUT_VARIABLE GIT_BRANCH
    OUTPUT_STRIP_TRAILING_WHITESPACE)
add_definitions( -DGIT_BRANCH="${GIT_BRANCH}" )

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Choose the type of build." FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Release")
endif()

# --- VTK Configuration ---
# Set VTK_DIR to point directly to the custom VTK build configuration
set(VTK_DIR "${CMAKE_SOURCE_DIR}/../3rdparty/vtk-9.5-qt6/lib/cmake/vtk-9.5")

find_package(VTK COMPONENTS
  RenderingCore
  ChartsCore
  CommonExecutionModel
  CommonTransforms
  CommonColor
  FiltersCore
  FiltersGeneral
  FiltersGeometry
  FiltersSources
  IOCore
  IOGeometry
  IOLegacy
  IOPLY
  IOXML
  GUISupportQt
  REQUIRED)

if("${VTK_VERSION}" VERSION_LESS 9.5)
  message(FATAL_ERROR "The VTK version is too old. EnGrid requires VTK 9.5 or higher for Qt6 support.")
endif()
# ---

if(NOT INITIAL_CONFIG)
  set(INITIAL_CONFIG "..." CACHE INTERNAL "hidden flag...")
  set(CMAKE_INSTALL_PREFIX $ENV{HOME}/local CACHE STRING "Install path prefix, prepended onto install directories." FORCE)
endif()

find_package(CGAL REQUIRED)
include(${CGAL_USE_FILE})

# --- Qt6 ---
find_package(Qt6 COMPONENTS Core Gui Widgets Network Xml REQUIRED)

# set include directory, add src directories
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/tetgen)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/libengrid)
include_directories(${CMAKE_CURRENT_BINARY_DIR}/libengrid)
include_directories(${CMAKE_CURRENT_SOURCE_DIR})
include_directories(${CMAKE_CURRENT_BINARY_DIR})
include_directories(${VTK_INCLUDE_DIRS})

option(PROFILING "add -g for profiling even in RELEASE configuration?" OFF)

if (${CMAKE_BUILD_TYPE} STREQUAL "Release")
  add_definitions(-DNDEBUG)
  add_definitions(-DQT_NO_DEBUG)
  remove_definitions(-DQT_DEBUG)
  if (PROFILING)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g")
  endif()
else()
  add_definitions(-DQT_DEBUG)
endif()

add_subdirectory(tetgen)
add_subdirectory(libengrid)

add_executable(engrid main.cpp libengrid/guimainwindow.ui)

set_target_properties(engrid PROPERTIES
    AUTOUIC ON
    AUTOMOC ON
    AUTORCC ON
)

target_include_directories(engrid PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/libengrid)
target_include_directories(engrid PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/libengrid/libengrid_autogen/include)

target_link_libraries(engrid PRIVATE
    libengrid
    tet
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::Network
    Qt6::Xml
    ${VTK_LIBRARIES}
)

install(TARGETS engrid DESTINATION bin)

install(
  FILES engrid.bash
  PERMISSIONS OWNER_EXECUTE OWNER_READ OWNER_WRITE GROUP_EXECUTE GROUP_READ
  DESTINATION bin
)


