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

#include <multipass/cli/cli_style.h>

#include <multipass/format.h>

#include <QByteArray>

#include <algorithm>
#include <cctype>
#include <cstdlib>

namespace mp = multipass;
namespace style = multipass::cli_style;

namespace
{
bool g_json = false;
bool g_color = false;

const char* ansi(style::Tone tone)
{
    switch (tone)
    {
    case style::Tone::reset:
        return "\033[0m";
    case style::Tone::dim:
        return "\033[2m";
    case style::Tone::bold:
        return "\033[1m";
    case style::Tone::green:
        return "\033[32m";
    case style::Tone::yellow:
        return "\033[33m";
    case style::Tone::red:
        return "\033[31m";
    case style::Tone::cyan:
        return "\033[36m";
    case style::Tone::magenta:
        return "\033[35m";
    case style::Tone::blue:
        return "\033[34m";
    }
    return "";
}

std::string strip_ansi(const std::string& s)
{
    std::string out;
    out.reserve(s.size());
    for (size_t i = 0; i < s.size(); ++i)
    {
        if (s[i] == '\033' && i + 1 < s.size() && s[i + 1] == '[')
        {
            i += 2;
            while (i < s.size() && s[i] != 'm')
                ++i;
            continue;
        }
        out.push_back(s[i]);
    }
    return out;
}

int display_width(const std::string& s)
{
    return static_cast<int>(strip_ansi(s).size());
}

std::string pad_cell(const std::string& cell, int width, bool right)
{
    const auto w = display_width(cell);
    if (w >= width)
        return cell;
    const auto pad = std::string(static_cast<size_t>(width - w), ' ');
    return right ? pad + cell : cell + pad;
}
} // namespace

void style::configure(bool want_json, bool force_no_color, bool cout_is_tty)
{
    g_json = want_json;
    const auto no_color_env = qEnvironmentVariableIsSet("NO_COLOR");
    g_color = !want_json && !force_no_color && !no_color_env && cout_is_tty;
}

bool style::json_enabled()
{
    return g_json;
}

bool style::color_enabled()
{
    return g_color;
}

std::string style::paint(Tone tone, const std::string& text)
{
    if (!g_color || tone == Tone::reset)
        return text;
    return fmt::format("{}{}{}", ansi(tone), text, ansi(Tone::reset));
}

std::string style::paint_status(const std::string& status)
{
    auto lower = status;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    if (lower == "running" || lower == "loaded" || lower == "ready" || lower == "ok" ||
        lower == "perfect")
        return paint(Tone::green, status);
    if (lower == "starting" || lower == "restarting" || lower == "downloading" ||
        lower == "suspending" || lower == "delayed shutdown" || lower == "tight" ||
        lower == "warning")
        return paint(Tone::yellow, status);
    if (lower == "stopped" || lower == "deleted" || lower == "suspended" || lower == "unavailable" ||
        lower == "failed" || lower == "error" || lower == "too_tight" || lower == "too-tight")
        return paint(Tone::red, status);
    return paint(Tone::dim, status);
}

std::string style::paint_status_cell(const std::string& status, int width)
{
    const auto pad = std::max(0, width - static_cast<int>(status.size()));
    return paint_status(status) + std::string(static_cast<size_t>(pad), ' ');
}

void style::print_ok(std::ostream& out, const std::string& message)
{
    out << paint(Tone::green, "✓") << " " << message << "\n";
}

void style::print_warn(std::ostream& out, const std::string& message)
{
    out << paint(Tone::yellow, "!") << " " << message << "\n";
}

void style::print_err(std::ostream& out, const std::string& message)
{
    out << paint(Tone::red, "✗") << " " << message << "\n";
}

void style::print_info(std::ostream& out, const std::string& message)
{
    out << paint(Tone::cyan, "›") << " " << message << "\n";
}

void style::print_table(std::ostream& out, const Table& table)
{
    if (table.columns.empty())
        return;

    std::vector<int> widths(table.columns.size(), 0);
    for (size_t c = 0; c < table.columns.size(); ++c)
    {
        widths[c] = std::max(table.columns[c].width, display_width(table.columns[c].header));
        for (const auto& row : table.rows)
        {
            if (c < row.size())
                widths[c] = std::max(widths[c], display_width(row[c]));
        }
        widths[c] = std::max(widths[c], 1);
    }

    auto emit_row = [&](const std::vector<std::string>& cells, bool header) {
        for (size_t c = 0; c < table.columns.size(); ++c)
        {
            if (c)
                out << "  ";
            const auto& raw = c < cells.size() ? cells[c] : std::string{};
            const auto padded = pad_cell(raw, widths[c], table.columns[c].right);
            out << (header ? paint(Tone::bold, strip_ansi(padded)) : padded);
        }
        out << "\n";
    };

    std::vector<std::string> headers;
    headers.reserve(table.columns.size());
    for (const auto& col : table.columns)
        headers.push_back(col.header);
    emit_row(headers, true);

    for (size_t c = 0; c < table.columns.size(); ++c)
    {
        if (c)
            out << "  ";
        out << paint(Tone::dim, std::string(static_cast<size_t>(widths[c]), '-'));
    }
    out << "\n";

    if (table.rows.empty())
    {
        out << paint(Tone::dim, "(none)") << "\n";
        return;
    }

    for (const auto& row : table.rows)
        emit_row(row, false);
}

void style::print_json(std::ostream& out, const QJsonObject& obj)
{
    print_json_doc(out, QJsonDocument{obj});
}

void style::print_json(std::ostream& out, const QJsonArray& arr)
{
    print_json_doc(out, QJsonDocument{arr});
}

void style::print_json_doc(std::ostream& out, const QJsonDocument& doc)
{
    out << doc.toJson(QJsonDocument::Indented).toStdString();
}
