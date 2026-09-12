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
find_package(OpenSSL REQUIRED)

add_library(elp_api STATIC
  auth_middleware.cpp
  config.cpp
  grpc_backend.cpp
  https_certs.cpp
  multipass_discovery.cpp
  operation_tracker.cpp
  server.cpp
  tls_fingerprint.cpp
  vm_registry.cpp
  handlers/handlers.cpp
  handlers/openai.cpp
  handlers/service.cpp
  marketplace_cloud_init.cpp
  spot_spec.cpp)

target_include_directories(elp_api
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
  PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${MULTIPASS_GENERATED_SOURCE_DIR})

target_compile_definitions(elp_api
  PUBLIC
    CPPHTTPLIB_OPENSSL_SUPPORT
    CPPHTTPLIB_DISABLE_MACOSX_AUTOMATIC_ROOT_CERTIFICATES)

# Newer GCC (e.g. GCC 16) mis-analyzes object layout while inlining
# httplib::SSLClient's destructor across the vendored cpp-httplib header,
# producing a false-positive -Warray-bounds. Scoped to this target only,
# since -Warray-bounds is still worth keeping as an error elsewhere.
target_compile_options(elp_api PRIVATE
  "$<$<CXX_COMPILER_ID:GNU>:-Wno-error=array-bounds>")

target_link_libraries(elp_api
  PUBLIC
    client_common
    rpc
    httplib::httplib
    Boost::json
    fmt::fmt-header-only
    Qt6::Core
    OpenSSL::SSL
    OpenSSL::Crypto
    cert
  PRIVATE
    logger
    utils
    yaml-cpp::yaml-cpp)

if(MSVC)
  prepare_windows_version_resource(
    ELP_API_RC_SOURCE
    elp-api
    "Electros LaunchPad REST API"
    "elp-api"
    "elp-api.exe"
  )
  prepare_windows_version_resource(
    ELP_LLM_PROXY_RC_SOURCE
    elp-llm-proxy
    "Electros LaunchPad LLM proxy"
    "elp-llm-proxy"
    "elp-llm-proxy.exe"
  )
  add_executable(elp-api
    main.cpp
    ${ELP_API_RC_SOURCE})
  add_executable(elp-llm-proxy
    llm_proxy_main.cpp
    ${ELP_LLM_PROXY_RC_SOURCE})
  qt6_disable_unicode_defines(elp-api)
  qt6_disable_unicode_defines(elp-llm-proxy)
else()
  add_executable(elp-api
    main.cpp)
  add_executable(elp-llm-proxy
    llm_proxy_main.cpp)
endif()

target_link_libraries(elp-api
  elp_api)
target_link_libraries(elp-llm-proxy
  elp_api)

install(TARGETS elp-api elp-llm-proxy
  DESTINATION bin
  COMPONENT elp_api)

install(DIRECTORY openapi/
  DESTINATION share/elp/api/openapi
  COMPONENT elp_api
  FILES_MATCHING PATTERN "*.yaml" PATTERN "*.md")

if(APPLE)
  set_target_properties(elp-api elp-llm-proxy PROPERTIES INSTALL_RPATH "@executable_path/../lib")

  install(CODE "
    include(${CMAKE_SOURCE_DIR}/packaging/FrameworkUtilities.cmake)
    install_frameworks(\"${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/elp-api\" \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/lib\")
    install_frameworks(\"${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/elp-llm-proxy\" \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/lib\")
    " COMPONENT elp_api)
endif()

if(MSVC)
  install(CODE "
    include(BundleUtilities)
    fixup_bundle(\"\${CMAKE_INSTALL_PREFIX}/bin/elp-api.exe\"  \"\"  \"${CMAKE_RUNTIME_OUTPUT_DIRECTORY}\")
    fixup_bundle(\"\${CMAKE_INSTALL_PREFIX}/bin/elp-llm-proxy.exe\"  \"\"  \"${CMAKE_RUNTIME_OUTPUT_DIRECTORY}\")
    " COMPONENT elp_api)
endif()
