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

#pragma once

#include <atomic>
#include <memory>

#include <QHash>
#include <QReadWriteLock>

#include "infohash.h"

// Thread-safe registry mapping a torrent to its shared "block upload" flag.
// The flag is read on the libtorrent thread by the per-peer upload blocker and
// written on the main thread when the option is toggled or seeded before a torrent
// is added. Sharing the atomic through a shared_ptr keeps a toggle instantly visible
// to already-connected peers without any locking on the per-message hot path.
class UploadBlockFlagStore
{
public:
    using Flag = std::shared_ptr<std::atomic<bool>>;

    // Main thread: set the flag, creating it if needed (used to seed before add).
    void setBlocked(const BitTorrent::TorrentID &id, bool blocked);
    // libtorrent thread: fetch the flag, creating a default (unblocked) one on demand.
    Flag flagFor(const BitTorrent::TorrentID &id);
    // Main thread: re-key the flag when a torrent's ID changes (e.g. hybrid magnet gains metadata).
    void changeTorrentID(const BitTorrent::TorrentID &from, const BitTorrent::TorrentID &to);
    // Main thread: drop the flag when a torrent is removed.
    void remove(const BitTorrent::TorrentID &id);

private:
    QReadWriteLock m_lock;
    QHash<BitTorrent::TorrentID, Flag> m_flags;
};
