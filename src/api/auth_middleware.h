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

#pragma once

#include "config.h"

#include <string>
#include <string_view>

namespace multipass::api
{

enum class AuthResult
{
    ok,
    missing,
    invalid
};

/** Paths that never require a Bearer token. */
bool is_public_path(std::string_view path);

/**
 * Validate an Authorization header value against the API config.
 * Expects "Bearer <token>" when auth is enabled.
 */
AuthResult check_bearer_auth(std::string_view authorization_header, const ApiConfig& config);

std::string auth_error_body(AuthResult result);

} // namespace multipass::api
