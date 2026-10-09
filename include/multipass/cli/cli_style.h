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

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>

#include <ostream>
#include <string>
#include <vector>

namespace multipass::cli_style
{

enum class Tone
{
    reset,
    dim,
    bold,
    green,
    yellow,
    red,
    cyan,
    magenta,
    blue
};

/// Call once after parsing global flags (from ArgParser).
void configure(bool want_json, bool force_no_color, bool cout_is_tty);

bool json_enabled();
bool color_enabled();

std::string paint(Tone tone, const std::string& text);
std::string paint_status(const std::string& status);
/// Color the status then right-pad to `width` using the uncolored length.
std::string paint_status_cell(const std::string& status, int width);

void print_ok(std::ostream& out, const std::string& message);
void print_warn(std::ostream& out, const std::string& message);
void print_err(std::ostream& out, const std::string& message);
void print_info(std::ostream& out, const std::string& message);

struct Column
{
    std::string header;
    int width{0}; // 0 = auto from content
    bool right{false};
};

struct Table
{
    std::vector<Column> columns;
    std::vector<std::vector<std::string>> rows;
};

void print_table(std::ostream& out, const Table& table);
void print_json(std::ostream& out, const QJsonObject& obj);
void print_json(std::ostream& out, const QJsonArray& arr);
void print_json_doc(std::ostream& out, const QJsonDocument& doc);

} // namespace multipass::cli_style
