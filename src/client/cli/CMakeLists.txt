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

add_library(client STATIC
  argparser.cpp
  client.cpp)

target_link_libraries(client
  client_platform
  commands
  fmt::fmt-header-only
  formatter
  rpc
  scope_guard
  shared
  Qt6::Core)

if(MSVC)
  prepare_windows_version_resource(
    ELP_RC_SOURCE
    elp
    "Electros LaunchPad CLI"
    "elp"
    "elp.exe"
  )
  add_executable(elp
    main.cpp
    ${ELP_RC_SOURCE})
else()
  add_executable(elp
    main.cpp)
endif()


target_link_libraries(elp
  client)

install(TARGETS elp
  DESTINATION bin
  COMPONENT elp)

if(APPLE)
  set_target_properties( elp PROPERTIES INSTALL_RPATH "@executable_path/../lib" )

  # Copy any framework depenencies into the install directory for packaging
  install(CODE "
    include(${CMAKE_SOURCE_DIR}/packaging/FrameworkUtilities.cmake)
    install_frameworks(\"${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/elp\" \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/lib\")
    " COMPONENT elp)
endif(APPLE)

if(MSVC)
  install(CODE "
    include(BundleUtilities)
    fixup_bundle(\"\${CMAKE_INSTALL_PREFIX}/bin/elp.exe\"  \"\"  \"${CMAKE_RUNTIME_OUTPUT_DIRECTORY}\")
    " COMPONENT elp)
endif()

add_subdirectory(cmd)
add_subdirectory(formatter)
