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

#include <multipass/process/process_scan.h>

#include <QElapsedTimer>
#include <QProcess>
#include <QRegularExpression>
#include <QThread>

#ifndef MULTIPASS_PLATFORM_WINDOWS
#include <signal.h>
#include <unistd.h>
#else
#include <windows.h>
#endif

namespace mp = multipass;
namespace mpu = multipass::utils;

std::vector<mpu::ProcessMatch> mpu::parse_ps_table(const QByteArray& output)
{
    std::vector<ProcessMatch> matches;
    const auto lines = QString::fromUtf8(output).split('\n', Qt::SkipEmptyParts);
    const QRegularExpression line_re{QStringLiteral(R"(^\s*(\d+)\s+(.*)$)")};
    for (const auto& line : lines)
    {
        const auto m = line_re.match(line);
        if (!m.hasMatch())
            continue;
        ProcessMatch match;
        match.pid = m.captured(1).toLongLong();
        match.command_line = m.captured(2).trimmed();
        if (match.pid > 0 && !match.command_line.isEmpty())
            matches.push_back(std::move(match));
    }
    return matches;
}

std::vector<mpu::ProcessMatch> mpu::list_processes()
{
#ifdef MULTIPASS_PLATFORM_WINDOWS
    return {};
#else
    QProcess ps;
    ps.setProcessChannelMode(QProcess::MergedChannels);
    ps.start("ps", {"-ax", "-o", "pid=", "-o", "args="});
    if (!ps.waitForFinished(3000))
    {
        ps.kill();
        return {};
    }
    return parse_ps_table(ps.readAllStandardOutput());
#endif
}

std::optional<qint64> mpu::find_pid_containing(const QString& program_needle,
                                               const QString& arg_needle)
{
    if (arg_needle.isEmpty())
        return std::nullopt;

    for (const auto& proc : list_processes())
    {
        if (!program_needle.isEmpty() && !proc.command_line.contains(program_needle))
            continue;
        if (proc.command_line.contains(arg_needle))
            return proc.pid;
    }
    return std::nullopt;
}

QString mpu::cli_flag_value(const QString& command_line, const QStringList& flags)
{
    const auto parts = command_line.split(QRegularExpression(R"(\s+)"), Qt::SkipEmptyParts);
    for (int i = 0; i + 1 < parts.size(); ++i)
    {
        if (flags.contains(parts[i]))
            return parts[i + 1];
    }
    return {};
}

bool mpu::pid_is_alive(qint64 pid)
{
    if (pid <= 0)
        return false;
#ifndef MULTIPASS_PLATFORM_WINDOWS
    return ::kill(static_cast<pid_t>(pid), 0) == 0;
#else
    HANDLE handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, static_cast<DWORD>(pid));
    if (!handle)
        return false;
    DWORD exit_code = 0;
    const bool alive = GetExitCodeProcess(handle, &exit_code) && exit_code == STILL_ACTIVE;
    CloseHandle(handle);
    return alive;
#endif
}

void mpu::terminate_pid(qint64 pid)
{
    if (pid <= 0)
        return;
#ifndef MULTIPASS_PLATFORM_WINDOWS
    ::kill(static_cast<pid_t>(pid), SIGTERM);
    QElapsedTimer timer;
    timer.start();
    while (pid_is_alive(pid) && timer.elapsed() < 3000)
        QThread::msleep(50);
    if (pid_is_alive(pid))
        ::kill(static_cast<pid_t>(pid), SIGKILL);
#else
    HANDLE handle = OpenProcess(PROCESS_TERMINATE, FALSE, static_cast<DWORD>(pid));
    if (!handle)
        return;
    TerminateProcess(handle, 1);
    CloseHandle(handle);
#endif
}
