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
set(CPACK_COMPONENTS_ALL elpd elp elp_gui)
if(ELP_ENABLE_API)
  list(APPEND CPACK_COMPONENTS_ALL elp_api)
endif()

set(CPACK_COMPONENT_ELPD_DISPLAY_NAME "Electros LaunchPad Daemon")
set(CPACK_COMPONENT_ELPD_DESCRIPTION
   "Background process that creates and manages virtual machines")
set(CPACK_COMPONENT_ELP_DISPLAY_NAME "Clients (CLI and GUI)")
set(CPACK_COMPONENT_ELP_DESCRIPTION
   "Command line tool to talk to the elp daemon")
set(CPACK_COMPONENT_ELP_GUI_DISPLAY_NAME "Electros LaunchPad Desktop GUI")
set(CPACK_COMPONENT_ELP_GUI_DESCRIPTION
    "Desktop client for Electros LaunchPad")
set(CPACK_COMPONENT_ELP_API_DISPLAY_NAME "Electros LaunchPad REST API")
set(CPACK_COMPONENT_ELP_API_DESCRIPTION
    "REST API sidecar that translates HTTP to the Electros LaunchPad daemon")

set(CPACK_COMPONENT_ELPD_REQUIRED TRUE)
set(CPACK_COMPONENT_ELP_REQUIRED TRUE)
set(CPACK_COMPONENT_ELP_GUI_REQUIRED TRUE)
if(ELP_ENABLE_API)
  set(CPACK_COMPONENT_ELP_API_REQUIRED TRUE)
endif()

# set default CPack Packaging options
set(CPACK_PACKAGE_NAME              "elp")
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
  # qemu overlay port and installed into the elpd component by
  # src/cmake/qemu-img-install-and-copy.cmake, so no separate lookup, shim
  # resolution or dependency fixup is needed here. The vcpkg binary is built
  # fully statically (it links only system DLLs), so fixup_bundle is unnecessary.

  # InstallRequiredSystemLibraries finds the VC redistributable dlls shipped with the Visual Studio compiler tools
  # and creats an install(PROGRAMS ...) rule using the destination and component IDs setup below.
  set(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION bin)
  set(CMAKE_INSTALL_SYSTEM_RUNTIME_COMPONENT elpd)
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

  set(CPACK_PACKAGING_INSTALL_PREFIX   "/Library/Application Support/com.elemento.elp")
  list(APPEND CPACK_INSTALL_COMMANDS "bash -x ${CMAKE_SOURCE_DIR}/packaging/macos/fixup-qemu-and-deps.sh ${CMAKE_BINARY_DIR}")

  set(ELPD_PLIST "com.elemento.elpd.plist")
  configure_file("${CMAKE_SOURCE_DIR}/packaging/macos/${ELPD_PLIST}.in"
                 "${CMAKE_BINARY_DIR}/${ELPD_PLIST}" @ONLY)
  configure_file("${CMAKE_SOURCE_DIR}/packaging/macos/preinstall-elpd.sh.in"
                 "${CMAKE_BINARY_DIR}/preinstall-elpd.sh" @ONLY)
  configure_file("${CMAKE_SOURCE_DIR}/packaging/macos/postinstall-elpd.sh.in"
                 "${CMAKE_BINARY_DIR}/postinstall-elpd.sh" @ONLY)
  configure_file("${CMAKE_SOURCE_DIR}/packaging/macos/postinstall-elp.sh.in"
                 "${CMAKE_BINARY_DIR}/postinstall-elp.sh" @ONLY)
  configure_file("${CMAKE_SOURCE_DIR}/packaging/macos/postinstall-elp-gui.sh.in"
                 "${CMAKE_BINARY_DIR}/postinstall-elp-gui.sh" @ONLY)

  install(FILES "${CMAKE_BINARY_DIR}/${ELPD_PLIST}" DESTINATION Resources COMPONENT elpd)
  install(DIRECTORY "${CMAKE_SOURCE_DIR}/completions" DESTINATION Resources COMPONENT elp)
  install(DIRECTORY "${CMAKE_BINARY_DIR}/lib/" DESTINATION lib COMPONENT elpd)

  set(CPACK_COMPONENT_ELP_GUI_PLIST "${CMAKE_SOURCE_DIR}/packaging/macos/elp-gui-component.plist")

  set(CPACK_PREFLIGHT_ELPD_SCRIPT  "${CMAKE_BINARY_DIR}/preinstall-elpd.sh")
  set(CPACK_POSTFLIGHT_ELPD_SCRIPT "${CMAKE_BINARY_DIR}/postinstall-elpd.sh")
  set(CPACK_POSTFLIGHT_ELP_SCRIPT  "${CMAKE_BINARY_DIR}/postinstall-elp.sh")
  set(CPACK_POSTFLIGHT_ELP_GUI_SCRIPT  "${CMAKE_BINARY_DIR}/postinstall-elp-gui.sh")

  if(ELP_ENABLE_API)
    set(ELP_API_PLIST "com.elemento.elp-api.plist")
    configure_file("${CMAKE_SOURCE_DIR}/packaging/macos/${ELP_API_PLIST}.in"
                   "${CMAKE_BINARY_DIR}/${ELP_API_PLIST}" @ONLY)
    configure_file("${CMAKE_SOURCE_DIR}/packaging/macos/postinstall-elp-api.sh.in"
                   "${CMAKE_BINARY_DIR}/postinstall-elp-api.sh" @ONLY)
    install(FILES "${CMAKE_BINARY_DIR}/${ELP_API_PLIST}" DESTINATION Resources COMPONENT elp_api)
    set(CPACK_POSTFLIGHT_ELP_API_SCRIPT  "${CMAKE_BINARY_DIR}/postinstall-elp-api.sh")
  endif()

  # Cleans up the installed package
  set(CPACK_PRE_BUILD_SCRIPTS "${CMAKE_SOURCE_DIR}/packaging/cleanup.cmake")

  # Signs the binaries using ad-hoc signing
  set(CPACK_POST_BUILD_SCRIPTS "${CMAKE_SOURCE_DIR}/packaging/macos/post_build.cmake")

  # CPack doesn't support a direct way to customise the Distribution.dist file, but the template
  # CPack.distribution.dist.in is searched for in the CMAKE_MODULE_PATH before CMAKE_ROOT, so as a hack,
  # point it to a local directory with our custom template
  set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/packaging/macos")

  install(FILES "${CMAKE_SOURCE_DIR}/packaging/macos/uninstall.sh"
          DESTINATION . COMPONENT elpd)
endif()

# must be last
include(CPack)
