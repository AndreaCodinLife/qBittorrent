/*
 * Bittorrent Client using Qt and libtorrent.
 * Copyright (C) 2024  Vladimir Golovnev <glassez@yandex.ru>
 * Copyright (C) 2024  Radu Carpa <radu.carpa@cern.ch>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 * In addition, as a special exception, the copyright holders give permission to
 * link this program with the OpenSSL project's "OpenSSL" library (or with
 * modified versions of it that use the same license as the "OpenSSL" library),
 * and distribute the linked executables. You must obey the GNU General Public
 * License in all respects for all of the code used other than "OpenSSL".  If you
 * modify file(s), you may extend this exception to your version of the file(s),
 * but you are not obligated to do so. If you do not wish to do so, delete this
 * exception statement from your version.
 */

#include "torrentcreationmanager.h"

#include <algorithm>
#include <exception>
#include <utility>

#include <boost/multi_index_container.hpp>
#include <boost/multi_index/indexed_by.hpp>
#include <boost/multi_index/key.hpp>
#include <boost/multi_index/ordered_index.hpp>

#include <QUuid>
#include <QMetaObject>
#include <QPointer>
#include <QRunnable>

#define SETTINGS_KEY(name) u"TorrentCreator/Manager/" name

namespace BitTorrent
{
    using namespace boost::multi_index;

    class TorrentCreationManager::TaskSet final : public multi_index_container<
        std::shared_ptr<TorrentCreationTask>,
        indexed_by<
            ordered_unique<tag<struct ByID>, key<&TorrentCreationTask::id>>,
            ordered_non_unique<tag<struct ByCompletion>,
                key<&TorrentCreationTask::isFinished, &TorrentCreationTask::timeAdded>>>>
    {
    };
}

BitTorrent::TorrentCreationManager::TorrentCreationManager(IApplication *app, QObject *parent)
    : ApplicationComponent(app, parent)
    , m_maxTasks {SETTINGS_KEY(u"MaxTasks"_s), 256}
    , m_numThreads {SETTINGS_KEY(u"NumThreads"_s), 1}
    , m_tasks {std::make_unique<TaskSet>()}
    , m_threadPool(this)
{
    m_threadPool.setObjectName("TorrentCreationManager m_threadPool");
    m_pieceCountThreadPool.setObjectName("TorrentCreationManager m_pieceCountThreadPool");
    m_pieceCountThreadPool.setMaxThreadCount(2);

    if (m_numThreads > 0)
        m_threadPool.setMaxThreadCount(m_numThreads);
}

BitTorrent::TorrentCreationManager::~TorrentCreationManager() = default;

std::shared_ptr<BitTorrent::TorrentCreationTask> BitTorrent::TorrentCreationManager::createTask(const TorrentCreatorParams &params, const bool startSeeding, const bool ignoreShareLimits)
{
    if (std::cmp_greater_equal(m_tasks->size(), m_maxTasks.get()))
    {
        // Try to delete old finished tasks to stay under target
        auto &tasksByCompletion = m_tasks->get<ByCompletion>();
        auto [iter, endIter] = tasksByCompletion.equal_range(std::make_tuple(true));
        while ((iter != endIter) && std::cmp_greater_equal(m_tasks->size(), m_maxTasks.get()))
        {
            iter = tasksByCompletion.erase(iter);
        }
    }
    if (std::cmp_greater_equal(m_tasks->size(), m_maxTasks.get()))
        return {};

    const QString taskID = generateTaskID();

    auto *torrentCreator = new TorrentCreator(params, this);
    auto creationTask = std::make_shared<TorrentCreationTask>(app(), taskID, torrentCreator, startSeeding, ignoreShareLimits);
    connect(creationTask.get(), &QObject::destroyed, torrentCreator, &BitTorrent::TorrentCreator::requestInterruption);

    m_tasks->get<ByID>().insert(creationTask);
    m_threadPool.start(torrentCreator);

    return creationTask;
}

QString BitTorrent::TorrentCreationManager::generateTaskID() const
{
    const auto &tasksByID = m_tasks->get<ByID>();
    QString taskID = QUuid::createUuid().toString(QUuid::WithoutBraces);
    while (tasksByID.find(taskID) != tasksByID.end())
        taskID = QUuid::createUuid().toString(QUuid::WithoutBraces);

    return taskID;
}

std::shared_ptr<BitTorrent::TorrentCreationTask> BitTorrent::TorrentCreationManager::getTask(const QString &id) const
{
    const auto &tasksByID = m_tasks->get<ByID>();
    const auto iter = tasksByID.find(id);
    if (iter == tasksByID.end())
        return nullptr;

    return *iter;
}

QList<std::shared_ptr<BitTorrent::TorrentCreationTask>> BitTorrent::TorrentCreationManager::tasks() const
{
    const auto &tasksByCompletion = m_tasks->get<ByCompletion>();
    return {tasksByCompletion.cbegin(), tasksByCompletion.cend()};
}

bool BitTorrent::TorrentCreationManager::deleteTask(const QString &id)
{
    auto &tasksByID = m_tasks->get<ByID>();
    const auto iter = tasksByID.find(id);
    if (iter == tasksByID.end())
        return false;

    tasksByID.erase(iter);
    return true;
}

QString BitTorrent::TorrentCreationManager::calculatePieces(const TorrentCreatorParams &params)
{
    int runningTasks = 0;
    for (const TorrentPieceCountStatus &status : m_pieceCountTasks)
    {
        if (status.state == TorrentPieceCountStatus::State::Running)
            ++runningTasks;
    }
    if (runningTasks >= 4)
        return {};

    constexpr qsizetype MAX_RETAINED_TASKS = 128;
    while (std::cmp_greater_equal(m_pieceCountTasks.size(), MAX_RETAINED_TASKS))
    {
        const auto finishedTask = std::find_if(m_pieceCountTasks.begin(), m_pieceCountTasks.end(), [](const auto &entry)
        {
            return (entry.state != TorrentPieceCountStatus::State::Running);
        });
        if (finishedTask == m_pieceCountTasks.end())
            return {};
        m_pieceCountTasks.erase(finishedTask);
    }

    const QString id = u"pieces-"_s + QUuid::createUuid().toString(QUuid::WithoutBraces);
    m_pieceCountTasks.insert(id, {});

    const QPointer<TorrentCreationManager> manager {this};
    m_pieceCountThreadPool.start(QRunnable::create([manager, id, params]
    {
        TorrentPieceCountStatus status;
        try
        {
#ifdef QBT_USES_LIBTORRENT2
            status.pieces = TorrentCreator::calculateTotalPieces(params.sourcePath, params.pieceSize, params.ignoreDotfiles, params.torrentFormat);
#else
            status.pieces = TorrentCreator::calculateTotalPieces(params.sourcePath, params.pieceSize, params.ignoreDotfiles, params.isAlignmentOptimized, params.paddedFileSizeLimit);
#endif
            status.state = TorrentPieceCountStatus::State::Finished;
        }
        catch (const std::exception &error)
        {
            status.state = TorrentPieceCountStatus::State::Failed;
            status.errorMessage = QString::fromUtf8(error.what());
        }
        catch (...)
        {
            status.state = TorrentPieceCountStatus::State::Failed;
            status.errorMessage = QObject::tr("Could not calculate the number of pieces.");
        }

        if (!manager)
            return;
        QMetaObject::invokeMethod(manager.data(), [manager, id, status]
        {
            if (manager)
                manager->finishPieceCount(id, status);
        }, Qt::QueuedConnection);
    }));

    return id;
}

std::optional<BitTorrent::TorrentPieceCountStatus> BitTorrent::TorrentCreationManager::pieceCountStatus(const QString &id) const
{
    const auto iter = m_pieceCountTasks.constFind(id);
    if (iter == m_pieceCountTasks.cend())
        return std::nullopt;
    return iter.value();
}

void BitTorrent::TorrentCreationManager::finishPieceCount(const QString &id, const TorrentPieceCountStatus &status)
{
    const auto iter = m_pieceCountTasks.find(id);
    if (iter != m_pieceCountTasks.end())
        iter.value() = status;
}
