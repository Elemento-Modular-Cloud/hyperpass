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

set(CMAKE_AUTOMOC ON)

add_library(llm STATIC
  api_key_store.cpp
  backend_probe.cpp
  binary_locator.cpp
  llama_server_process_spec.cpp
  llm_activity_log.cpp
  llm_service.cpp
  llmfit_advisor.cpp
  mlx_server_process_spec.cpp
  model_vault.cpp)

target_include_directories(llm
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
    ${MULTIPASS_GENERATED_SOURCE_DIR}
  PRIVATE
    ${CMAKE_SOURCE_DIR}/src)

target_link_libraries(llm
  PUBLIC
    rpc
    Qt6::Core
    Qt6::Network
  PRIVATE
    fmt::fmt-header-only
    logger
    platform
    process
    settings
    utils)
