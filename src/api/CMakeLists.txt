# Copyright (C) Elemento.
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

find_package(httplib CONFIG REQUIRED)
find_package(Boost CONFIG REQUIRED COMPONENTS json)

add_library(hyperpass_api STATIC
  auth_middleware.cpp
  config.cpp
  grpc_backend.cpp
  multipass_discovery.cpp
  operation_tracker.cpp
  server.cpp
  handlers/handlers.cpp)

target_include_directories(hyperpass_api
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
  PRIVATE
    ${CMAKE_SOURCE_DIR}/include)

target_link_libraries(hyperpass_api
  PUBLIC
    client_common
    rpc
    httplib::httplib
    Boost::json
    fmt::fmt-header-only
    Qt6::Core
  PRIVATE
    logger
    utils)

if(MSVC)
  prepare_windows_version_resource(
    HYPERPASS_API_RC_SOURCE
    hyperpass-api
    "Hyperpass REST API"
    "hyperpass-api"
    "hyperpass-api.exe"
  )
  add_executable(hyperpass-api
    main.cpp
    ${HYPERPASS_API_RC_SOURCE})
  qt6_disable_unicode_defines(hyperpass-api)
else()
  add_executable(hyperpass-api
    main.cpp)
endif()

target_link_libraries(hyperpass-api
  hyperpass_api)

install(TARGETS hyperpass-api
  DESTINATION bin
  COMPONENT hyperpass_api)

install(DIRECTORY openapi/
  DESTINATION share/hyperpass/api/openapi
  COMPONENT hyperpass_api
  FILES_MATCHING PATTERN "*.yaml" PATTERN "*.md")

if(APPLE)
  set_target_properties(hyperpass-api PROPERTIES INSTALL_RPATH "@executable_path/../lib")

  install(CODE "
    include(${CMAKE_SOURCE_DIR}/packaging/FrameworkUtilities.cmake)
    install_frameworks(\"${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/hyperpass-api\" \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/lib\")
    " COMPONENT hyperpass_api)
endif()

if(MSVC)
  install(CODE "
    include(BundleUtilities)
    fixup_bundle(\"\${CMAKE_INSTALL_PREFIX}/bin/hyperpass-api.exe\"  \"\"  \"${CMAKE_RUNTIME_OUTPUT_DIRECTORY}\")
    " COMPONENT hyperpass_api)
endif()
