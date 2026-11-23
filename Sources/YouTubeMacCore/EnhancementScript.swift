import Foundation

/// Generates lightweight JavaScript and CSS injected into YouTube tabs for distraction-free styling,
/// playback quality-of-life enhancements, and media telemetry.
public enum EnhancementScript {
    public static let messageHandlerName = "ytmacBridge"

    /// Bootstrap script registered as a `WKUserScript` at document end.
    public static func bootstrapScript(config: DistractionFreeConfig) -> String {
        let configJSON = encodeConfigJSON(config)
        let styleText = cssRules.replacingOccurrences(of: "`", with: "\\`")

        return """
        (() => {
            const initialConfig = \(configJSON);
            window.__ytmacConfig = initialConfig;

            const styleText = `\(styleText)`;
            const SHORTS_CARD_SELECTOR = [
                'ytd-reel-shelf-renderer',
                'ytd-video-renderer',
                'ytd-grid-video-renderer',
                'ytd-rich-item-renderer',
                'ytd-compact-video-renderer',
                'ytd-guide-entry-renderer'
            ].join(',');

            const SHORTS_SHELF_SELECTOR = [
                'ytd-rich-section-renderer',
                'ytd-rich-shelf-renderer',
                'grid-shelf-view-model'
            ].join(',');

            const QUALITY_LADDER = ['highres', 'hd2160', 'hd1440', 'hd1080', 'hd720', 'large', 'medium', 'small', 'tiny'];

            function ensureStyleElement() {
                if (document.getElementById('ytmac-style')) return;
                const styleEl = document.createElement('style');
                styleEl.id = 'ytmac-style';
                styleEl.textContent = styleText;
                (document.head || document.documentElement).appendChild(styleEl);
            }

            function setDatasetFlag(root, key, enabled) {
                const value = enabled ? 'true' : 'false';
                if (root.dataset[key] !== value) {
                    root.dataset[key] = value;
                }
            }

            function isYouTubeTVHost() {
                return location.hostname.toLowerCase() === 'tv.youtube.com';
            }

            function isStandardYouTubeHost() {
                return !isYouTubeTVHost() && /youtube\\.com$/i.test(location.hostname);
            }

            function isWatchPage() {
                if (isYouTubeTVHost()) {
                    // YouTube TV uses path-based /watch/<id>; /live is the Live EPG Guide (not a watch page).
                    return /^\\/watch\\/[^/?#]+/.test(location.pathname);
                }
                return location.pathname.startsWith('/watch') || /^\\/live\\/[^/?#]+/.test(location.pathname);
            }

            function getPlayer() {
                return document.getElementById('movie_player') || document.querySelector('.html5-video-player');
            }

            function isWatchPageWithPlayer() {
                return isWatchPage() && Boolean(getPlayer() || document.querySelector('video.html5-main-video'));
            }

            function getMainVideo() {
                const player = getPlayer();
                if (player) {
                    const v = player.querySelector('video.html5-main-video') || player.querySelector('video');
                    if (v) return v;
                }
                if (isWatchPage()) {
                    return document.querySelector('video.html5-main-video') || document.querySelector('video');
                }
                return null;
            }

            let lastProgrammaticMuteActionAt = 0;
            let lastKnownMuted = null;
            let lastMutedVideoId = '';

            window.__ytmacMarkProgrammaticMute = () => {
                lastProgrammaticMuteActionAt = Date.now();
            };

            function resolveMutedState(player, video) {
                try {
                    if (player && typeof player.isMuted === 'function') {
                        return Boolean(player.isMuted());
                    }
                } catch (_) {}
                return Boolean(video && (video.muted || video.volume === 0));
            }

            let tileResizeTimer = null;
            function scheduleTileWatchResizeSync() {
                if (isYouTubeTVHost()) return;
                const root = document.documentElement;
                if (!root || root.dataset.ytmacTilePlayer !== 'true' || root.dataset.ytmacOnWatch !== 'true') return;
                if (document.fullscreenElement) return;

                const syncOnce = () => {
                    if (document.fullscreenElement || isYouTubeTVHost()) return;
                    const r = document.documentElement;
                    if (!r || r.dataset.ytmacTilePlayer !== 'true' || r.dataset.ytmacOnWatch !== 'true') return;
                    window.dispatchEvent(new Event('resize'));
                    const p = getPlayer();
                    try {
                        if (p && typeof p.setSize === 'function') p.setSize();
                        if (p && typeof p.setInternalSize === 'function') p.setInternalSize();
                    } catch (_) {}
                };

                requestAnimationFrame(syncOnce);
                if (tileResizeTimer) {
                    clearTimeout(tileResizeTimer);
                }
                tileResizeTimer = setTimeout(() => {
                    tileResizeTimer = null;
                    requestAnimationFrame(syncOnce);
                }, 200);
            }

            const themeSheetCache = { dark: null, light: null };
            let themeSwapSeq = 0;

            function resolveEffectiveDark(appearance) {
                if (appearance === 'dark') return true;
                if (appearance === 'light') return false;
                return Boolean(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
            }

            function syncPrefThemeCookie(isDark) {
                if (!isStandardYouTubeHost()) return;
                const match = document.cookie.match(/(?:^|;\\s*)PREF=([^;]*)/);
                const rawPref = match ? match[1] : '';
                const parts = rawPref ? rawPref.split('&').filter(Boolean) : [];
                let foundF6 = false;
                let currF6 = 0;

                const nextParts = [];
                for (let i = 0; i < parts.length; i += 1) {
                    const part = parts[i];
                    if (part.startsWith('f6=')) {
                        foundF6 = true;
                        const parsed = parseInt(part.slice(3), 16);
                        currF6 = Number.isFinite(parsed) ? (parsed >>> 0) : 0;
                        continue;
                    }
                    nextParts.push(part);
                }

                const themeFlag = isDark ? 0x400 : 0x80000;
                const nextF6 = (((currF6 & ~0x80400) | themeFlag) >>> 0);
                nextParts.push('f6=' + nextF6.toString(16));

                const nextPref = nextParts.join('&');
                if (nextPref !== rawPref || !foundF6) {
                    document.cookie = 'PREF=' + nextPref + '; path=/; domain=.youtube.com; max-age=31536000; SameSite=Lax';
                }
            }

            function commitThemeAttributes(isDark) {
                const root = document.documentElement;
                if (!root) return;
                const targetScheme = isDark ? 'dark' : 'light';

                if (isDark) {
                    if (!root.hasAttribute('dark')) root.setAttribute('dark', '');
                } else if (root.hasAttribute('dark')) {
                    root.removeAttribute('dark');
                }

                if (root.style.colorScheme !== targetScheme) {
                    root.style.colorScheme = targetScheme;
                }
                if (root.dataset.ytmacTheme !== targetScheme) {
                    root.dataset.ytmacTheme = targetScheme;
                }

                const masthead = document.querySelector('ytd-masthead');
                if (masthead) {
                    if (isDark) {
                        if (!masthead.hasAttribute('dark')) masthead.setAttribute('dark', '');
                        masthead.classList.add('dark');
                    } else {
                        if (masthead.hasAttribute('dark')) masthead.removeAttribute('dark');
                        masthead.classList.remove('dark');
                    }
                }
            }

            function getKevlarBaseLinks() {
                return Array.from(document.querySelectorAll('link[rel="stylesheet"][href*="kevlar_base"]'));
            }

            function extractKevlarBaseHref(html) {
                const match = html.match(/href="(https:\\/\\/www\\.youtube\\.com\\/s\\/_\\/ytmainappweb\\/_\\/ss\\/k=ytmainappweb\\.kevlar_base[^"]+)"/)
                    || html.match(/href="(\\/s\\/_\\/ytmainappweb\\/_\\/ss\\/k=ytmainappweb\\.kevlar_base[^"]+)"/);
                if (!match || !match[1]) return null;
                return match[1].startsWith('/') ? (location.origin + match[1]) : match[1];
            }

            function swapKevlarStylesheetAndCommit(targetHref, isDark, seq) {
                const oldLinks = getKevlarBaseLinks();
                if (!targetHref || oldLinks.length === 0) {
                    if (seq === themeSwapSeq) {
                        commitThemeAttributes(isDark);
                    }
                    return;
                }
                if (oldLinks[0].href === targetHref) {
                    if (seq === themeSwapSeq) {
                        commitThemeAttributes(isDark);
                    }
                    return;
                }

                const link = document.createElement('link');
                link.rel = 'stylesheet';
                link.href = targetHref;
                let finished = false;
                const finish = (loaded) => {
                    if (finished) return;
                    finished = true;
                    if (seq !== themeSwapSeq) {
                        if (loaded) link.remove();
                        return;
                    }
                    if (loaded) {
                        for (let i = 0; i < oldLinks.length; i += 1) {
                            oldLinks[i].remove();
                        }
                        commitThemeAttributes(isDark);
                    } else {
                        link.remove();
                    }
                };
                link.onload = () => finish(true);
                link.onerror = () => finish(false);
                oldLinks[0].parentNode.insertBefore(link, oldLinks[0].nextSibling);
            }

            function applyTheme(cfg) {
                const root = document.documentElement;
                if (!root) return;
                const appearance = (cfg && cfg.appearance) ? cfg.appearance : 'system';
                const isDark = resolveEffectiveDark(appearance);
                const targetKey = isDark ? 'dark' : 'light';
                const currentIsDark = root.hasAttribute('dark');
                const currentKey = currentIsDark ? 'dark' : 'light';

                const currentLinks = getKevlarBaseLinks();
                if (currentLinks.length > 0 && !themeSheetCache[currentKey]) {
                    themeSheetCache[currentKey] = currentLinks[0].href;
                }

                syncPrefThemeCookie(isDark);

                if (currentIsDark === isDark) {
                    commitThemeAttributes(isDark);
                    return;
                }

                const seq = ++themeSwapSeq;
                if (currentLinks.length === 0) {
                    commitThemeAttributes(isDark);
                    return;
                }

                if (themeSheetCache[targetKey]) {
                    swapKevlarStylesheetAndCommit(themeSheetCache[targetKey], isDark, seq);
                    return;
                }

                if (!isStandardYouTubeHost()) {
                    if (!isYouTubeTVHost()) {
                        commitThemeAttributes(isDark);
                    }
                    return;
                }

                // Fetch YouTube's server-compiled kevlar_base stylesheet URL for the target theme using the updated PREF cookie,
                // then swap the stylesheet & toggle <html dark> atomically on load (zero playback interruption, zero broken contrast).
                fetch('/', { credentials: 'include', cache: 'no-store' })
                    .then((resp) => (resp && resp.ok ? resp.text() : ''))
                    .then((html) => {
                        if (seq !== themeSwapSeq || !html) return;
                        const nextHref = extractKevlarBaseHref(html);
                        if (nextHref) {
                            themeSheetCache[targetKey] = nextHref;
                            swapKevlarStylesheetAndCommit(nextHref, isDark, seq);
                        }
                    })
                    .catch(() => {});
            }

            function applyDatasetConfig(cfg) {
                const root = document.documentElement;
                if (!root) return;
                const isYTTV = isYouTubeTVHost();
                const hostTag = isYTTV ? 'yttv' : 'youtube';
                if (root.dataset.ytmacHost !== hostTag) {
                    root.dataset.ytmacHost = hostTag;
                }

                const prevOnWatch = root.dataset.ytmacOnWatch === 'true';
                const prevTilePlayer = root.dataset.ytmacTilePlayer === 'true';
                const onWatch = isWatchPageWithPlayer();
                const tilePlayer = Boolean(cfg.miniPlayerActive || cfg.multiviewTileActive);

                // Force www.youtube.com-only flags to false on tv.youtube.com so YouTube TV's guide & controls stay intact.
                setDatasetFlag(root, 'ytmacHideShorts', !isYTTV && cfg.hideShorts);
                setDatasetFlag(root, 'ytmacCleanChrome', !isYTTV && cfg.cleanWebChrome);
                setDatasetFlag(root, 'ytmacHideHeader', !isYTTV && cfg.hideWebHeader);
                setDatasetFlag(root, 'ytmacHideEndScreens', !isYTTV && cfg.hideEndScreens);
                setDatasetFlag(root, 'ytmacHideWatchRecs', !isYTTV && cfg.hideWatchRecommendations);
                setDatasetFlag(root, 'ytmacHideComments', !isYTTV && cfg.hideComments);
                setDatasetFlag(root, 'ytmacHideHomeFeed', !isYTTV && cfg.hideHomeFeed);
                setDatasetFlag(root, 'ytmacDisableAmbient', cfg.disableAmbientMode || Boolean(cfg.multiviewTileActive));
                setDatasetFlag(root, 'ytmacMiniPlayer', cfg.miniPlayerActive);
                setDatasetFlag(root, 'ytmacTilePlayer', tilePlayer);
                setDatasetFlag(root, 'ytmacOnWatch', onWatch);
                setDatasetFlag(root, 'ytmacAutoTheater', !isYTTV && cfg.autoTheaterMode);
                setDatasetFlag(root, 'ytmacRedirectShorts', !isYTTV && cfg.redirectShortsToWatch);

                if (!isYTTV) {
                    applyTheme(cfg);
                    if (cfg.autoTheaterMode && !document.cookie.includes('wide=1')) {
                        document.cookie = 'wide=1; path=/; domain=.youtube.com; max-age=31536000; SameSite=Lax';
                    }
                    if (tilePlayer && onWatch && (!prevOnWatch || !prevTilePlayer)) {
                        scheduleTileWatchResizeSync();
                    }
                }
            }

            function markShortsElements() {
                if (isYouTubeTVHost()) return;
                const cfg = window.__ytmacConfig;
                if (!cfg || !cfg.hideShorts) return;
                const links = document.querySelectorAll('a[href^="/shorts/"]:not([data-ytmac-checked])');
                for (let i = 0; i < links.length; i += 1) {
                    const link = links[i];
                    link.setAttribute('data-ytmac-checked', '1');

                    // Only hide whole Home shelf containers when they are PURE Shorts shelves
                    // (never hide mixed shelves containing normal /watch videos).
                    const shelf = link.closest(SHORTS_SHELF_SELECTOR);
                    if (shelf && !shelf.classList.contains('ytmac-shorts-hidden')) {
                        const isPureShortsShelf = shelf.hasAttribute('is-shorts')
                            || Boolean(shelf.querySelector('ytd-reel-shelf-renderer'))
                            || !shelf.querySelector('a[href^="/watch"]');
                        if (isPureShortsShelf) {
                            shelf.classList.add('ytmac-shorts-hidden');
                            continue;
                        }
                    }

                    const card = link.closest(SHORTS_CARD_SELECTOR);
                    if (card && !card.classList.contains('ytmac-shorts-hidden')) {
                        card.classList.add('ytmac-shorts-hidden');
                    }
                }
            }

            function detectEmptyHomeFeed() {
                if (isYouTubeTVHost()) return false;
                if (location.pathname !== '/' && location.pathname !== '') return false;
                const homeBrowse = document.querySelector('ytd-browse[page-subtype="home"]');
                if (!homeBrowse) return false;
                const visibleItems = homeBrowse.querySelectorAll('ytd-rich-item-renderer:not(.ytmac-shorts-hidden)');
                if (visibleItems.length > 0) return false;
                const hasNudge = Boolean(
                    homeBrowse.querySelector('ytd-feed-nudge-renderer, ytd-background-promo-renderer, #contents ytd-message-renderer')
                );
                return hasNudge;
            }

            function currentVideoId() {
                if (isYouTubeTVHost()) {
                    const match = location.pathname.match(/^\\/watch\\/([^/?#]+)/);
                    return match && match[1] ? match[1] : '';
                }
                if (location.pathname.startsWith('/watch')) {
                    const qv = new URLSearchParams(location.search).get('v');
                    if (qv) return qv;
                    const pathMatch = location.pathname.match(/^\\/watch\\/([^/?#]+)/);
                    return pathMatch && pathMatch[1] ? pathMatch[1] : '';
                }
                const liveMatch = location.pathname.match(/^\\/live\\/([^/?#]+)/);
                if (liveMatch && liveMatch[1]) {
                    return liveMatch[1];
                }
                return '';
            }

            function maybeRedirectShorts() {
                if (isYouTubeTVHost()) return;
                const cfg = window.__ytmacConfig;
                if (!cfg || !cfg.redirectShortsToWatch) return;
                const match = location.pathname.match(/^\\/shorts\\/([^/?#]+)/);
                if (match && match[1]) {
                    const target = '/watch?v=' + encodeURIComponent(match[1]);
                    location.replace(target);
                }
            }

            // --- Auto Theater Mode (bounded one-shot per videoId) ---
            let lastTheaterVideoId = null;
            let theaterAttemptTimer = null;
            let theaterDelayTimer = null;

            function clearTheaterTimers() {
                if (theaterDelayTimer) {
                    clearTimeout(theaterDelayTimer);
                    theaterDelayTimer = null;
                }
                if (theaterAttemptTimer) {
                    clearInterval(theaterAttemptTimer);
                    theaterAttemptTimer = null;
                }
            }

            function maybeEnableTheaterMode() {
                if (isYouTubeTVHost()) return;
                const cfg = window.__ytmacConfig;
                if (!cfg || !cfg.autoTheaterMode) return;
                if (!isWatchPage()) return;
                const videoId = currentVideoId();
                if (!videoId || lastTheaterVideoId === videoId) return;

                clearTheaterTimers();

                let attempts = 0;
                const tryEnable = () => {
                    attempts += 1;
                    const activeCfg = window.__ytmacConfig;
                    if (!activeCfg || !activeCfg.autoTheaterMode || currentVideoId() !== videoId) {
                        clearTheaterTimers();
                        return;
                    }
                    const flexy = document.querySelector('ytd-watch-flexy');
                    const player = document.getElementById('movie_player');
                    const sizeBtn = document.querySelector('.ytp-size-button');
                    const isFullscreen = Boolean(document.fullscreenElement || (player && player.classList.contains('ytp-fullscreen')));

                    if (flexy && flexy.hasAttribute('theater')) {
                        lastTheaterVideoId = videoId;
                        clearTheaterTimers();
                        return;
                    }

                    if (flexy && sizeBtn && !isFullscreen) {
                        sizeBtn.click();
                        lastTheaterVideoId = videoId;
                        clearTheaterTimers();
                        return;
                    }

                    if (attempts >= 6) {
                        lastTheaterVideoId = videoId;
                        clearTheaterTimers();
                    }
                };

                theaterDelayTimer = setTimeout(() => {
                    theaterDelayTimer = null;
                    tryEnable();
                    if (lastTheaterVideoId !== videoId) {
                        theaterAttemptTimer = setInterval(tryEnable, 250);
                    }
                }, 250);
            }

            // --- Preferred Video Quality (bounded one-shot per videoId, HDR10-safe) ---
            let lastQualityVideoId = null;
            let qualityAttemptTimer = null;
            let qualityDelayTimer = null;

            function clearQualityTimers() {
                if (qualityDelayTimer) {
                    clearTimeout(qualityDelayTimer);
                    qualityDelayTimer = null;
                }
                if (qualityAttemptTimer) {
                    clearInterval(qualityAttemptTimer);
                    qualityAttemptTimer = null;
                }
            }

            function maybeApplyPreferredQuality() {
                const cfg = window.__ytmacConfig;
                if (!cfg || !cfg.preferredQuality) return;
                if (!isWatchPage()) return;
                const videoId = currentVideoId();
                if (!videoId || lastQualityVideoId === videoId) return;

                clearQualityTimers();

                let attempts = 0;
                const tryQuality = () => {
                    attempts += 1;
                    const activeCfg = window.__ytmacConfig;
                    if (!activeCfg || !activeCfg.preferredQuality || currentVideoId() !== videoId) {
                        clearQualityTimers();
                        return;
                    }
                    const player = getPlayer();
                    if (player && typeof player.getAvailableQualityLevels === 'function') {
                        try {
                            const available = player.getAvailableQualityLevels();
                            if (Array.isArray(available) && available.length > 0) {
                                const usable = available.filter((q) => q && q !== 'auto');
                                if (usable.length > 0) {
                                    const prefIdx = QUALITY_LADDER.indexOf(activeCfg.preferredQuality);
                                    let chosen = usable[0];
                                    if (prefIdx >= 0) {
                                        for (let i = 0; i < usable.length; i += 1) {
                                            const qIdx = QUALITY_LADDER.indexOf(usable[i]);
                                            if (qIdx >= prefIdx) {
                                                chosen = usable[i];
                                                break;
                                            }
                                        }
                                    }
                                    if (typeof player.setPlaybackQualityRange === 'function') {
                                        player.setPlaybackQualityRange(chosen, chosen);
                                    }
                                    if (typeof player.setPlaybackQuality === 'function') {
                                        player.setPlaybackQuality(chosen);
                                    }
                                    lastQualityVideoId = videoId;
                                    clearQualityTimers();
                                    return;
                                }
                            }
                        } catch (_) {}
                    }

                    if (attempts >= 8) {
                        lastQualityVideoId = videoId;
                        clearQualityTimers();
                    }
                };

                qualityDelayTimer = setTimeout(() => {
                    qualityDelayTimer = null;
                    tryQuality();
                    if (lastQualityVideoId !== videoId) {
                        qualityAttemptTimer = setInterval(tryQuality, 300);
                    }
                }, 250);
            }

            // --- Default Playback Speed (one-shot per videoId) ---
            let lastSpeedVideoId = null;

            function maybeApplyDefaultSpeed() {
                const cfg = window.__ytmacConfig;
                if (!cfg || !isWatchPage()) return;
                const videoId = currentVideoId();
                if (!videoId || lastSpeedVideoId === videoId) return;

                const video = getMainVideo();
                if (!video || video.readyState < 1) return;

                const target = Number(cfg.defaultPlaybackRate);
                if (!Number.isFinite(target) || target < 0.25 || target > 4.0) {
                    lastSpeedVideoId = videoId;
                    return;
                }

                lastSpeedVideoId = videoId;
                if (Math.abs((video.playbackRate || 1.0) - target) >= 0.01) {
                    const player = getPlayer();
                    try {
                        if (player && typeof player.setPlaybackRate === 'function') {
                            player.setPlaybackRate(target);
                        }
                    } catch (_) {}
                    video.playbackRate = target;
                }
            }

            // --- Prefer Original Audio Track (anti-auto-dubbing, bounded one-shot per videoId) ---
            let lastAudioTrackVideoId = null;
            let audioTrackAttemptTimer = null;
            let audioTrackDelayTimer = null;

            function clearAudioTrackTimers() {
                if (audioTrackDelayTimer) {
                    clearTimeout(audioTrackDelayTimer);
                    audioTrackDelayTimer = null;
                }
                if (audioTrackAttemptTimer) {
                    clearInterval(audioTrackAttemptTimer);
                    audioTrackAttemptTimer = null;
                }
            }

            function describeAudioTrack(track) {
                if (!track || typeof track !== 'object') return '';
                const parts = [];
                try {
                    if (typeof track.getLanguageInfo === 'function') {
                        const info = track.getLanguageInfo();
                        if (info) {
                            if (info.name) parts.push(String(info.name));
                            if (info.id) parts.push(String(info.id));
                        }
                    }
                } catch (_) {}
                try {
                    for (const key of Object.keys(track)) {
                        const val = track[key];
                        if (typeof val === 'string') {
                            parts.push(val);
                        } else if (val && typeof val === 'object') {
                            if (typeof val.name === 'string') parts.push(val.name);
                            if (typeof val.displayName === 'string') parts.push(val.displayName);
                            if (typeof val.id === 'string') parts.push(val.id);
                            if (typeof val.xtags === 'string') parts.push(val.xtags);
                        }
                    }
                } catch (_) {}
                return parts.join(' ');
            }

            function isOriginalAudioTrack(track) {
                const desc = describeAudioTrack(track);
                return /\\boriginal\\b|acont=original|audioTrackType=ORIGINAL/i.test(desc);
            }

            function maybeSelectOriginalAudioTrack() {
                const cfg = window.__ytmacConfig;
                if (!cfg || !cfg.preferOriginalAudio) return;
                if (!isWatchPage()) return;
                const videoId = currentVideoId();
                if (!videoId || lastAudioTrackVideoId === videoId) return;

                clearAudioTrackTimers();

                let attempts = 0;
                const tryAudioTrack = () => {
                    attempts += 1;
                    const activeCfg = window.__ytmacConfig;
                    if (!activeCfg || !activeCfg.preferOriginalAudio || currentVideoId() !== videoId) {
                        clearAudioTrackTimers();
                        return;
                    }
                    const player = getPlayer();
                    if (player && typeof player.getAvailableAudioTracks === 'function' && typeof player.setAudioTrack === 'function') {
                        try {
                            const tracks = player.getAvailableAudioTracks();
                            if (Array.isArray(tracks) && tracks.length > 0) {
                                if (tracks.length > 1) {
                                    const current = typeof player.getAudioTrack === 'function' ? player.getAudioTrack() : null;
                                    if (!current || !isOriginalAudioTrack(current)) {
                                        const originalTrack = tracks.find((t) => isOriginalAudioTrack(t));
                                        if (originalTrack) {
                                            player.setAudioTrack(originalTrack);
                                        }
                                    }
                                }
                                lastAudioTrackVideoId = videoId;
                                clearAudioTrackTimers();
                                return;
                            }
                        } catch (_) {}
                    }

                    if (attempts >= 6) {
                        lastAudioTrackVideoId = videoId;
                        clearAudioTrackTimers();
                    }
                };

                audioTrackDelayTimer = setTimeout(() => {
                    audioTrackDelayTimer = null;
                    tryAudioTrack();
                    if (lastAudioTrackVideoId !== videoId) {
                        audioTrackAttemptTimer = setInterval(tryAudioTrack, 350);
                    }
                }, 400);
            }

            // --- Scrubber Drag Tracking (prevents dragstart hijacking, mid-drag UI thrashing, and SponsorBlock fighting user scrub) ---
            let isScrubbing = false;
            let wasPlayingBeforeScrub = false;
            let scrubSettleTimer = null;

            function clearScrubSettleTimer() {
                if (scrubSettleTimer) {
                    clearTimeout(scrubSettleTimer);
                    scrubSettleTimer = null;
                }
            }

            function beginScrubInteraction(target) {
                if (!target) return;
                const el = target.nodeType === 1 ? target : target.parentElement;
                if (!el || typeof el.closest !== 'function') return;
                if (!el.closest('#movie_player .ytp-progress-bar-container, #movie_player .ytp-progress-bar, .html5-video-player .ytp-progress-bar-container, .html5-video-player .ytp-progress-bar')) return;

                clearScrubSettleTimer();
                if (!isScrubbing) {
                    const video = getMainVideo();
                    wasPlayingBeforeScrub = Boolean(video && !video.paused && !video.ended);
                }
                isScrubbing = true;
            }

            function endScrubInteraction() {
                if (!isScrubbing) return;
                isScrubbing = false;
                clearScrubSettleTimer();
                scrubSettleTimer = setTimeout(() => {
                    scrubSettleTimer = null;
                    wasPlayingBeforeScrub = false;
                    emitMediaState(true);
                }, 250);
            }

            function isScrubSuppressingStateChange(video) {
                if (isScrubbing) return true;
                return Boolean(wasPlayingBeforeScrub && video && (video.seeking || video.readyState < 2));
            }

            // --- Auto-Dismiss "Video paused. Continue watching?" (event-driven on video pause, zero observers) ---
            let continueWatchingTimer = null;

            function maybeDismissContinueWatching(video) {
                const cfg = window.__ytmacConfig;
                if (!cfg || !cfg.autoDismissContinueWatching) return;
                if (!video || video.ended || isScrubbing || video.seeking) return;

                if (continueWatchingTimer) {
                    clearTimeout(continueWatchingTimer);
                }
                continueWatchingTimer = setTimeout(() => {
                    continueWatchingTimer = null;
                    const activeCfg = window.__ytmacConfig;
                    if (!activeCfg || !activeCfg.autoDismissContinueWatching) return;
                    if (!video.paused || video.ended) return;

                    const dialogs = document.querySelectorAll('yt-confirm-dialog-renderer');
                    for (let i = 0; i < dialogs.length; i += 1) {
                        const dialog = dialogs[i];
                        if (!dialog || dialog.offsetParent === null) continue;
                        const paperDialog = dialog.closest('tp-yt-paper-dialog');
                        if (paperDialog && (paperDialog.getAttribute('aria-hidden') === 'true' || paperDialog.style.display === 'none')) {
                            continue;
                        }
                        const confirmBtn = dialog.querySelector('#confirm-button button, #confirm-button yt-button-shape button, #confirm-button');
                        if (!confirmBtn || confirmBtn.offsetParent === null) continue;

                        const cancelBtn = dialog.querySelector('#cancel-button');
                        const cancelHidden = !cancelBtn || cancelBtn.hidden || cancelBtn.style.display === 'none' || cancelBtn.offsetParent === null;
                        const text = (dialog.textContent || '').trim();
                        const matchesPromptText = /continue watching|video paused|still watching/i.test(text);

                        if (matchesPromptText || (cancelHidden && text.length > 0)) {
                            confirmBtn.click();
                            break;
                        }
                    }
                }, 200);
            }

            // --- SponsorBlock Segment Skipping (passive timeupdate, skip each segment once) ---
            let sponsorState = { videoId: '', segments: [], skippedIndices: new Set() };

            function checkSponsorSkip(video) {
                const cfg = window.__ytmacConfig;
                if (!cfg || !cfg.sponsorBlockEnabled) return;
                if (!video || video.paused || video.ended || isScrubbing || video.seeking) return;
                const activeId = currentVideoId();
                if (!activeId || sponsorState.videoId !== activeId || sponsorState.segments.length === 0) return;

                const t = video.currentTime;
                if (!Number.isFinite(t)) return;

                for (let i = 0; i < sponsorState.segments.length; i += 1) {
                    if (sponsorState.skippedIndices.has(i)) continue;
                    const seg = sponsorState.segments[i];
                    if (t >= seg[0] && t < seg[1] - 0.35) {
                        sponsorState.skippedIndices.add(i);
                        const target = Number.isFinite(video.duration) ? Math.min(video.duration, seg[1]) : seg[1];
                        video.currentTime = target;
                        const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);
                        if (handler) {
                            handler.postMessage({
                                event: 'sponsorSkipped',
                                videoId: activeId,
                                category: seg[2] || 'sponsor'
                            });
                        }
                        break;
                    }
                }
            }

            window.__ytmacSetSponsorSegments = (videoId, segments) => {
                sponsorState = {
                    videoId: String(videoId || ''),
                    segments: Array.isArray(segments) ? segments : [],
                    skippedIndices: new Set()
                };
                const video = getMainVideo();
                if (video) {
                    checkSponsorSkip(video);
                }
            };

            function cleanTitle(raw) {
                return (raw || '')
                    .replace(/^\\(\\d+\\)\\s*/, '')
                    .replace(/\\s*-\\s*YouTube$/i, '')
                    .trim();
            }

            function extractMediaMetadata() {
                const titleNode = document.querySelector('ytd-watch-metadata h1 yt-formatted-string, ytd-watch-metadata h1, h1.ytd-video-primary-info-renderer');
                const channelNode = document.querySelector('ytd-watch-metadata ytd-channel-name a, #owner #channel-name a');
                const title = cleanTitle(titleNode ? titleNode.textContent : document.title);
                const channel = channelNode ? (channelNode.textContent || '').trim() : '';
                const channelURL = channelNode && channelNode.href ? String(channelNode.href) : '';
                return { title, channel, channelURL };
            }

            function detectHDR() {
                const player = getPlayer();
                if (!player) return false;
                try {
                    if (typeof player.getPlaybackQualityLabel === 'function') {
                        const label = String(player.getPlaybackQualityLabel() || '');
                        if (/\\bHDR\\b/i.test(label)) return true;
                        if (label.length > 0) return false;
                    }
                    if (typeof player.getStatsForNerds === 'function') {
                        const stats = player.getStatsForNerds() || {};
                        const info = (stats.codecs || '') + ' ' + (stats.color || '');
                        if (/\\b(vp09\\.02|av01\\.\\d+\\.\\d+[MH]\\.10|smpte2084|arib-std-b67|bt2020)\\b/i.test(info)) {
                            return true;
                        }
                    }
                } catch (_) {}
                return false;
            }

            let boundVideo = null;
            let lastTimeEmit = 0;
            let lastEmittedKey = '';

            function emitMediaState(force) {
                const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);
                if (!handler) return;

                const now = Date.now();
                if (!force && now - lastTimeEmit < 1000) return;

                const video = getMainVideo();
                const player = getPlayer();
                const flexy = document.querySelector('ytd-watch-flexy');
                const { title, channel, channelURL } = extractMediaMetadata();
                const isTheater = Boolean(flexy && flexy.hasAttribute('theater'));
                const isHomeFeedEmpty = detectEmptyHomeFeed();

                const payload = !video ? {
                    hasVideo: false,
                    isPlaying: false,
                    title,
                    channel,
                    channelURL,
                    urlString: location.href,
                    currentTime: 0,
                    duration: 0,
                    isMuted: false,
                    isPiP: false,
                    isTheater,
                    isHDR: false,
                    playbackRate: 1.0,
                    isHomeFeedEmpty
                } : (() => {
                    const isPiP = document.pictureInPictureElement === video ||
                        (typeof video.webkitPresentationMode === 'string' && video.webkitPresentationMode === 'picture-in-picture');
                    const hasVideo = isWatchPage() && Boolean(video.src || video.currentSrc || video.readyState > 0);
                    let isMuted = Boolean(video.muted || video.volume === 0);
                    try {
                        if (player && typeof player.isMuted === 'function') {
                            isMuted = Boolean(player.isMuted());
                        }
                    } catch (_) {}
                    const rate = Number.isFinite(video.playbackRate) && video.playbackRate > 0 ? video.playbackRate : 1.0;
                    const rawPlaying = hasVideo && !video.paused && !video.ended && video.readyState >= 2;
                    const effectivePlaying = (isScrubSuppressingStateChange(video) && wasPlayingBeforeScrub && hasVideo)
                        ? true
                        : rawPlaying;
                    return {
                        hasVideo,
                        isPlaying: effectivePlaying,
                        title,
                        channel,
                        channelURL,
                        urlString: location.href,
                        currentTime: Number.isFinite(video.currentTime) ? video.currentTime : 0,
                        duration: Number.isFinite(video.duration) ? video.duration : 0,
                        isMuted,
                        isPiP: Boolean(isPiP),
                        isTheater,
                        isHDR: hasVideo && detectHDR(),
                        playbackRate: rate,
                        isHomeFeedEmpty
                    };
                })();

                const secTime = Math.floor(payload.currentTime);
                const secDur = Math.floor(payload.duration);
                const rateKey = Math.round(payload.playbackRate * 100);
                const key = [
                    payload.hasVideo,
                    payload.isPlaying,
                    payload.title,
                    payload.channel,
                    payload.channelURL,
                    payload.urlString,
                    payload.isMuted,
                    payload.isPiP,
                    payload.isTheater,
                    payload.isHDR,
                    rateKey,
                    payload.isHomeFeedEmpty,
                    secTime,
                    secDur
                ].join('|');

                if (key === lastEmittedKey) return;
                lastEmittedKey = key;
                lastTimeEmit = now;
                handler.postMessage(payload);
            }

            window.__ytmacEmitStateNow = () => emitMediaState(true);

            function bindVideoListeners() {
                const video = getMainVideo();
                if (video === boundVideo) return;
                boundVideo = video;
                if (!video) {
                    emitMediaState(true);
                    return;
                }

                const immediateEvents = [
                    'play', 'playing', 'pause', 'ended', 'seeked', 'loadedmetadata', 'durationchange',
                    'volumechange', 'ratechange', 'webkitpresentationmodechanged',
                    'enterpictureinpicture', 'leavepictureinpicture', 'emptied'
                ];
                for (const evt of immediateEvents) {
                    video.addEventListener(evt, () => {
                        if (evt === 'pause') {
                            maybeDismissContinueWatching(video);
                            if (isScrubbing) return;
                        } else if (evt === 'playing') {
                            if (!isScrubbing && scrubSettleTimer) {
                                clearScrubSettleTimer();
                                wasPlayingBeforeScrub = false;
                            }
                        } else if (evt === 'ended') {
                            const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);
                            if (handler) {
                                handler.postMessage({
                                    event: 'videoEnded',
                                    urlString: location.href
                                });
                            }
                        } else if (evt === 'seeked') {
                            if (!isScrubbing && !wasPlayingBeforeScrub && scrubSettleTimer) {
                                clearScrubSettleTimer();
                            }
                        } else if (evt === 'volumechange') {
                            const player = getPlayer();
                            const nowMuted = resolveMutedState(player, video);
                            const vid = currentVideoId();
                            if (isWatchPage()
                                && (Date.now() - lastProgrammaticMuteActionAt > 500)
                                && lastKnownMuted === true
                                && nowMuted === false
                                && vid
                                && vid === lastMutedVideoId) {
                                const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);
                                if (handler) {
                                    handler.postMessage({
                                        event: 'userUnmuted',
                                        urlString: location.href
                                    });
                                }
                            }
                            lastKnownMuted = nowMuted;
                            lastMutedVideoId = vid;
                        } else if (evt === 'loadedmetadata') {
                            const player = getPlayer();
                            lastKnownMuted = resolveMutedState(player, video);
                            lastMutedVideoId = currentVideoId();
                            maybeApplyDefaultSpeed();
                            maybeApplyPreferredQuality();
                            maybeSelectOriginalAudioTrack();
                            extractAndEmitChapters();
                        }
                        emitMediaState(true);
                    }, { passive: true });
                }
                video.addEventListener('timeupdate', () => {
                    checkSponsorSkip(video);
                    if (isScrubbing) return;
                    emitMediaState(false);
                }, { passive: true });

                lastKnownMuted = resolveMutedState(getPlayer(), video);
                lastMutedVideoId = currentVideoId();
                maybeApplyDefaultSpeed();
                extractAndEmitChapters();
                emitMediaState(true);
            }

            let lastEmittedChaptersSig = '';
            function extractStructuredChaptersFromWatchFlexy() {
                const flexy = document.querySelector('ytd-watch-flexy');
                const rootData = flexy && (flexy.data || (flexy.__data && flexy.__data.data));
                const overlay = rootData && rootData.playerOverlays && rootData.playerOverlays.playerOverlayRenderer;
                const decorated = overlay && overlay.decoratedPlayerBarRenderer && overlay.decoratedPlayerBarRenderer.decoratedPlayerBarRenderer;
                const playerBar = decorated && decorated.playerBar && decorated.playerBar.multiMarkersPlayerBarRenderer;
                const markersMap = playerBar && Array.isArray(playerBar.markersMap) ? playerBar.markersMap : null;
                if (!markersMap) return [];

                for (const entry of markersMap) {
                    const chapters = entry && entry.value && Array.isArray(entry.value.chapters) ? entry.value.chapters : null;
                    if (!chapters || chapters.length < 2) continue;
                    const parsed = [];
                    for (const ch of chapters) {
                        const r = ch && ch.chapterRenderer;
                        if (!r) continue;
                        const title = (r.title && (r.title.simpleText || (Array.isArray(r.title.runs) ? r.title.runs.map(x => x.text || '').join('') : ''))) || '';
                        const ms = Number(r.timeRangeStartMillis);
                        if (title && Number.isFinite(ms) && ms >= 0) {
                            parsed.push({ title: title.trim(), startSeconds: Math.floor(ms / 1000) });
                        }
                    }
                    if (parsed.length >= 2) return parsed;
                }
                return [];
            }

            function extractAndEmitChapters() {
                const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);
                if (!handler) return;

                if (isYouTubeTVHost() || !isWatchPage()) {
                    if (lastEmittedChaptersSig !== 'empty') {
                        lastEmittedChaptersSig = 'empty';
                        handler.postMessage({
                            event: 'chaptersUpdated',
                            videoId: '',
                            chapters: [],
                            description: ''
                        });
                    }
                    return;
                }

                const vid = currentVideoId();
                if (!vid) return;

                let structured = [];
                try {
                    structured = extractStructuredChaptersFromWatchFlexy();
                } catch (_) {}

                let description = '';
                try {
                    const player = getPlayer();
                    const resp = player && typeof player.getPlayerResponse === 'function' ? player.getPlayerResponse() : null;
                    if (resp && resp.videoDetails && resp.videoDetails.videoId === vid && typeof resp.videoDetails.shortDescription === 'string') {
                        description = resp.videoDetails.shortDescription;
                    }
                } catch (_) {}

                const sig = vid + '|' + structured.length + '|' + (structured.length ? structured[0].title : '') + '|' + description.length;
                if (sig === lastEmittedChaptersSig) return;
                lastEmittedChaptersSig = sig;

                handler.postMessage({
                    event: 'chaptersUpdated',
                    videoId: vid,
                    chapters: structured,
                    description: structured.length >= 2 ? '' : description
                });
            }

            let shortsPostNavTimer = null;
            function schedulePostNavigationShortsPass() {
                if (shortsPostNavTimer) {
                    clearTimeout(shortsPostNavTimer);
                }
                const delay = isYouTubeTVHost() ? 400 : 700;
                shortsPostNavTimer = setTimeout(() => {
                    shortsPostNavTimer = null;
                    const cfg = window.__ytmacConfig || initialConfig;
                    applyDatasetConfig(cfg);
                    markShortsElements();
                    bindVideoListeners();
                    extractAndEmitChapters();
                    emitMediaState(true);
                }, delay);
            }

            let prevConfigQuality = initialConfig.preferredQuality;
            let prevConfigSpeed = initialConfig.defaultPlaybackRate;

            window.__ytmacApplyConfigOnly = () => {
                ensureStyleElement();
                const cfg = window.__ytmacConfig || initialConfig;
                applyDatasetConfig(cfg);
                if (cfg.hideShorts && !isYouTubeTVHost()) {
                    markShortsElements();
                }
                if (cfg.preferredQuality !== prevConfigQuality) {
                    const oldQuality = prevConfigQuality;
                    prevConfigQuality = cfg.preferredQuality;
                    if (cfg.preferredQuality) {
                        lastQualityVideoId = null;
                        maybeApplyPreferredQuality();
                    } else if (oldQuality && !cfg.preferredQuality) {
                        // Explicitly unlock ABR when transitioning from a Multiview quality cap back to .auto ("")
                        clearQualityTimers();
                        lastQualityVideoId = null;
                        const player = getPlayer();
                        try {
                            if (player && typeof player.setPlaybackQualityRange === 'function') {
                                player.setPlaybackQualityRange('tiny', 'highres');
                            }
                            if (player && typeof player.setPlaybackQuality === 'function') {
                                player.setPlaybackQuality('default');
                            }
                        } catch (_) {}
                    }
                }
                if (cfg.defaultPlaybackRate !== prevConfigSpeed) {
                    prevConfigSpeed = cfg.defaultPlaybackRate;
                    lastSpeedVideoId = null;
                    maybeApplyDefaultSpeed();
                }
            };

            window.__ytmacApplyRuntime = () => {
                ensureStyleElement();
                applyDatasetConfig(window.__ytmacConfig || initialConfig);
                maybeRedirectShorts();
                markShortsElements();
                schedulePostNavigationShortsPass();
                maybeEnableTheaterMode();
                maybeApplyPreferredQuality();
                maybeSelectOriginalAudioTrack();
                bindVideoListeners();
                maybeApplyDefaultSpeed();
                emitMediaState(true);
            };

            if (!window.__ytmacInitialized) {
                window.__ytmacInitialized = true;

                let lastObservedHref = location.href;
                let lastObservedVideoId = currentVideoId();
                const handleRouteChange = () => {
                    const nextVideoId = currentVideoId();
                    if (location.href !== lastObservedHref || nextVideoId !== lastObservedVideoId) {
                        lastObservedHref = location.href;
                        lastObservedVideoId = nextVideoId;
                        lastTheaterVideoId = null;
                        lastQualityVideoId = null;
                        lastSpeedVideoId = null;
                        lastAudioTrackVideoId = null;
                        lastKnownMuted = null;
                        lastMutedVideoId = '';
                        if (sponsorState.videoId !== nextVideoId) {
                            sponsorState = { videoId: '', segments: [], skippedIndices: new Set() };
                        }
                    }
                    window.__ytmacApplyRuntime();
                };

                window.__ytmacHandleRouteChange = handleRouteChange;

                window.addEventListener('yt-navigate-finish', handleRouteChange, true);
                window.addEventListener('yt-page-data-updated', () => {
                    const cfg = window.__ytmacConfig || initialConfig;
                    applyDatasetConfig(cfg);
                    bindVideoListeners();
                    maybeApplyDefaultSpeed();
                    maybeApplyPreferredQuality();
                    maybeSelectOriginalAudioTrack();
                    extractAndEmitChapters();
                    emitMediaState(true);
                    markShortsElements();
                }, true);
                window.addEventListener('popstate', handleRouteChange, true);
                window.addEventListener('hashchange', handleRouteChange, true);

                if (window.matchMedia) {
                    const colorSchemeQuery = window.matchMedia('(prefers-color-scheme: dark)');
                    const handleColorSchemeChange = () => {
                        const cfg = window.__ytmacConfig || initialConfig;
                        if (cfg.appearance === 'system' && !isYouTubeTVHost()) {
                            applyTheme(cfg);
                        }
                    };
                    if (typeof colorSchemeQuery.addEventListener === 'function') {
                        colorSchemeQuery.addEventListener('change', handleColorSchemeChange);
                    }
                }

                // Prevent WebKit HTML5 native drag-and-drop from hijacking YouTube / YouTube TV scrubber bars.
                window.addEventListener('dragstart', (ev) => {
                    const target = ev.target;
                    const el = target && target.nodeType === 1 ? target : (target && target.parentElement);
                    if (el && typeof el.closest === 'function' && el.closest('#movie_player, .html5-video-player')) {
                        ev.preventDefault();
                    }
                }, true);

                window.addEventListener('pointerdown', (ev) => beginScrubInteraction(ev.target), true);
                window.addEventListener('mousedown', (ev) => beginScrubInteraction(ev.target), true);
                window.addEventListener('pointerup', endScrubInteraction, true);
                window.addEventListener('mouseup', endScrubInteraction, true);
                window.addEventListener('pointercancel', endScrubInteraction, true);
                window.addEventListener('blur', endScrubInteraction, true);

                let lastScrollScan = 0;
                window.addEventListener('scroll', () => {
                    const cfg = window.__ytmacConfig;
                    if (!cfg || !cfg.hideShorts) return;
                    const now = Date.now();
                    if (now - lastScrollScan < 500) return;
                    lastScrollScan = now;
                    markShortsElements();
                }, { passive: true });
            }

            window.__ytmacApplyRuntime();
        })();
        """
    }

    /// Script evaluated in live tabs only when distraction-free config or mini-player state actually changes.
    public static func applyConfigScript(_ config: DistractionFreeConfig, triggerResize: Bool = false) -> String {
        let configJSON = encodeConfigJSON(config)
        let resizeLine = triggerResize ? "\nrequestAnimationFrame(() => window.dispatchEvent(new Event('resize')));" : ""
        return """
        (() => {
            window.__ytmacConfig = \(configJSON);
            if (typeof window.__ytmacApplyConfigOnly === 'function') {
                window.__ytmacApplyConfigOnly();
            }\(resizeLine)
        })();
        """
    }

    /// One-shot viewport & YouTube player resize notification fired strictly after a WKWebView returns to full single-tab layout.
    public static let notifyViewportResizeScript = """
    (() => {
        const ds = document.documentElement.dataset;
        if (document.fullscreenElement || ds.ytmacMiniPlayer === 'true' || ds.ytmacTilePlayer === 'true') return;
        requestAnimationFrame(() => {
            const d = document.documentElement.dataset;
            if (document.fullscreenElement || d.ytmacMiniPlayer === 'true' || d.ytmacTilePlayer === 'true') return;
            window.dispatchEvent(new Event('resize'));
            const p = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
            try {
                if (p && typeof p.setSize === 'function') p.setSize();
                if (p && typeof p.setInternalSize === 'function') p.setInternalSize();
            } catch (_) {}
        });
    })();
    """

    /// Lightweight SPA route-change hook invoked from `BrowserTab`'s URL KVO (supports `tv.youtube.com` History API transitions).
    public static let notifyRouteChangedScript = """
    (() => {
        if (typeof window.__ytmacHandleRouteChange === 'function') {
            window.__ytmacHandleRouteChange();
        }
    })();
    """

    /// Pushes fetched SponsorBlock segments for a single `videoID` into the page.
    public static func setSponsorSegmentsScript(videoID: String, segments: [SponsorSegment]) -> String {
        let safeVideoID = escapeJSString(videoID)
        let arrayLiteral = segments.map { seg -> String in
            let safeCat = escapeJSString(seg.category)
            return "[\(seg.start),\(seg.end),\"\(safeCat)\"]"
        }.joined(separator: ",")
        return """
        (() => {
            if (typeof window.__ytmacSetSponsorSegments === 'function') {
                window.__ytmacSetSponsorSegments("\(safeVideoID)", [\(arrayLiteral)]);
            }
        })();
        """
    }

    private static let resolveMainVideoSnippet = """
    const p = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
    const isWatchPath = location.hostname.toLowerCase() === 'tv.youtube.com'
        ? /^\\/watch\\/[^/?#]+/.test(location.pathname)
        : (location.pathname.startsWith('/watch') || /^\\/live\\/[^/?#]+/.test(location.pathname));
    const v = (p && (p.querySelector('video.html5-main-video') || p.querySelector('video')))
        || (isWatchPath ? (document.querySelector('video.html5-main-video') || document.querySelector('video')) : null);
    """

    public static let togglePlayPauseScript = """
    (() => {
        \(resolveMainVideoSnippet)
        if (!v) return false;
        if (v.paused || v.ended) {
            v.play().catch(() => {});
        } else {
            v.pause();
        }
        return true;
    })();
    """

    public static let pauseScript = """
    (() => {
        \(resolveMainVideoSnippet)
        if (v && !v.paused) {
            v.pause();
        }
    })();
    """

    public static func seekByScript(seconds: Double) -> String {
        """
        (() => {
            \(resolveMainVideoSnippet)
            if (!v) return false;
            const target = Math.max(0, (v.currentTime || 0) + (\(seconds)));
            v.currentTime = Number.isFinite(v.duration) ? Math.min(v.duration, target) : target;
            return true;
        })();
        """
    }

    /// Deterministically seeks to an absolute timestamp in seconds (clamped to `0...duration`) and emits media state.
    public static func seekToScript(seconds: Double) -> String {
        let safeSeconds = (seconds.isFinite && seconds >= 0) ? seconds : 0
        return """
        (() => {
            \(resolveMainVideoSnippet)
            if (!v || !Number.isFinite(v.duration) || v.duration <= 0) return false;
            const next = Math.max(0, Math.min(v.duration, \(safeSeconds)));
            if (p && typeof p.seekTo === 'function') {
                p.seekTo(next, true);
            } else {
                v.currentTime = next;
            }
            if (typeof window.__ytmacEmitStateNow === 'function') window.__ytmacEmitStateNow();
            return true;
        })();
        """
    }

    /// Deterministically sets the mute state of the active player/video, marking programmatic mute timing
    /// so user-unmute detection never loops, and restoring volume > 0 on unmute.
    public static func setMutedScript(muted: Bool) -> String {
        let jsMuted = muted ? "true" : "false"
        let playerCall = muted
            ? "if (p && typeof p.mute === 'function') p.mute();"
            : "if (p && typeof p.unMute === 'function') p.unMute(); if (v.volume === 0) { v.volume = 1.0; if (p && typeof p.setVolume === 'function') p.setVolume(100); }"
        return """
        (() => {
            if (typeof window.__ytmacMarkProgrammaticMute === 'function') window.__ytmacMarkProgrammaticMute();
            \(resolveMainVideoSnippet)
            if (!v) return false;
            try {
                \(playerCall)
            } catch (_) {}
            v.muted = \(jsMuted);
            if (typeof window.__ytmacEmitStateNow === 'function') window.__ytmacEmitStateNow();
            return true;
        })();
        """
    }

    /// Deterministically sets mute state and player/video volume (0–100) using strictly DRM-safe
    /// HTMLMediaElement / movie_player APIs (never WebAudio) with programmatic mute timing protection.
    public static func setAudioLevelScript(muted: Bool, volumePercent: Int) -> String {
        let clampedPercent = min(max(volumePercent, 0), 100)
        let normalizedVolume = String(format: "%.2f", Double(clampedPercent) / 100.0)
        let jsMuted = muted ? "true" : "false"
        let playerCall = muted
            ? "if (p && typeof p.setVolume === 'function') p.setVolume(\(clampedPercent)); if (p && typeof p.mute === 'function') p.mute();"
            : "if (p && typeof p.unMute === 'function') p.unMute(); if (p && typeof p.setVolume === 'function') p.setVolume(\(clampedPercent));"
        return """
        (() => {
            if (typeof window.__ytmacMarkProgrammaticMute === 'function') window.__ytmacMarkProgrammaticMute();
            \(resolveMainVideoSnippet)
            if (!v) return false;
            try {
                \(playerCall)
            } catch (_) {}
            v.volume = \(normalizedVolume);
            v.muted = \(jsMuted);
            if (typeof window.__ytmacEmitStateNow === 'function') window.__ytmacEmitStateNow();
            return true;
        })();
        """
    }

    /// Attempts clean native-resolution offscreen `<canvas>` frame capture with FairPlay DRM detection
    /// (`tv.youtube.com`, `video.mediaKeys`, and Safari `video.webkitKeys`) and CORS snapshot rect fallback.
    public static let captureVideoFrameScript = """
    (() => {
        \(resolveMainVideoSnippet)
        if (!v || v.readyState < 2 || !v.videoWidth || !v.videoHeight) {
            return { status: 'no_video' };
        }
        if (location.hostname.toLowerCase() === 'tv.youtube.com' || v.mediaKeys || v.webkitKeys) {
            return { status: 'drm' };
        }
        try {
            const canvas = document.createElement('canvas');
            canvas.width = v.videoWidth;
            canvas.height = v.videoHeight;
            const ctx = canvas.getContext('2d');
            if (!ctx) {
                return { status: 'no_video' };
            }
            ctx.drawImage(v, 0, 0, canvas.width, canvas.height);
            const dataURL = canvas.toDataURL('image/png');
            if (dataURL && dataURL.startsWith('data:image/png;base64,')) {
                return { status: 'ok', dataURL, width: canvas.width, height: canvas.height };
            }
        } catch (_) {}
        const rect = v.getBoundingClientRect();
        return {
            status: 'cors_fallback',
            x: rect.left,
            y: rect.top,
            width: rect.width,
            height: rect.height
        };
    })();
    """

    public static let toggleMuteScript = """
    (() => {
        if (typeof window.__ytmacMarkProgrammaticMute === 'function') window.__ytmacMarkProgrammaticMute();
        \(resolveMainVideoSnippet)
        if (!v) return false;
        try {
            if (p && typeof p.isMuted === 'function' && typeof p.mute === 'function' && typeof p.unMute === 'function') {
                if (p.isMuted()) {
                    p.unMute();
                    if (v.volume === 0) { v.volume = 1.0; if (typeof p.setVolume === 'function') p.setVolume(100); }
                } else {
                    p.mute();
                }
                if (typeof window.__ytmacEmitStateNow === 'function') window.__ytmacEmitStateNow();
                return true;
            }
        } catch (_) {}
        v.muted = !v.muted;
        if (!v.muted && v.volume === 0) v.volume = 1.0;
        if (typeof window.__ytmacEmitStateNow === 'function') window.__ytmacEmitStateNow();
        return true;
    })();
    """

    public static let togglePictureInPictureScript = """
    (async () => {
        \(resolveMainVideoSnippet)
        if (!v) return false;
        if (typeof v.webkitSetPresentationMode === 'function' &&
            typeof v.webkitSupportsPresentationMode === 'function' &&
            v.webkitSupportsPresentationMode('picture-in-picture')) {
            const next = v.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture';
            v.webkitSetPresentationMode(next);
            return true;
        }
        if (document.pictureInPictureElement) {
            await document.exitPictureInPicture().catch(() => {});
            return true;
        }
        if (document.pictureInPictureEnabled && typeof v.requestPictureInPicture === 'function') {
            await v.requestPictureInPicture().catch(() => {});
            return true;
        }
        return false;
    })();
    """

    public static let toggleTheaterModeScript = """
    (() => {
        const btn = document.querySelector('.ytp-size-button');
        if (!btn) return false;
        btn.click();
        return true;
    })();
    """

    public static func setPlaybackRateScript(rate: Double) -> String {
        let clamped = min(max(rate.isFinite ? rate : 1.0, 0.25), 4.0)
        return """
        (() => {
            \(resolveMainVideoSnippet)
            if (!v) return false;
            try {
                if (p && typeof p.setPlaybackRate === 'function') {
                    p.setPlaybackRate(\(clamped));
                }
            } catch (_) {}
            v.playbackRate = \(clamped);
            if (typeof window.__ytmacEmitStateNow === 'function') window.__ytmacEmitStateNow();
            return true;
        })();
        """
    }

    public static let focusYouTubeSearchScript = """
    (() => {
        const input = document.querySelector('input#search, input[name="search_query"]');
        if (input) {
            input.focus();
            input.select();
            return true;
        }
        return false;
    })();
    """

    public static let clearSelectionScript = """
    (() => {
        try {
            const sel = window.getSelection();
            if (sel && typeof sel.removeAllRanges === 'function') sel.removeAllRanges();
        } catch (_) {}
        return true;
    })();
    """

    private static func escapeJSString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    static func encodeConfigJSON(_ config: DistractionFreeConfig) -> String {
        let boolString: (Bool) -> String = { $0 ? "true" : "false" }
        let safeQuality = escapeJSString(config.preferredQuality.youtubeQualityLevel)
        let safeAppearance = escapeJSString(config.appearance.rawValue)
        let speedString = String(format: "%.2f", config.defaultPlaybackRate)
        return """
        {
          "hideShorts": \(boolString(config.hideShorts)),
          "redirectShortsToWatch": \(boolString(config.redirectShortsToWatch)),
          "cleanWebChrome": \(boolString(config.cleanWebChrome)),
          "hideWebHeader": \(boolString(config.hideWebHeader)),
          "autoTheaterMode": \(boolString(config.autoTheaterMode)),
          "hideEndScreens": \(boolString(config.hideEndScreens)),
          "hideWatchRecommendations": \(boolString(config.effectiveHideWatchRecommendations)),
          "hideComments": \(boolString(config.effectiveHideComments)),
          "hideHomeFeed": \(boolString(config.hideHomeFeed)),
          "disableAmbientMode": \(boolString(config.disableAmbientMode)),
          "autoDismissContinueWatching": \(boolString(config.autoDismissContinueWatching)),
          "preferOriginalAudio": \(boolString(config.preferOriginalAudio)),
          "preferredQuality": "\(safeQuality)",
          "defaultPlaybackRate": \(speedString),
          "sponsorBlockEnabled": \(boolString(config.sponsorBlockEnabled)),
          "appearance": "\(safeAppearance)",
          "focusModeActive": \(boolString(config.focusModeActive)),
          "miniPlayerActive": \(boolString(config.miniPlayerActive)),
          "multiviewTileActive": \(boolString(config.multiviewTileActive))
        }
        """
    }

    static let cssRules = """
    /* Subtle macOS-native web polish */
    html, body {
        -webkit-font-smoothing: antialiased;
    }

    html[data-ytmac-theme="dark"],
    html[data-ytmac-theme="dark"] body,
    html[data-ytmac-theme="dark"] ytd-app {
        color-scheme: dark;
    }

    html[data-ytmac-theme="light"],
    html[data-ytmac-theme="light"] body,
    html[data-ytmac-theme="light"] ytd-app {
        color-scheme: light;
    }

    ::-webkit-scrollbar {
        width: 8px;
        height: 8px;
    }

    ::-webkit-scrollbar-track {
        background: transparent;
    }

    ::-webkit-scrollbar-thumb {
        background: rgba(142, 142, 147, 0.35);
        border-radius: 999px;
        border: 2px solid transparent;
        background-clip: content-box;
    }

    ::-webkit-scrollbar-thumb:hover {
        background: rgba(142, 142, 147, 0.58);
        background-clip: content-box;
    }

    /* Disable heavy YouTube Ambient Mode cinematic glow canvas for crisp GPU/battery performance on macOS */
    html[data-ytmac-disable-ambient="true"] #cinematics,
    html[data-ytmac-disable-ambient="true"] #cinematics-container,
    html[data-ytmac-disable-ambient="true"] #cinematic-background,
    html[data-ytmac-disable-ambient="true"] ytd-watch-flexy #cinematics {
        display: none !important;
    }

    /* Hide Shorts via O(1) direct element & marked-container selectors */
    html[data-ytmac-hide-shorts="true"] ytd-reel-shelf-renderer,
    html[data-ytmac-hide-shorts="true"] ytd-rich-shelf-renderer[is-shorts],
    html[data-ytmac-hide-shorts="true"] ytd-mini-guide-entry-renderer[aria-label="Shorts"],
    html[data-ytmac-hide-shorts="true"] yt-tab-shape[tab-title="Shorts"],
    html[data-ytmac-hide-shorts="true"] .ytmac-shorts-hidden {
        display: none !important;
    }

    /* Prevent WebKit native drag-and-drop / text selection from interfering with YouTube & YouTube TV scrubber bars */
    #movie_player .ytp-chrome-bottom,
    #movie_player .ytp-progress-bar-container,
    #movie_player .ytp-progress-bar,
    #movie_player .ytp-scrubber-container,
    #movie_player .ytp-scrubber-button,
    .html5-video-player .ytp-chrome-bottom,
    .html5-video-player .ytp-progress-bar-container,
    .html5-video-player .ytp-progress-bar,
    .html5-video-player .ytp-scrubber-container,
    .html5-video-player .ytp-scrubber-button {
        -webkit-user-drag: none !important;
        -webkit-user-select: none !important;
        user-select: none !important;
    }

    /* Clean Web Chrome: remove redundant web left rail, non-persistent guide overlay, left masthead logo gap, voice search, and promos */
    html[data-ytmac-clean-chrome="true"] ytd-mini-guide-renderer,
    html[data-ytmac-clean-chrome="true"] #guide-button,
    html[data-ytmac-clean-chrome="true"] tp-yt-app-drawer#guide,
    html[data-ytmac-clean-chrome="true"] #masthead #start,
    html[data-ytmac-clean-chrome="true"] #country-code,
    html[data-ytmac-clean-chrome="true"] #voice-search-button,
    html[data-ytmac-clean-chrome="true"] ytd-banner-promo-renderer,
    html[data-ytmac-clean-chrome="true"] ytd-statement-banner-renderer,
    html[data-ytmac-clean-chrome="true"] yt-mealbar-promo-renderer,
    html[data-ytmac-clean-chrome="true"] ytd-brand-video-shelf-renderer,
    html[data-ytmac-clean-chrome="true"] ytd-primetime-promo-renderer {
        display: none !important;
        pointer-events: none !important;
    }

    html[data-ytmac-clean-chrome="true"] #masthead #container.ytd-masthead {
        padding-left: 18px !important;
    }

    html[data-ytmac-clean-chrome="true"] ytd-app[mini-guide-visible],
    html[data-ytmac-clean-chrome="true"] ytd-app[guide-persistent-and-visible] {
        --ytd-mini-guide-width: 0px !important;
    }

    html[data-ytmac-clean-chrome="true"] ytd-app[mini-guide-visible] #page-manager,
    html[data-ytmac-clean-chrome="true"] ytd-app[guide-persistent-and-visible] #page-manager {
        margin-left: 0 !important;
    }

    /* Hide YouTube Web Header completely when native toolbar suffices */
    html[data-ytmac-hide-header="true"] #masthead-container {
        display: none !important;
    }

    html[data-ytmac-hide-header="true"] ytd-app {
        --ytd-masthead-height: 0px !important;
    }

    html[data-ytmac-hide-header="true"] #page-manager {
        margin-top: 0 !important;
    }

    /* Hide distracting player end-screens, card teasers, and paid-content badges */
    html[data-ytmac-hide-end-screens="true"] .ytp-ce-element,
    html[data-ytmac-hide-end-screens="true"] .ytp-endscreen-content,
    html[data-ytmac-hide-end-screens="true"] .ytp-cards-teaser,
    html[data-ytmac-hide-end-screens="true"] .ytp-paid-content-overlay {
        display: none !important;
    }

    /* Hide Watch Recommendations sidebar & widen primary watch column */
    html[data-ytmac-hide-watch-recs="true"] ytd-watch-flexy #secondary,
    html[data-ytmac-hide-watch-recs="true"] ytd-watch-flexy #related {
        display: none !important;
    }

    html[data-ytmac-hide-watch-recs="true"] ytd-watch-flexy #primary {
        max-width: 1180px !important;
        margin: 0 auto !important;
    }

    /* Hide Comments */
    html[data-ytmac-hide-comments="true"] ytd-comments#comments,
    html[data-ytmac-hide-comments="true"] #comments {
        display: none !important;
    }

    /* Hide Home Feed for intentional viewing */
    html[data-ytmac-hide-home-feed="true"] ytd-browse[page-subtype="home"] ytd-rich-grid-renderer {
        display: none !important;
    }

    html[data-ytmac-hide-home-feed="true"] ytd-browse[page-subtype="home"]::after {
        content: "Distraction-Free Mode — Use Search or Subscriptions";
        display: flex;
        align-items: center;
        justify-content: center;
        min-height: 55vh;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        font-size: 16px;
        font-weight: 500;
        letter-spacing: -0.01em;
        color: rgba(142, 142, 147, 0.9);
        text-align: center;
        padding: 32px;
    }

    /*
     * Floating Mini-Player & Multiview Edge-to-Edge Tile Player (www.youtube.com ONLY):
     * ONLY promote #movie_player itself to fixed full-viewport when on a www.youtube.com watch page.
     * Never style both #player-full-bleed-container and #player-container-outer as fixed/black, because
     * the empty container in Theater Mode sits later in the DOM and paints a black curtain over the video.
     * On tv.youtube.com (data-ytmac-host="yttv"), NEVER promote .html5-video-player to fixed/high z-index
     * because YTTV renders ytu-player-controls as sibling elements outside .html5-video-player.
     */
    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"],
    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] body,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"],
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] body,
    html[data-ytmac-host="yttv"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"],
    html[data-ytmac-host="yttv"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] body {
        overflow: hidden !important;
        background: #000 !important;
    }

    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] #masthead-container,
    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] #below,
    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] #secondary,
    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] #guide,
    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] ytd-mini-guide-renderer,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #masthead-container,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #below,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #secondary,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #guide,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] ytd-mini-guide-renderer {
        display: none !important;
    }

    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] #movie_player,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #movie_player {
        position: fixed !important;
        top: 0 !important;
        left: 0 !important;
        right: 0 !important;
        bottom: 0 !important;
        width: 100vw !important;
        height: 100vh !important;
        max-width: 100vw !important;
        max-height: 100vh !important;
        margin: 0 !important;
        padding: 0 !important;
        z-index: 2147483640 !important;
        background: #000 !important;
    }

    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] #movie_player .html5-video-container,
    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] #movie_player video.html5-main-video,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #movie_player .html5-video-container,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #movie_player video.html5-main-video {
        width: 100% !important;
        height: 100% !important;
        left: 0 !important;
        top: 0 !important;
        object-fit: contain !important;
    }
    """
}
