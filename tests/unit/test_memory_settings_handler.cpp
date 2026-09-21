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

#include "common.h"

#include <multipass/constants.h>
#include <multipass/exceptions/settings_exceptions.h>
#include <multipass/settings/basic_setting_spec.h>
#include <multipass/settings/memory_settings_handler.h>
#include <multipass/user_messages.h>

namespace mp = multipass;
namespace mpt = multipass::test;
using namespace testing;

namespace
{
mp::SettingSpec::Set token_settings()
{
    mp::SettingSpec::Set settings;
    settings.insert(std::make_unique<mp::BasicSettingSpec>(mp::spacedock_token_key, ""));
    return settings;
}
} // namespace

TEST(MemorySettingsHandler, getReturnsDefaultThenStoredValue)
{
    mp::MemorySettingsHandler handler{token_settings()};
    EXPECT_EQ(handler.get(mp::spacedock_token_key), "");

    [[maybe_unused]] mp::UserMessages messages{};
    handler.set(mp::spacedock_token_key, "portal-jwt", messages);
    EXPECT_EQ(handler.get(mp::spacedock_token_key), "portal-jwt");
}

TEST(MemorySettingsHandler, rejectsUnknownKeys)
{
    mp::MemorySettingsHandler handler{token_settings()};
    MP_ASSERT_THROW_THAT(handler.get("local.unknown"),
                         mp::UnrecognizedSettingException,
                         mpt::match_what(HasSubstr("local.unknown")));
}
