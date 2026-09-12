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

#include "intent_service_templates.h"

namespace mp = multipass;

namespace
{
constexpr auto redis_cloud_init = R"YAML(packages:
- redis-server

runcmd:
- |
  sed -i 's/^bind 127.0.0.1.*/bind 0.0.0.0/' /etc/redis/redis.conf
  systemctl enable redis-server --now

final_message: "redis is up, after $UPTIME seconds"
)YAML";

constexpr auto postgres_cloud_init = R"YAML(packages:
- postgresql

runcmd:
- |
  echo "listen_addresses = '*'" >> /etc/postgresql/*/main/postgresql.conf
  echo "host all all 0.0.0.0/0 md5" >> /etc/postgresql/*/main/pg_hba.conf
  systemctl enable postgresql --now
  systemctl restart postgresql

final_message: "postgres is up, after $UPTIME seconds"
)YAML";
} // namespace

std::optional<mp::IntentServiceTemplate> mp::find_intent_service_template(const std::string& role)
{
    if (role == "redis")
        return IntentServiceTemplate{{}, redis_cloud_init};
    if (role == "postgres")
        return IntentServiceTemplate{{}, postgres_cloud_init};
    return std::nullopt;
}
