/*
 * Copyright (C) Elemento.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

/**
 * Lightweight HTTP-level smoke helpers for hyperpass-api.
 * These do not require a live daemon: they exercise auth middleware wiring via
 * the pure helpers covered in test_api.cpp. Live daemon smoke is documented in
 * src/api/README.md (run-dev-daemon.sh + run-dev-api.sh).
 *
 * CI coverage: multipass_cpp_tests includes Api* suites when HYPERPASS_ENABLE_API=ON.
 */
