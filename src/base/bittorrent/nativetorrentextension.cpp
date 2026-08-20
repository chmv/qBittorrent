/*
 * Bittorrent Client using Qt and libtorrent.
 * Copyright (C) 2020-2023  Vladimir Golovnev <glassez@yandex.ru>
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

#include "nativetorrentextension.h"

#include <libtorrent/peer_connection_handle.hpp>
#include <libtorrent/torrent_status.hpp>

#include "infohash.h"
#include "uploadblockflagstore.h"

namespace
{
    // Per-peer plugin that makes a torrent behave as if it has no free upload slots:
    // swallowing INTERESTED keeps the peer out of the (optimistic) unchoke candidates,
    // swallowing REQUEST rejects allowed-fast pieces and any request from a peer that
    // was already unchoked before the flag was set. Reads a shared flag with no locking.
    class PeerUploadBlocker final : public lt::peer_plugin
    {
    public:
        explicit PeerUploadBlocker(std::shared_ptr<std::atomic<bool>> flag)
            : m_flag {std::move(flag)}
        {
        }

    private:
        bool on_interested() override
        {
            return m_flag->load(std::memory_order_relaxed);
        }

        bool on_request(const lt::peer_request &) override
        {
            return m_flag->load(std::memory_order_relaxed);
        }

        std::shared_ptr<std::atomic<bool>> m_flag;
    };
}

NativeTorrentExtension::NativeTorrentExtension(const lt::torrent_handle &torrentHandle, ExtensionData *data
    , const std::shared_ptr<UploadBlockFlagStore> &uploadBlockFlags)
    : m_torrentHandle {torrentHandle}
    , m_data {data}
{
    // NOTE: `data` may not exist if a torrent is added behind the scenes to download metadata

    if (m_data)
    {
        m_data->status = m_torrentHandle.status();
        m_data->trackers = m_torrentHandle.trackers();
        m_data->urlSeeds = m_torrentHandle.url_seeds();

#ifdef QBT_USES_LIBTORRENT2
        const BitTorrent::InfoHash infoHash {m_torrentHandle.info_hashes()};
#else
        const BitTorrent::InfoHash infoHash {m_torrentHandle.info_hash()};
#endif
        m_uploadBlockedFlag = uploadBlockFlags->flagFor(BitTorrent::TorrentID::fromInfoHash(infoHash));
    }

    on_state(m_data ? m_data->status.state : m_torrentHandle.status({}).state);
}

NativeTorrentExtension::~NativeTorrentExtension()
{
    delete m_data;
}

void NativeTorrentExtension::on_state(const lt::torrent_status::state_t state)
{
    if ((m_state == lt::torrent_status::downloading_metadata)
            || (m_state == lt::torrent_status::checking_files))
    {
        m_torrentHandle.unset_flags(lt::torrent_flags::auto_managed);
        m_torrentHandle.pause();
    }

    m_state = state;
}

std::shared_ptr<lt::peer_plugin> NativeTorrentExtension::new_connection(const lt::peer_connection_handle &)
{
    if (!m_uploadBlockedFlag)
        return {};

    return std::make_shared<PeerUploadBlocker>(m_uploadBlockedFlag);
}
