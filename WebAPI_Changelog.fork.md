# WebAPI Changelog (fork)

Fork-only WebAPI changes on top of upstream qBittorrent. Upstream's `WebAPI_Changelog.md` and the runtime `API_VERSION` stay untouched by fork patches; fork changes are numbered independently here as `fork-N`.

## fork-1
* Added per-torrent upload blocking control
  * `torrents/setUploadBlocked` endpoint sets whether upload is blocked for the given torrents (params: `hashes`, `value`)
  * `torrents/info` and `sync/maindata` now include a bool field `upload_blocked` reporting the per-torrent upload-blocked state
  * `torrents/add` endpoint accepts a new optional bool parameter `uploadBlocked` that sets the per-torrent upload block for the added torrents; when the parameter is omitted, upload is blocked
