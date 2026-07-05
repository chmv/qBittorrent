/*
 * Bittorrent Client using Qt and libtorrent.
 * Copyright (C) 2026  Michael Chernyshev <chmv-git@allnetic.com>
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

#include "uploadblockflagstore.h"

void UploadBlockFlagStore::setBlocked(const BitTorrent::TorrentID &id, const bool blocked)
{
    flagFor(id)->store(blocked, std::memory_order_relaxed);
}

UploadBlockFlagStore::Flag UploadBlockFlagStore::flagFor(const BitTorrent::TorrentID &id)
{
    const QWriteLocker locker {&m_lock};
    Flag &flag = m_flags[id];
    if (!flag)
        flag = std::make_shared<std::atomic<bool>>(false);
    return flag;
}

void UploadBlockFlagStore::changeTorrentID(const BitTorrent::TorrentID &from, const BitTorrent::TorrentID &to)
{
    const QWriteLocker locker {&m_lock};
    if (Flag flag = m_flags.take(from))
        m_flags.insert(to, std::move(flag));
}

void UploadBlockFlagStore::remove(const BitTorrent::TorrentID &id)
{
    const QWriteLocker locker {&m_lock};
    m_flags.remove(id);
}
