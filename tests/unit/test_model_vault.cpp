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
#include "stub_url_downloader.h"
#include "temp_dir.h"

#include "model_vault.h"
#include "runners/model_format.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>

namespace mp = multipass;
namespace mpt = multipass::test;
namespace llm = multipass::llm;
using namespace testing;

namespace
{
struct TestModelVault : public Test
{
    mpt::TempDir data_dir;
    mpt::StubURLDownloader downloader;
    mp::ModelVault vault{data_dir.path(), downloader};
};
} // namespace

TEST_F(TestModelVault, registerRemoteKeepsMultipleFormatsPerModel)
{
    const auto hf = vault.register_remote("llama-3.1-8b", "meta-llama/Llama-3.1-8B", llm::format_hf);
    const auto mlx =
        vault.register_remote("llama-3.1-8b", "mlx-community/Llama-3.1-8B-4bit", llm::format_mlx);

    EXPECT_EQ(hf.format, llm::format_hf);
    EXPECT_EQ(mlx.format, llm::format_mlx);

    const auto by_hf = vault.find("llama-3.1-8b", llm::format_hf);
    const auto by_mlx = vault.find("llama-3.1-8b", llm::format_mlx);
    ASSERT_TRUE(by_hf);
    ASSERT_TRUE(by_mlx);
    EXPECT_EQ(by_hf->repo, "meta-llama/Llama-3.1-8B");
    EXPECT_EQ(by_mlx->repo, "mlx-community/Llama-3.1-8B-4bit");

    const auto listed = vault.list_for("llama-3.1-8b");
    EXPECT_EQ(listed.size(), 2u);
}

TEST_F(TestModelVault, formatForRunnerSelectsMatchingArtifact)
{
    vault.register_remote("qwen", "Qwen/Qwen2.5-7B", llm::format_hf);
    vault.register_remote("qwen", "mlx-community/Qwen2.5-7B-4bit", llm::format_mlx);

    const auto for_vllm = vault.find("qwen", llm::format_for_runner(llm::runner_vllm));
    const auto for_mlx = vault.find("qwen", llm::format_for_runner(llm::runner_mlx));
    const auto for_llama = vault.find("qwen", llm::format_for_runner(llm::runner_llamacpp));

    ASSERT_TRUE(for_vllm);
    ASSERT_TRUE(for_mlx);
    EXPECT_FALSE(for_llama);
    EXPECT_EQ(for_vllm->format, llm::format_hf);
    EXPECT_EQ(for_mlx->format, llm::format_mlx);
}

TEST_F(TestModelVault, registerRemoteRejectsGguf)
{
    EXPECT_THROW(vault.register_remote("x", "org/model", llm::format_gguf), std::runtime_error);
}

TEST_F(TestModelVault, removeByFormatLeavesSibling)
{
    vault.register_remote("m", "org/hf", llm::format_hf);
    vault.register_remote("m", "org/mlx", llm::format_mlx);

    EXPECT_TRUE(vault.remove("m", llm::format_hf));
    EXPECT_FALSE(vault.find("m", llm::format_hf));
    ASSERT_TRUE(vault.find("m", llm::format_mlx));
}

namespace
{
void write_minimal_gguf(const QString& path)
{
    QDir{}.mkpath(QFileInfo{path}.absolutePath());
    QFile file{path};
    ASSERT_TRUE(file.open(QIODevice::WriteOnly));
    file.write("GGUF");
    file.write(QByteArray(1024 * 1024, 'x'));
}
} // namespace

TEST_F(TestModelVault, pullKeepsMultipleGgufQuants)
{
    const auto q4 = QDir{vault.models_root()}.filePath("org_model/model-Q4_K_M.gguf");
    const auto q8 = QDir{vault.models_root()}.filePath("org_model/model-Q8_0.gguf");
    write_minimal_gguf(q4);
    write_minimal_gguf(q8);

    const auto nop = [](int, int) { return true; };
    vault.pull("m", "org/model", "model-Q4_K_M.gguf", "Q4_K_M", "", nop);
    vault.pull("m", "org/model", "model-Q8_0.gguf", "Q8_0", "", nop);

    const auto listed = vault.list_for("m");
    EXPECT_EQ(listed.size(), 2u);

    const auto by_q4 = vault.find("m", llm::format_gguf, "Q4_K_M");
    const auto by_q8 = vault.find("m", llm::format_gguf, "Q8_0");
    ASSERT_TRUE(by_q4);
    ASSERT_TRUE(by_q8);
    EXPECT_EQ(by_q4->filename, "model-Q4_K_M.gguf");
    EXPECT_EQ(by_q8->filename, "model-Q8_0.gguf");

    // Prefer Q4_K_M when quant is omitted.
    const auto preferred = vault.find("m", llm::format_gguf);
    ASSERT_TRUE(preferred);
    EXPECT_EQ(preferred->quant, "Q4_K_M");
}

TEST_F(TestModelVault, removeQuantLeavesSiblingQuant)
{
    const auto q4 = QDir{vault.models_root()}.filePath("org_model/model-Q4_K_M.gguf");
    const auto q5 = QDir{vault.models_root()}.filePath("org_model/model-Q5_K_M.gguf");
    write_minimal_gguf(q4);
    write_minimal_gguf(q5);

    const auto nop = [](int, int) { return true; };
    vault.pull("m", "org/model", "model-Q4_K_M.gguf", "Q4_K_M", "", nop);
    vault.pull("m", "org/model", "model-Q5_K_M.gguf", "Q5_K_M", "", nop);

    EXPECT_TRUE(vault.remove("m", llm::format_gguf, "Q4_K_M"));
    EXPECT_FALSE(vault.find("m", llm::format_gguf, "Q4_K_M"));
    ASSERT_TRUE(vault.find("m", llm::format_gguf, "Q5_K_M"));
}

namespace
{
struct SnapshotDownloader : public multipass::URLDownloader
{
    SnapshotDownloader() : multipass::URLDownloader{std::chrono::seconds(10)}
    {
    }

    void download_to(const QUrl&,
                     const QString& file_name,
                     int64_t,
                     const int,
                     const multipass::ProgressMonitor& monitor) override
    {
        QDir{}.mkpath(QFileInfo{file_name}.absolutePath());
        QFile file{file_name};
        ASSERT_TRUE(file.open(QIODevice::WriteOnly));
        file.write("x");
        file.close();
        if (monitor)
            monitor(0, 100);
    }

    QByteArray download(const QUrl& url) override
    {
        if (!url.path().contains(QStringLiteral("/tree/")))
            return {};
        return R"([
          {"type":"file","path":"config.json","size":3},
          {"type":"file","path":"model.safetensors","size":10},
          {"type":"directory","path":"unused","size":0}
        ])";
    }
};
} // namespace

TEST(TestModelVaultPullRemote, downloadsFullSnapshotIntoVault)
{
    mpt::TempDir data_dir;
    SnapshotDownloader downloader;
    mp::ModelVault vault{data_dir.path(), downloader};

    int last_progress = -1;
    const auto art = vault.pull_remote(
        "gemma",
        "mlx-community/Gemma-2-2B-4bit",
        llm::format_mlx,
        "mlx-4bit",
        "",
        [&](int, int percent) {
            last_progress = percent;
            return true;
        });

    EXPECT_EQ(art.format, llm::format_mlx);
    EXPECT_EQ(art.repo, "mlx-community/Gemma-2-2B-4bit");
    EXPECT_EQ(art.quant, "mlx-4bit");
    EXPECT_TRUE(QFileInfo{QString::fromStdString(art.path)}.isDir());
    EXPECT_TRUE(QFileInfo{QDir{QString::fromStdString(art.path)}.filePath("config.json")}.exists());
    EXPECT_TRUE(
        QFileInfo{QDir{QString::fromStdString(art.path)}.filePath("model.safetensors")}.exists());
    EXPECT_EQ(last_progress, 100);

    // Second pull is a no-op once the local snapshot exists.
    const auto again = vault.pull_remote(
        "gemma", "mlx-community/Gemma-2-2B-4bit", llm::format_mlx, "mlx-4bit", "", [](int, int) {
            return true;
        });
    EXPECT_EQ(again.path, art.path);
}
