# Copyright (C) Canonical, Ltd.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Helpful docs:
# https://cmake.org/Wiki/CMake:Component_Install_With_CPack
# https://cmake.org/Wiki/CMake:CPackConfiguration
#
# Vital concept to understand are "Components" - a component is a collection of files to be installed.
# Any file to be packaged for installation must be part of a component - note the COMPONENT flag for
# "install". CPack then includes it in the generated package, to be installed at the destination
# specified in the "install" (plus a CPack-only prefix set below).
#
# Components are intended to be self-contained, as they may be installed individually. Components also
# smap directly to the options made visible to the user in the installer.
#

set(CPACK_WARN_ON_ABSOLUTE_INSTALL_DESTINATION ON) # helps avoid errors

set(CPACK_COMPONENTS_GROUPING ALL_COMPONENTS_IN_ONE)
set(CPACK_COMPONENTS_ALL hyperpassd hyperpass hyperpass_gui)

set(CPACK_COMPONENT_HYPERPASSD_DISPLAY_NAME "Hyperpass Daemon")
set(CPACK_COMPONENT_HYPERPASSD_DESCRIPTION
   "Background process that creates and manages virtual machines")
set(CPACK_COMPONENT_HYPERPASS_DISPLAY_NAME "Clients (CLI and GUI)")
set(CPACK_COMPONENT_HYPERPASS_DESCRIPTION
   "Command line tool to talk to the hyperpass daemon")
set(CPACK_COMPONENT_HYPERPASS_GUI_DISPLAY_NAME "Hyperpass Desktop GUI")
set(CPACK_COMPONENT_HYPERPASS_GUI_DESCRIPTION
    "Desktop client for Hyperpass")

set(CPACK_COMPONENT_HYPERPASSD_REQUIRED TRUE)
set(CPACK_COMPONENT_HYPERPASS_REQUIRED TRUE)
set(CPACK_COMPONENT_HYPERPASS_GUI_REQUIRED TRUE)

# set default CPack Packaging options
set(CPACK_PACKAGE_NAME              "hyperpass")
set(CPACK_PACKAGE_VENDOR            "elemento")
set(CPACK_PACKAGE_CONTACT           "contact@elemento.cloud")
set(CPACK_PACKAGE_VERSION           "${MULTIPASS_VERSION}")

if (APPLE)
  set(CPACK_PACKAGE_VERSION "${CPACK_PACKAGE_VERSION}.${HOST_ARCH}")
endif()

#set(CPACK_PACKAGE_ICON              "${PROJECT_SOURCE_DIR}/cmake/sac_logo.png")

if (CMAKE_BUILD_TYPE STREQUAL "Release")
  set(CPACK_STRIP_FILES 1)
endif ()

# set (CPACK_PACKAGE_DESCRIPTION_FILE ...)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Easily create, control and connect to cloud instances")

if (MSVC)
  # qemu-img.exe (used to convert qcow images to VHDX) is built by the vcpkg
  # qemu overlay port and installed into the hyperpassd component by
  # src/cmake/qemu-img-install-and-copy.cmake, so no separate lookup, shim
  # resolution or dependency fixup is needed here. The vcpkg binary is built
  # fully statically (it links only system DLLs), so fixup_bundle is unnecessary.

  # InstallRequiredSystemLibraries finds the VC redistributable dlls shipped with the Visual Studio compiler tools
  # and creats an install(PROGRAMS ...) rule using the destination and component IDs setup below.
  set(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION bin)
  set(CMAKE_INSTALL_SYSTEM_RUNTIME_COMPONENT hyperpassd)
  if(CMAKE_BUILD_TYPE_LOWER STREQUAL "debug")
    set(CMAKE_INSTALL_DEBUG_LIBRARIES TRUE)
    set(CMAKE_INSTALL_UCRT_LIBRARIES TRUE)
  endif()
  include(InstallRequiredSystemLibraries)

  set(CPACK_SOURCE_DIR "${CMAKE_SOURCE_DIR}")
  set(CPACK_BUILD_TYPE "${CMAKE_BUILD_TYPE}")

  set(CPACK_GENERATOR External)
  set(CPACK_EXTERNAL_ENABLE_STAGING ON)

  set(CPACK_EXTERNAL_PACKAGE_SCRIPT "${CMAKE_SOURCE_DIR}/packaging/windows/CPackExternal.cmake")
endif()

if(APPLE)
  set(CPACK_OSX_DEPLOYMENT_TARGET "${CMAKE_OSX_DEPLOYMENT_TARGET}")
  set(CPACK_RESOURCE_FILE_WELCOME "${PROJECT_SOURCE_DIR}/packaging/macos/WELCOME.html")
  set(CPACK_RESOURCE_FILE_LICENSE "${PROJECT_SOURCE_DIR}/packaging/macos/LICENCE.html")
  set(CPACK_RESOURCE_FILE_README "${PROJECT_SOURCE_DIR}/packaging/macos/README.html")
  set(CPACK_GENERATOR "productbuild")
  set(CPACK_productbuild_COMPONENT_INSTALL ON)

  set(CPACK_PACKAGING_INSTALL_PREFIX   "/Library/Application Support/com.elemento.hyperpass")
  list(APPEND CPACK_INSTALL_COMMANDS "bash -x ${CMAKE_SOURCE_DIR}/packaging/macos/fixup-qemu-and-deps.sh ${CMAKE_BINARY_DIR}")

  set(HYPERPASSD_PLIST "com.elemento.hyperpassd.plist")
  configure_file("${CMAKE_SOURCE_DIR}/packaging/macos/${HYPERPASSD_PLIST}.in"
                 "${CMAKE_BINARY_DIR}/${HYPERPASSD_PLIST}" @ONLY)
  configure_file("${CMAKE_SOURCE_DIR}/packaging/macos/preinstall-hyperpassd.sh.in"
                 "${CMAKE_BINARY_DIR}/preinstall-hyperpassd.sh" @ONLY)
  configure_file("${CMAKE_SOURCE_DIR}/packaging/macos/postinstall-hyperpassd.sh.in"
                 "${CMAKE_BINARY_DIR}/postinstall-hyperpassd.sh" @ONLY)
  configure_file("${CMAKE_SOURCE_DIR}/packaging/macos/postinstall-hyperpass.sh.in"
                 "${CMAKE_BINARY_DIR}/postinstall-hyperpass.sh" @ONLY)
  configure_file("${CMAKE_SOURCE_DIR}/packaging/macos/postinstall-hyperpass-gui.sh.in"
                 "${CMAKE_BINARY_DIR}/postinstall-hyperpass-gui.sh" @ONLY)

  install(FILES "${CMAKE_BINARY_DIR}/${HYPERPASSD_PLIST}" DESTINATION Resources COMPONENT hyperpassd)
  install(DIRECTORY "${CMAKE_SOURCE_DIR}/completions" DESTINATION Resources COMPONENT hyperpass)
  install(DIRECTORY "${CMAKE_BINARY_DIR}/lib/" DESTINATION lib COMPONENT hyperpassd)

  set(CPACK_COMPONENT_HYPERPASS_GUI_PLIST "${CMAKE_SOURCE_DIR}/packaging/macos/hyperpass-gui-component.plist")

  set(CPACK_PREFLIGHT_HYPERPASSD_SCRIPT  "${CMAKE_BINARY_DIR}/preinstall-hyperpassd.sh")
  set(CPACK_POSTFLIGHT_HYPERPASSD_SCRIPT "${CMAKE_BINARY_DIR}/postinstall-hyperpassd.sh")
  set(CPACK_POSTFLIGHT_HYPERPASS_SCRIPT  "${CMAKE_BINARY_DIR}/postinstall-hyperpass.sh")
  set(CPACK_POSTFLIGHT_HYPERPASS_GUI_SCRIPT  "${CMAKE_BINARY_DIR}/postinstall-hyperpass-gui.sh")

  # Cleans up the installed package
  set(CPACK_PRE_BUILD_SCRIPTS "${CMAKE_SOURCE_DIR}/packaging/cleanup.cmake")

  # Signs the binaries using ad-hoc signing
  set(CPACK_POST_BUILD_SCRIPTS "${CMAKE_SOURCE_DIR}/packaging/macos/post_build.cmake")

  # CPack doesn't support a direct way to customise the Distribution.dist file, but the template
  # CPack.distribution.dist.in is searched for in the CMAKE_MODULE_PATH before CMAKE_ROOT, so as a hack,
  # point it to a local directory with our custom template
  set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/packaging/macos")

  install(FILES "${CMAKE_SOURCE_DIR}/packaging/macos/uninstall.sh"
          DESTINATION . COMPONENT hyperpassd)
endif()

# must be last
include(CPack)
