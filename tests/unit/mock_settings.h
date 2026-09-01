/*
 * Copyright (C) Canonical, Ltd.
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

#include "common.h"
#include "mock_singleton_helpers.h"

#include <multipass/constants.h>
#include <multipass/settings/settings.h>

namespace multipass::test
{
class MockSettings : public Settings
{
public:
    using Settings::Settings;

    MOCK_METHOD(SettingsHandler*, register_handler, (std::unique_ptr<SettingsHandler>), (override));
    MOCK_METHOD(void, unregister_handler, (SettingsHandler * handler), (override));
    MOCK_METHOD(QString, get, (const QString&), (const, override));
    MOCK_METHOD(void, set, (const QString&, const QString&, UserMessages&), (override));
    MOCK_METHOD(std::set<QString>, keys, (), (const, override));

    MP_MOCK_SINGLETON_BOILERPLATE(MockSettings, Settings);
};

inline void expect_default_host_resource_settings(MockSettings& mock_settings)
{
    using namespace testing;
    EXPECT_CALL(mock_settings, get(Eq(QString{multipass::host_memory_reserve_key})))
        .Times(AnyNumber())
        .WillRepeatedly(Return(QString{multipass::default_host_memory_reserve}));
    EXPECT_CALL(mock_settings, get(Eq(QString{multipass::host_memory_policy_key})))
        .Times(AnyNumber())
        .WillRepeatedly(Return(QString{multipass::default_host_memory_policy}));
    EXPECT_CALL(mock_settings, get(Eq(QString{multipass::llm_backend_key})))
        .Times(AnyNumber())
        .WillRepeatedly(Return(QString{"auto"}));
    EXPECT_CALL(mock_settings, get(Eq(QString{multipass::llm_hf_token_key})))
        .Times(AnyNumber())
        .WillRepeatedly(Return(QString{}));
    EXPECT_CALL(mock_settings, get(Eq(QString{multipass::llm_idle_unload_key})))
        .Times(AnyNumber())
        .WillRepeatedly(Return(QString{multipass::default_llm_idle_unload}));
}
} // namespace multipass::test
