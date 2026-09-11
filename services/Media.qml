pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Singleton {
    id: root

    readonly property int maxIdentityChars: 512
    readonly property int maxMetadataChars: 2048
    readonly property int maxArtSourceChars: 4096

    function finiteNonnegative(value): real {
        const number = Number(value)
        return isFinite(number) && number > 0 ? number : 0
    }

    // any process on the bus can set artUrl, and Qt loads a remote one on the pixmap
    // thread, where a QNetworkAccessManager first use has crashed the shell in OpenSSL
    function artSource(raw): string {
        const value = String(raw ?? "").trim()
        if (value.length === 0 || value.length > root.maxArtSourceChars) return ""
        if (/[\u0000-\u001F\u007F]/.test(value)) return ""
        if (/^https:\/\//i.test(value))
            return ShellSettings.mediaRemoteArt ? value : ""
        if (/^http:\/\//i.test(value)) return ""
        return IconResolver.safeLocalSource(value)
    }

    // ephemeral by design: players come and go, so a pinned choice is dropped the moment its player leaves the bus
    property string preferredPlayer: ""

    readonly property var playerList: {
        const out = []
        const players = Mpris.players.values ?? []
        for (let i = 0; i < players.length; i++)
            if (players[i]) out.push(players[i])
        // playerctld only mirrors the real players; keep it solely when nothing else is on the bus
        const real = out.filter(p => (p.dbusName || "").indexOf("playerctld") < 0)
        const pool = real.length > 0 ? real : out
        // browsers leave the MPRIS service registered after the tab goes, stopped and with no
        // metadata: counting those offers a switcher that cycles onto an empty card. Stopped
        // only - a paused player is one the user may well want to come back to
        const live = pool.filter(p => p.playbackState !== MprisPlaybackState.Stopped)
        return live.length > 0 ? live : pool
    }
    readonly property int playerCount: playerList.length

    onPlayerListChanged: {
        if (root.preferredPlayer.length === 0) return
        for (let i = 0; i < root.playerList.length; i++)
            if (root.playerList[i].dbusName === root.preferredPlayer) return
        root.preferredPlayer = ""
    }

    // step: +1/-1 (or any integer) steps forward/back through playerList and wraps;
    // the view passes the direction rather than duplicating this index math itself
    function cyclePlayer(step: int): void {
        const players = root.playerList
        const n = players.length
        if (n < 2) return
        let idx = -1
        for (let i = 0; i < n; i++)
            if (players[i] === root.player) { idx = i; break }
        const next = ((idx + step) % n + n) % n
        root.preferredPlayer = players[next].dbusName
    }

    readonly property var player: {
        const players = root.playerList
        let fallback = null

        if (root.preferredPlayer.length > 0) {
            for (let i = 0; i < players.length; i++)
                if (players[i].dbusName === root.preferredPlayer) return players[i]
        }

        for (let i = 0; i < players.length; i++) {
            const p = players[i]
            if (!p) continue
            if (p.isPlaying) return p
            if (p.playbackState !== MprisPlaybackState.Stopped) {
                if (!fallback || fallback.playbackState === MprisPlaybackState.Stopped) fallback = p
            } else if (!fallback) {
                fallback = p
            }
        }

        return fallback
    }

    readonly property bool available: player !== null
        && (player.playbackState !== MprisPlaybackState.Stopped || title.length > 0)
    readonly property bool playing: player ? player.isPlaying : false

    readonly property bool canTogglePlaying: player ? player.canTogglePlaying : false
    readonly property bool canGoNext:        player ? player.canGoNext : false
    readonly property bool canGoPrevious:    player ? player.canGoPrevious : false

    // a freshly paused player still gets a grace period before it fades, since
    // pausing is usually a state to come back to -- but the surface now lets go
    // after ~30s (10s grace + 20s fade-out) rather than lingering, so the bar
    // declutters itself sooner once a source is paused for good. A player that's
    // already paused the first time we see it (shell just started, or one
    // reconnects mid-pause) shows immediately and fades on that same clock.
    property bool shown: false

    function _syncShown(): void {
        if (!available)  { _pauseTimer.stop(); _hideTimer.stop(); if (shown) shown = false; return }
        if (playing)     { _pauseTimer.stop(); _hideTimer.stop(); if (!shown) shown = true; return }
        // paused, and this is the first we've seen of it (shell just started with a
        // player already paused, or one reconnects mid-pause) -- show it now rather than
        // waiting on a play event that already happened, and start the same grace
        // timer so it fades on the same clock as an already-shown card that just paused
        if (!shown) { shown = true; _pauseTimer.start(); return }
        if (!_pauseTimer.running && !_hideTimer.running) _pauseTimer.start()
    }

    onAvailableChanged: { _syncShown(); _syncStableArt() }
    onPlayingChanged:   { _syncShown(); _reanchor() }
    Component.onCompleted: { _syncShown(); _reanchor(); if (artUrl.length > 0) stableArtUrl = artUrl }

    Timer { id: _pauseTimer; interval: 10000; onTriggered: _hideTimer.start() }
    Timer { id: _hideTimer;  interval: 20000; onTriggered: root.shown = false  }

    // MPRIS reports 2^63-1 microseconds for anything with no end, which every live
    // stream is; a real track is never a day long, so past the cap it means unknown
    readonly property real _rawLength:  (player && player.lengthSupported)
        ? root.finiteNonnegative(player.length) : 0
    readonly property bool lengthKnown: _rawLength > 0 && _rawLength <= 86400
    // only the sentinel means endless; a browser reports 0 between videos and through an
    // ad break, and calling that live claims something about the track instead of admitting
    // the length is not known yet
    readonly property bool endless:     _rawLength > 86400
    readonly property real length:      lengthKnown ? _rawLength : 0
    readonly property bool canSeek:     player ? player.canSeek : false
    // position still ticks without a length; only the ratio and the seek bar need one
    readonly property bool hasPosition: player !== null && player.positionSupported

    property real  _anchorPos:  0
    property real  _anchorMs:   0
    property real  positionNow: 0
    readonly property real positionRatio: length > 0 ? Math.max(0, Math.min(1, positionNow / length)) : 0
    function positionDemand(homeActive: bool, barVisible: bool, overview: bool): bool {
        return homeActive || (barVisible && !overview)
    }
    // The bar-anchored popup hosts the same MediaCard as the menu home tab, so its
    // seek controls need the timer even while the overview is active.
    readonly property bool positionVisible: root.positionDemand(
        MenuState.homeActive,
        ShellSettings.barShowMedia && root.shown && ShellSettings.mediaWidgetHelper,
        OverviewState.active) || MediaPopupState.open

    function _reanchor(): void {
        root._anchorPos = (player && player.positionSupported)
            ? root.finiteNonnegative(player.position) : 0
        root._anchorMs  = Date.now()
        _recompute()
    }
    function _recompute(): void {
        if (!player) { positionNow = 0; return }
        let p = root._anchorPos
        if (playing) p += (Date.now() - root._anchorMs) / 1000
        positionNow = root.length > 0 ? Math.max(0, Math.min(root.length, p)) : Math.max(0, p)
    }
    function seekToRatio(r: real): void {
        if (!player || !canSeek || length <= 0) return
        const ratio = Number(r)
        if (!isFinite(ratio)) return
        const target = Math.max(0, Math.min(1, ratio)) * length
        player.position = target
        root._anchorPos = target
        root._anchorMs  = Date.now()
        _recompute()
    }
    function formatTime(secs: real): string {
        const s  = (isFinite(secs) && secs > 0) ? Math.floor(secs) : 0
        const h  = Math.floor(s / 3600)
        const m  = Math.floor((s % 3600) / 60)
        const ss = String(s % 60).padStart(2, "0")
        return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`
    }

    Connections {
        target: root.player
        enabled: root.player !== null
        function onPositionChanged() { root._reanchor() }
    }
    onPositionVisibleChanged: if (positionVisible) root._reanchor()
    Timer {
        interval: 500; repeat: true
        running: root.playing && root.hasPosition && !Idle.isQuiet
            && root.positionVisible
        onTriggered: root._recompute()
    }

    onPlayerChanged: _reanchor()
    readonly property string artist: SafeText.singleLineText(
        player ? player.trackArtist : "", root.maxMetadataChars)
    readonly property string title: SafeText.singleLineText(
        player ? player.trackTitle : "", root.maxMetadataChars)
    readonly property string identity: SafeText.singleLineText(
        player ? player.identity : "", root.maxIdentityChars)
    readonly property string desktopEntry: SafeText.singleLineText(
        player ? player.desktopEntry : "", root.maxIdentityChars)

    function privacyPlaceholderSource(value): string {
        const clean = SafeText.singleLineText(value, root.maxMetadataChars)
        const match = clean.match(/^(.+?)\s+is playing media$/i)
        return match ? match[1].trim() : ""
    }

    function metadataIsPrivacyProtected(titleValue, artistValue, urlValue,
            identityValue, desktopEntryValue, dbusNameValue): bool {
        const placeholderSource = root.privacyPlaceholderSource(titleValue)
        if (placeholderSource.length === 0
                || String(artistValue || "").trim().length > 0
                || String(urlValue || "").trim().length > 0)
            return false

        const source = [placeholderSource, identityValue, desktopEntryValue, dbusNameValue]
            .join(" ").toLowerCase()
        return /(firefox|zen|librewolf|floorp|waterfox|chrome|chromium|brave|edge|opera|vivaldi|thorium)/.test(source)
    }

    readonly property string trackUrl: {
        const metadata = player ? player.metadata : null
        return SafeText.singleLineText(metadata ? metadata["xesam:url"] : "",
            root.maxArtSourceChars)
    }
    readonly property bool metadataPrivacyProtected: root.metadataIsPrivacyProtected(
        title, artist, trackUrl, identity, desktopEntry, player ? player.dbusName : "")
    readonly property string sourceLabel: {
        const placeholder = root.metadataPrivacyProtected
            ? root.privacyPlaceholderSource(title) : ""
        if (placeholder.length > 0) return placeholder
        if (identity.length > 0) return identity
        if (desktopEntry.length > 0) return desktopEntry
        return ""
    }
    readonly property string displayTitle: root.metadataPrivacyProtected
        ? "Media details hidden" : title
    readonly property string displayArtist: root.metadataPrivacyProtected
        ? (sourceLabel.length > 0
            ? "Private tab details stay in " + sourceLabel
            : "Private tab details stay in the browser")
        : artist

    // Spotify's Linux client reports an open.spotify.com/image link that 404s
    function normalizedArtUrl(raw): string {
        return String(raw ?? "")
            .replace("https://open.spotify.com/image/", "https://i.scdn.co/image/")
    }

    // i.scdn.co spells the edge length into the id prefix and publishes all three sizes
    // for every cover; clients that hand over the 64px form leave the tile a blur
    function upscaledArtUrl(raw): string {
        const match = String(raw ?? "").match(
            /^(https:\/\/i\.scdn\.co\/image\/)ab67616d(?:00004851|00001e02)([0-9a-f]{8,})$/i)
        return match ? match[1] + "ab67616d0000b273" + match[2] : ""
    }

    // the directory holding a locally played track, for the covers that sit beside it
    function trackDirectory(raw): string {
        const value = String(raw ?? "")
        if (value.slice(0, 8) !== "file:///") return ""
        let path = ""
        try { path = decodeURIComponent(value.slice(7)) } catch (error) { return "" }
        const cut = path.lastIndexOf("/")
        return cut > 0 && path.indexOf("/../") < 0 ? path.slice(0, cut) : ""
    }

    readonly property var sidecarArtNames: [
        "cover.jpg", "cover.png", "Cover.jpg",
        "folder.jpg", "folder.png", "Folder.jpg",
        "front.jpg", "AlbumArt.jpg"
    ]

    // remote art is allowed on purpose where notification icons are denied: mpris art genuinely is a url
    readonly property var artCandidates: {
        const out = []
        function offer(value) {
            const source = root.artSource(value)
            if (source.length > 0 && out.indexOf(source) < 0) out.push(source)
        }
        const reported = root.normalizedArtUrl(root.player ? root.player.trackArtUrl : "")
        offer(root.upscaledArtUrl(reported))
        offer(reported)
        const directory = root.trackDirectory(root.trackUrl)
        if (directory.length > 0)
            for (let i = 0; i < root.sidecarArtNames.length; i++)
                offer(directory + "/" + root.sidecarArtNames[i])
        return out
    }

    readonly property string artKey: root.artCandidates.join("\u0000")
    property int _artCandidate: 0
    onArtKeyChanged: root._artCandidate = 0

    readonly property string artUrl: {
        const candidates = root.artCandidates
        if (candidates.length === 0) return ""
        return candidates[Math.min(root._artCandidate, candidates.length - 1)]
    }

    // a view reports the load it could not finish; without this a cover url that 404s
    // retries itself forever while a readable cover sits unopened beside the track
    function artFailed(url: string): void {
        if (url !== root.artUrl) return
        if (root._artCandidate + 1 < root.artCandidates.length) root._artCandidate++
    }
    function retryArt(): void { root._artCandidate = 0 }

    property string stableArtUrl: ""
    function _syncStableArt(): void {
        if (root.artUrl.length > 0) {
            _staleArtClear.stop()
            root.stableArtUrl = root.artUrl
        } else if (!root.available) {
            _staleArtClear.stop()
            root.stableArtUrl = ""
        } else if (root.stableArtUrl.length > 0) {
            // MPRIS properties often arrive in separate D-Bus updates. Keep the
            // old cover briefly, but do not show it forever for a track with no art.
            _staleArtClear.restart()
        }
    }
    Timer {
        id: _staleArtClear
        interval: 750
        onTriggered: if (root.artUrl.length === 0) root.stableArtUrl = ""
    }
    onArtUrlChanged: _syncStableArt()
    onTitleChanged: { _reanchor(); _syncStableArt() }

    readonly property string playerName:
        !player              ? "" :
        desktopEntry.length > 0 ? desktopEntry :
        identity.length > 0     ? identity :
        SafeText.singleLineText(player.dbusName, root.maxIdentityChars)

    readonly property string label: {
        if (root.metadataPrivacyProtected)
            return sourceLabel.length > 0 ? sourceLabel + " · private media" : "Private media"
        if (ShellSettings.mediaWidgetFormat === "artist-title" && artist.length > 0 && title.length > 0)
            return SafeText.singleLineText(artist + " - " + title, root.maxMetadataChars)
        if (title.length > 0) return title
        if (artist.length > 0) return artist
        if (identity.length > 0) return identity
        if (desktopEntry.length > 0) return desktopEntry
        return player ? "Media" : ""
    }

    function togglePlay(): void {
        if (!canTogglePlaying) return
        player.togglePlaying()
    }

    function next(): void {
        if (!canGoNext) return
        player.next()
    }

    function previous(): void {
        if (!canGoPrevious) return
        player.previous()
    }

    // hardware media keys land here (nixos keybindings.nix binds XF86Audio*): going
    // through the shell instead of playerctl keeps the chords on the same player the
    // card and bar control -- including a source pinned with the < > steppers, which
    // playerctld's own last-active pick knows nothing about.
    //
    // no bootstrap property needed: shell.qml eagerly references MediaPopupState.open
    // (the media popup's PopupLoader.wantOpen binding), and MediaPopupState already
    // carries a top-level Connections{target: Media} to close itself when the player
    // drops -- that binding alone drags this singleton (and this IpcHandler) into
    // existence at shell start, the same way KeybindsPopupState.available bootstraps
    // Keybinds.
    IpcHandler {
        target: "media"
        function playPause(): void { root.togglePlay() }
        function next(): void { root.next() }
        function previous(): void { root.previous() }
    }
}
