import Foundation

/// Generates lightweight JavaScript and CSS injected into YouTube tabs for distraction-free styling,
/// playback quality-of-life enhancements, and media telemetry.
public enum EnhancementScript {
    public static let messageHandlerName = "ytmacBridge"

    /// Bootstrap script registered as a `WKUserScript` at document end.
    public static func bootstrapScript(config: DistractionFreeConfig) -> String {
        let configJSON = encodeConfigJSON(config)
        let styleText = cssRules.replacingOccurrences(of: "`", with: "\\`")
        let quotedLocales = StreamingServiceCatalog.iso639LocaleCodes.map { "\"\(escapeJSString($0))\"" }.joined(separator: ",")
        let quotedRegions = StreamingServiceCatalog.regionLocalePrefixes.map { "\"\(escapeJSString($0))\"" }.joined(separator: ",")

        return """
        (() => {
            function isYouTubeTVHost() {
                return location.hostname.toLowerCase() === 'tv.youtube.com';
            }

            function isStandardYouTubeHost() {
                return !isYouTubeTVHost() && /(^|\\.)(youtube\\.com|youtu\\.be|youtube-nocookie\\.com)$/i.test(location.hostname);
            }

            function isWebCompanionHost() {
                return !isYouTubeTVHost() && !isStandardYouTubeHost();
            }

            const ISO639_LOCALES = new Set([\(quotedLocales)]);
            const REGION_LOCALES = new Set([\(quotedRegions)]);

            function stripLeadingLocale(segs) {
                if (!segs || segs.length === 0) return segs || [];
                const first = (segs[0] || '').toLowerCase();
                if (!first) return segs;
                if (ISO639_LOCALES.has(first) || REGION_LOCALES.has(first)) {
                    return segs.slice(1);
                }
                const parts = first.split('-');
                if (parts.length === 2) {
                    const lang = parts[0];
                    const region = parts[1];
                    const validPrefix = ISO639_LOCALES.has(lang) || REGION_LOCALES.has(lang);
                    const validRegion = /^[a-z]{2}$/.test(region) || /^\\d{3}$/.test(region);
                    if (validPrefix && validRegion) {
                        return segs.slice(1);
                    }
                }
                return segs;
            }

            function isCompanionAuthPage() {
                if (!isWebCompanionHost()) return false;
                const host = location.hostname.toLowerCase();
                if (/^(sso|auth|login|signin|sign-in|passport|identity|id|ids|accounts|oauth)\\./i.test(host)) return true;
                if (/(^|\\.)(accounts\\.google\\.[a-z.]+|accounts\\.youtube\\.com|idmsa\\.apple\\.com|appleid\\.apple\\.com|registerdisney\\.go\\.com|cdn\\.registerdisney\\.go\\.com|my\\.disney\\.com|sp\\.auth\\.adobe\\.com|(na|eu|fe)\\.account\\.amazon\\.com|auth\\.hulu\\.com|auth\\.max\\.com|auth\\.hbomax\\.com|sso\\.crunchyroll\\.com|id\\.nfl\\.com|ids\\.mlb\\.com|identity\\.nba\\.com|id\\.peacocktv\\.com|identity\\.sling\\.com|passport\\.twitch\\.tv|id\\.twitch\\.tv)$/i.test(host)) return true;
                const path = location.pathname.toLowerCase();
                const normSegs = path.split('/').filter(Boolean).map((s) => s.replace(/\\.(html|htm|php|aspx)$/i, ''));
                const strippedRegion = (normSegs.length >= 2 && normSegs[0] === 'region' && /^[a-z]{2,3}$/.test(normSegs[1]))
                    ? normSegs.slice(2)
                    : normSegs;
                if (/(^|\\.)(amazon\\.[a-z.]+|primevideo\\.com)$/i.test(host)) {
                    if (strippedRegion[0] === 'ap' || strippedRegion[0] === 'ax') return true;
                    if (strippedRegion[0] === 'gp' && strippedRegion[1] === 'video' && (strippedRegion[2] === 'auth' || strippedRegion[2] === 'splash')) return true;
                    if (strippedRegion[0] === 'gp' && strippedRegion[1] === 'sign-in') return true;
                    if (strippedRegion.includes('auth-redirect')) return true;
                }
                const authTokens = new Set([
                    'signin', 'sign-in', 'sign_in', 'oauth', 'oauth2', 'authorize',
                    'servicelogin', 'auth-redirect', 'mfa', 'cvf', 'captcha',
                    'signout', 'sign-out', 'logout', 'log-out', 'register', 'reset-password'
                ]);
                for (let i = 0; i < normSegs.length; i += 1) {
                    if (authTokens.has(normSegs[i])) return true;
                    if (i + 1 < normSegs.length) {
                        const pair = normSegs[i] + '/' + normSegs[i + 1];
                        if (pair === 'oauth/callback' || pair === 'oauth2/callback' || pair === 'auth/callback' || pair === 'sso/callback' || pair === 'auth/return') {
                            return true;
                        }
                    }
                }
                const afterLocale = stripLeadingLocale(normSegs);
                if (afterLocale[0] === 'login') return true;
                if (afterLocale.length >= 2 && ['web', 'account', 'accounts', 'auth', 'sso', 'user', 'identity'].includes(afterLocale[0]) && afterLocale[1] === 'login') return true;
                if ((host === 'disneyplus.com' || host.endsWith('.disneyplus.com')) && afterLocale[0] === 'identity') return true;
                if ((host === 'hbomax.com' || host.endsWith('.hbomax.com') || host === 'max.com' || host.endsWith('.max.com')) && afterLocale[0] === 'auth') return true;
                const query = (location.search || '').toLowerCase();
                if (query && (query.includes('servicelogin') || query.includes('openid.mode=checkid_setup') || query.includes('openid.mode=checkid_immediate') || (query.includes('oauth') && query.includes('client_id=')))) {
                    return true;
                }
                return false;
            }
            if (isCompanionAuthPage()) return;
            if (window.__ytmacInitialized) {
                window.__ytmacConfig = \(configJSON);
                if (typeof window.__ytmacApplyConfigOnly === 'function') window.__ytmacApplyConfigOnly();
                if (typeof window.__ytmacHandleRouteChange === 'function') window.__ytmacHandleRouteChange();
                return;
            }

            const initialConfig = \(configJSON);
            window.__ytmacConfig = initialConfig;

            const styleText = `\(styleText)`;
            const cleanBoxStyleText = `\(cleanBoxCSSRules.replacingOccurrences(of: "`", with: "\\`"))`;
            const CLEANBOX_PLAYER_SELECTORS = \(encodeCleanBoxProfilesJSON());
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
                if (isWebCompanionHost() || !document.head || document.getElementById('ytmac-style')) return;
                const styleEl = document.createElement('style');
                styleEl.id = 'ytmac-style';
                styleEl.textContent = styleText;
                document.head.appendChild(styleEl);
            }

            function ensureCleanBoxStyleElement() {
                if (!isWebCompanionHost() || isCompanionAuthPage() || !document.head || document.getElementById('ytmac-cleanbox-style')) return;
                const styleEl = document.createElement('style');
                styleEl.id = 'ytmac-cleanbox-style';
                styleEl.textContent = cleanBoxStyleText;
                document.head.appendChild(styleEl);
            }

            let activeCleanBoxState = { root: null, iframe: null, video: null, mediaAnchor: null, chain: [], ancestors: [] };
            let lastCleanBoxEligible = false;
            let lastCleanBoxActive = false;
            let cleanBoxBlockedByModal = false;
            let cleanBoxSettleTimers = [];
            let cleanBoxCloseTimer1 = null;
            let cleanBoxCloseTimer2 = null;

            function clearCleanBoxSettleTimers() {
                for (let i = 0; i < cleanBoxSettleTimers.length; i += 1) {
                    clearTimeout(cleanBoxSettleTimers[i]);
                }
                cleanBoxSettleTimers = [];
            }

            function clearCleanBoxCloseTimers() {
                if (cleanBoxCloseTimer1) { clearTimeout(cleanBoxCloseTimer1); cleanBoxCloseTimer1 = null; }
                if (cleanBoxCloseTimer2) { clearTimeout(cleanBoxCloseTimer2); cleanBoxCloseTimer2 = null; }
            }

            function stripCleanBoxAttributes() {
                const tagged = document.querySelectorAll('[data-ytmac-cb]');
                for (let i = 0; i < tagged.length; i += 1) {
                    tagged[i].removeAttribute('data-ytmac-cb');
                }
                activeCleanBoxState = { root: null, iframe: null, video: null, mediaAnchor: null, chain: [], ancestors: [] };
            }

            function isCleanBoxStateIntact() {
                if (!activeCleanBoxState.root || !activeCleanBoxState.root.isConnected) return false;
                if (activeCleanBoxState.root.getAttribute('data-ytmac-cb') !== 'player') return false;
                if (activeCleanBoxState.iframe && activeCleanBoxState.iframe !== activeCleanBoxState.root) {
                    if (!activeCleanBoxState.iframe.isConnected || activeCleanBoxState.iframe.getAttribute('data-ytmac-cb') !== 'iframe') return false;
                }
                if (activeCleanBoxState.video && activeCleanBoxState.video !== activeCleanBoxState.root) {
                    if (!activeCleanBoxState.video.isConnected || activeCleanBoxState.video.getAttribute('data-ytmac-cb') !== 'video') return false;
                }
                for (let i = 0; i < activeCleanBoxState.chain.length; i += 1) {
                    const el = activeCleanBoxState.chain[i];
                    if (!el || !el.isConnected || el.getAttribute('data-ytmac-cb') !== 'chain') return false;
                }
                for (let i = 0; i < activeCleanBoxState.ancestors.length; i += 1) {
                    const el = activeCleanBoxState.ancestors[i];
                    if (!el || !el.isConnected || el.getAttribute('data-ytmac-cb') !== 'ancestor') return false;
                }
                return true;
            }

            function releaseCompanionCleanBox(stripStyle, suppressResize) {
                if (document.fullscreenElement || document.webkitFullscreenElement) return false;
                const rootEl = document.documentElement;
                const wasActive = Boolean(rootEl && rootEl.dataset.ytmacCleanBox === 'true');
                stripCleanBoxAttributes();
                if (rootEl) {
                    if (stripStyle) {
                        delete rootEl.dataset.ytmacCleanBox;
                    } else {
                        setDatasetFlag(rootEl, 'ytmacCleanBox', false);
                    }
                }
                if (stripStyle) {
                    const styleEl = document.getElementById('ytmac-cleanbox-style');
                    if (styleEl) styleEl.remove();
                }
                lastCleanBoxActive = false;
                if (wasActive && !suppressResize) {
                    requestAnimationFrame(() => window.dispatchEvent(new Event('resize')));
                }
                return wasActive;
            }

            function isCleanBoxWatchPage() {
                if (!isWebCompanionHost() || isCompanionAuthPage()) return false;
                const host = location.hostname.toLowerCase();
                const path = location.pathname.toLowerCase();
                const normSegs = path.split('/').filter(Boolean).map((s) => s.replace(/\\.(html|htm|php|aspx)$/i, ''));

                if (host === 'clips.twitch.tv') {
                    return normSegs.length >= 1 ? { serviceID: 'twitch', type: 'watch' } : { serviceID: 'twitch', type: 'browse' };
                }
                if (host === 'twitch.tv' || host.endsWith('.twitch.tv')) {
                    const reserved = new Set([
                        'directory', 'browse', 'following', 'search', 'settings', 'subscriptions',
                        'inventory', 'drops', 'wallet', 'turbo', 'downloads', 'jobs', 'p',
                        'login', 'signup', 'activate', 'videos', 'popout', 'moderator',
                        'u', 'team', 'store', 'prime', 'bits', 'friends', 'messages',
                        'payments', 'security', 'privacy', 'terms', 'products', 'broadcast',
                        'creatorcamp', 'redeem', 'gift', 'clip', 'clips'
                    ]);
                    if (normSegs.length >= 2 && normSegs[0] === 'videos') return { serviceID: 'twitch', type: 'watch' };
                    if (normSegs.length >= 3 && normSegs[1] === 'clip') return { serviceID: 'twitch', type: 'watch' };
                    if (normSegs.length === 1 && !reserved.has(normSegs[0])) return { serviceID: 'twitch', type: 'watch' };
                    return { serviceID: 'twitch', type: 'browse' };
                }
                if (host === 'crunchyroll.com' || host.endsWith('.crunchyroll.com')) {
                    const afterLoc = stripLeadingLocale(normSegs);
                    return (afterLoc.length >= 2 && afterLoc[0] === 'watch')
                        ? { serviceID: 'crunchyroll', type: 'watch' }
                        : { serviceID: 'crunchyroll', type: 'browse' };
                }
                if (host === 'primevideo.com' || host.endsWith('.primevideo.com') || /(^|\\.)amazon\\.[a-z.]+$/i.test(host)) {
                    return { serviceID: 'primevideo', type: 'overlaySDK' };
                }
                if (host === 'tv.apple.com') {
                    return { serviceID: 'appletv', type: 'overlaySDK' };
                }
                if (host === 'espn.com' || host.endsWith('.espn.com') || host === 'espn.go.com' || host.endsWith('.espn.go.com')) {
                    return (path.startsWith('/watch/player') || path.startsWith('/espnplus/player') || path.startsWith('/video/clip'))
                        ? { serviceID: 'espn', type: 'watch' }
                        : { serviceID: 'espn', type: 'browse' };
                }
                if (host === 'nfl.com' || host.endsWith('.nfl.com')) {
                    const ok = path.startsWith('/plus/games/') || path.startsWith('/plus/live/') || path.startsWith('/plus/episodes/') || path.startsWith('/plus/replays/') || path.startsWith('/network/watch/');
                    return { serviceID: 'nfl', type: ok ? 'watch' : 'browse' };
                }
                if (host === 'mlb.com' || host.endsWith('.mlb.com')) {
                    const ok = (normSegs.length >= 2 && normSegs[0] === 'tv' && (normSegs[1].startsWith('g') || normSegs[1].startsWith('c')))
                        || path.startsWith('/live-stream-games/') || path.startsWith('/video/');
                    return { serviceID: 'mlb', type: ok ? 'watch' : 'browse' };
                }
                if (host === 'nba.com' || host.endsWith('.nba.com')) {
                    const ok = path.startsWith('/watch/event/') || path.startsWith('/watch/video/') || path.startsWith('/watch/league-pass');
                    return { serviceID: 'nba', type: ok ? 'watch' : 'browse' };
                }
                if (host === 'peacocktv.com' || host.endsWith('.peacocktv.com')) {
                    const ok = path.startsWith('/watch/playback') || path.startsWith('/watch/asset');
                    return { serviceID: 'peacock', type: ok ? 'watch' : 'browse' };
                }
                if (host === 'paramountplus.com' || host.endsWith('.paramountplus.com')) {
                    const ok = (normSegs.length >= 3 && normSegs[0] === 'shows' && normSegs[2] === 'video')
                        || (normSegs.length >= 2 && normSegs[0] === 'movies' && normSegs[1] === 'video')
                        || path.startsWith('/video/') || normSegs[0] === 'live-tv';
                    return { serviceID: 'paramount', type: ok ? 'watch' : 'browse' };
                }
                if (host === 'fubo.tv' || host.endsWith('.fubo.tv')) {
                    const ok = path.startsWith('/p/watch') || path.startsWith('/p/live') || path.startsWith('/p/dvr/');
                    return { serviceID: 'fubo', type: ok ? 'watch' : 'browse' };
                }
                if (host === 'sling.com' || host.endsWith('.sling.com')) {
                    const ok = path.startsWith('/1/program/') || path.startsWith('/1/channel/') || path.startsWith('/1/asset/') || path.startsWith('/1/franchise/') || normSegs.includes('watch');
                    return { serviceID: 'sling', type: ok ? 'watch' : 'browse' };
                }
                if (host === 'disneyplus.com' || host.endsWith('.disneyplus.com')) {
                    const afterLoc = stripLeadingLocale(normSegs);
                    const ok = afterLoc.length >= 2 && (afterLoc[0] === 'play' || afterLoc[0] === 'video');
                    return { serviceID: 'disneyplus', type: ok ? 'watch' : 'browse' };
                }
                if (host === 'hulu.com' || host.endsWith('.hulu.com')) {
                    return { serviceID: 'hulu', type: path.startsWith('/watch/') ? 'watch' : 'browse' };
                }
                if (host === 'play.max.com' || host === 'max.com' || host.endsWith('.max.com') || host === 'hbomax.com' || host.endsWith('.hbomax.com')) {
                    const afterLoc = stripLeadingLocale(normSegs);
                    const ok = (afterLoc.length >= 2 && afterLoc[0] === 'video' && afterLoc[1] === 'watch') || afterLoc[0] === 'player';
                    return { serviceID: 'max', type: ok ? 'watch' : 'browse' };
                }
                if (host === 'netflix.com' || host.endsWith('.netflix.com')) {
                    const afterLoc = stripLeadingLocale(normSegs);
                    const ok = afterLoc.length >= 2 && afterLoc[0] === 'watch';
                    return { serviceID: 'netflix', type: ok ? 'watch' : 'browse' };
                }
                return { serviceID: '_generic', type: 'generic' };
            }

            function climbLightHost(node) {
                let cur = node;
                let guard = 0;
                while (cur && guard < 12) {
                    guard += 1;
                    const rn = typeof cur.getRootNode === 'function' ? cur.getRootNode() : null;
                    if (rn && rn.host) {
                        cur = rn.host;
                    } else {
                        break;
                    }
                }
                return cur;
            }

            function hasMediaSource(v) {
                return Boolean(v && (v.src || v.currentSrc || v.srcObject || v.readyState > 0 || (v.querySelector && v.querySelector('source[src]'))));
            }

            function isAmbientTrailerVideo(v) {
                if (!v) return true;
                if (v.loop && v.muted && (!Number.isFinite(v.duration) || v.duration <= 180)) return true;
                if (v.getAttribute && v.getAttribute('aria-hidden') === 'true' && (v.muted || v.loop) && (!Number.isFinite(v.duration) || v.duration <= 180)) return true;
                return false;
            }

            function hasHiddenAncestor(el, isAlreadyActive) {
                try {
                    let cur = el;
                    let guard = 0;
                    while (cur && cur !== document.body && cur !== document.documentElement && guard < 40) {
                        guard += 1;
                        if (isAlreadyActive) {
                            const s = cur.style;
                            if (s && (s.display === 'none' || s.visibility === 'hidden' || s.opacity === '0')) return true;
                            const cs = getComputedStyle(cur);
                            if (cs.display === 'none' || cs.visibility === 'hidden') return true;
                        } else {
                            const s = cur.style;
                            if (s && (s.display === 'none' || s.visibility === 'hidden' || s.opacity === '0')) return true;
                            const cs = getComputedStyle(cur);
                            if (cs.display === 'none' || cs.visibility === 'hidden' || parseFloat(cs.opacity || '1') <= 0.05) return true;
                        }
                        cur = cur.parentElement;
                    }
                } catch (_) {}
                return false;
            }

            function hasVisibleExternalModal(playerRoot) {
                try {
                    const vw = window.innerWidth || 0;
                    const vh = window.innerHeight || 0;
                    const dialogs = document.querySelectorAll('[role="dialog"], [aria-modal="true"]');
                    for (let i = 0; i < dialogs.length; i += 1) {
                        const d = dialogs[i];
                        if (!d || !d.isConnected) continue;
                        if (playerRoot && (playerRoot.contains(d) || d.contains(playerRoot))) continue;
                        if (typeof d.closest === 'function' && d.closest('[aria-hidden="true"], [inert]')) continue;
                        const cs = getComputedStyle(d);
                        if (cs.display === 'none' || cs.visibility === 'hidden' || parseFloat(cs.opacity || '1') <= 0.05 || cs.pointerEvents === 'none') continue;
                        const isAriaModal = d.getAttribute('aria-modal') === 'true';
                        if (!isAriaModal) {
                            const idLower = (d.id || '').toLowerCase();
                            const clsLower = typeof d.className === 'string' ? d.className.toLowerCase() : '';
                            if (idLower.includes('onetrust') || clsLower.includes('onetrust') || clsLower.includes('toast') || d.getAttribute('role') === 'status') {
                                continue;
                            }
                        }
                        const r = d.getBoundingClientRect();
                        const visW = Math.min(r.right, vw) - Math.max(r.left, 0);
                        const visH = Math.min(r.bottom, vh) - Math.max(r.top, 0);
                        if (visW < 200 || visH < 120) continue;
                        if (isAriaModal) return true;
                        if (d.tagName === 'DIALOG' && d.open) return true;
                        if (cs.position === 'fixed') {
                            const spansCenter = r.left < vw * 0.5 && r.right > vw * 0.5 && r.top < vh * 0.5 && r.bottom > vh * 0.5;
                            if (spansCenter || (visW >= vw * 0.25 && visH >= vh * 0.25)) {
                                return true;
                            }
                        }
                    }
                } catch (_) {}
                return false;
            }

            function resolveGenericPlayerBox(lightVideo) {
                if (!lightVideo || !lightVideo.getBoundingClientRect) return null;
                const baseRect = lightVideo.getBoundingClientRect();
                if (baseRect.width < 120 || baseRect.height < 68) return lightVideo;
                let best = lightVideo;
                let cur = lightVideo.parentElement;
                for (let depth = 0; cur && depth < 10; depth += 1, cur = cur.parentElement) {
                    const tag = (cur.tagName || '').toLowerCase();
                    if (tag === 'body' || tag === 'html' || tag === 'main') break;
                    if (cur.id === 'root' || cur.id === 'app' || cur.id === '__next') break;
                    if (cur.querySelector && cur.querySelector('nav, header[role="banner"], footer, h1, article, [data-a-target="chat-scroller"]')) break;
                    if (cur.querySelectorAll && cur.querySelectorAll('a[href]').length > 16) break;
                    const r = cur.getBoundingClientRect();
                    if (r.width <= baseRect.width * 1.18 + 24 && r.height <= baseRect.height * 1.25 + 80) {
                        best = cur;
                    } else {
                        break;
                    }
                }
                return best;
            }

            const CLEANBOX_AD_HOST_SUFFIXES = [
                'doubleclick.net',
                'googlesyndication.com',
                'imasdk.googleapis.com',
                'adservice.google.com',
                'amazon-adsystem.com',
                'scorecardresearch.com',
                'moatads.com'
            ];

            function isDisallowedPlayerIframeHost(h) {
                if (!h) return true;
                if (/^(sso|auth|login|signin|sign-in|passport|identity|id|ids|accounts|oauth)\\./i.test(h)) return true;
                if (/(^|\\.)(accounts\\.google\\.[a-z.]+|accounts\\.youtube\\.com|idmsa\\.apple\\.com|appleid\\.apple\\.com|registerdisney\\.go\\.com|cdn\\.registerdisney\\.go\\.com|my\\.disney\\.com|sp\\.auth\\.adobe\\.com|(na|eu|fe)\\.account\\.amazon\\.com|auth\\.hulu\\.com|auth\\.max\\.com|auth\\.hbomax\\.com|sso\\.crunchyroll\\.com|id\\.nfl\\.com|ids\\.mlb\\.com|identity\\.nba\\.com|id\\.peacocktv\\.com|identity\\.sling\\.com|passport\\.twitch\\.tv|id\\.twitch\\.tv)$/i.test(h)) return true;
                if (CLEANBOX_AD_HOST_SUFFIXES.some((s) => h === s || h.endsWith('.' + s))) return true;
                return false;
            }

            function collectCleanBoxIframes(root, depth) {
                const out = [];
                if (!root || depth > 3) return out;
                const seenShadow = new Set();
                const pushHost = (host) => {
                    if (!host || !host.shadowRoot || seenShadow.has(host)) return;
                    seenShadow.add(host);
                    const sub = collectCleanBoxIframes(host.shadowRoot, depth + 1);
                    for (let i = 0; i < sub.length; i += 1) out.push(sub[i]);
                };
                try {
                    const direct = root.querySelectorAll ? root.querySelectorAll('iframe') : [];
                    for (let i = 0; i < direct.length; i += 1) out.push(direct[i]);
                    if (depth < 3 && root.querySelectorAll) {
                        const els = root.querySelectorAll('*');
                        const cap = Math.min(els.length, 400);
                        for (let i = 0; i < cap; i += 1) pushHost(els[i]);
                    }
                } catch (_) {}
                return out;
            }

            function resolveIframeCandidate(profile, isCompactSurface, wasCleanBox) {
                if (!profile || !Array.isArray(profile.allowedIframeHostSuffixes) || profile.allowedIframeHostSuffixes.length === 0) {
                    return null;
                }
                const selectors = Array.isArray(profile.iframeSelectors) ? profile.iframeSelectors : [];
                if (profile.strategy !== 'companionIframe' && selectors.length === 0) {
                    return null;
                }
                const allowedSuffixes = profile.allowedIframeHostSuffixes;
                const playerSelJoined = Array.isArray(profile.playerSelectors) ? profile.playerSelectors.join(',') : '';
                const minW = isCompactSurface ? 100 : 200;
                const minH = isCompactSurface ? 56 : 112;

                const evaluateFrame = (frame, allowBlankSubframe) => {
                    if (!frame || !frame.isConnected || frame.hasAttribute('srcdoc')) return null;
                    const already = wasCleanBox && activeCleanBoxState.iframe === frame;
                    if (hasHiddenAncestor(frame, already)) return null;
                    const r = frame.getBoundingClientRect();
                    if (!already && (r.width < minW || r.height < minH)) return null;

                    const rawSrc = (frame.getAttribute('src') || '').trim();
                    const lowerSrc = rawSrc.toLowerCase();
                    if (lowerSrc.startsWith('javascript:') || lowerSrc.startsWith('data:') || lowerSrc.startsWith('blob:')) {
                        return null;
                    }
                    const isBlank = rawSrc === '' || lowerSrc === 'about:blank' || lowerSrc.startsWith('about:blank?') || lowerSrc.startsWith('about:blank#');
                    if (isBlank) {
                        if (!allowBlankSubframe || window.__ytmacSubframeMediaActive !== true) return null;
                        const matchesExplicitSelector = selectors.some((s) => {
                            try { return typeof frame.matches === 'function' && frame.matches(s); } catch (_) { return false; }
                        });
                        const insidePlayer = Boolean(playerSelJoined && typeof frame.closest === 'function' && frame.closest(playerSelJoined));
                        if (!matchesExplicitSelector && !insidePlayer) return null;
                    } else {
                        try {
                            const u = new URL(rawSrc, location.href);
                            if (u.protocol !== 'https:') return null;
                            const h = (u.hostname || '').toLowerCase();
                            if (isDisallowedPlayerIframeHost(h)) return null;
                            if (!allowedSuffixes.some((s) => h === s || h.endsWith('.' + s))) return null;
                        } catch (_) {
                            return null;
                        }
                    }

                    const area = Math.max(0, r.width) * Math.max(0, r.height);
                    const inLightDOM = typeof frame.getRootNode === 'function' && frame.getRootNode() === document;
                    if (inLightDOM) {
                        return { root: frame, iframe: frame, video: null, mediaAnchor: frame, area };
                    }
                    const hostEl = climbLightHost(frame);
                    if (!hostEl || !hostEl.isConnected || hasHiddenAncestor(hostEl, wasCleanBox && activeCleanBoxState.root === hostEl)) {
                        return null;
                    }
                    return { root: hostEl, iframe: null, video: null, mediaAnchor: hostEl, area };
                };

                const pickLargest = (frames, allowBlankSubframe) => {
                    let best = null;
                    for (let i = 0; i < frames.length; i += 1) {
                        const cand = evaluateFrame(frames[i], allowBlankSubframe);
                        if (cand && (!best || cand.area > best.area)) {
                            best = cand;
                        }
                    }
                    return best;
                };

                const tier1Frames = [];
                for (let i = 0; i < selectors.length; i += 1) {
                    const list = document.querySelectorAll(selectors[i]);
                    for (let j = 0; j < list.length; j += 1) tier1Frames.push(list[j]);
                }
                const allFrames = collectCleanBoxIframes(document, 0);

                // Always prioritize explicit HTTPS allowlisted player iframes before any blank/about:blank fallback.
                return pickLargest(tier1Frames, false)
                    || pickLargest(allFrames, false)
                    || pickLargest(tier1Frames, true)
                    || pickLargest(allFrames, true);
            }

            function resolveInlineVideoCandidate(profile, route, isCompactSurface, wasCleanBox) {
                const video = findPrimaryWebVideo();
                if (!video || !video.isConnected || !hasMediaSource(video) || isAmbientTrailerVideo(video)) return null;
                const lightEl = climbLightHost(video);
                if (!lightEl || !lightEl.isConnected) return null;
                if (typeof lightEl.closest === 'function' && lightEl.closest('[data-a-target="front-page-carousel"], .persistent-player')) {
                    return null;
                }
                const vRect = lightEl.getBoundingClientRect();
                const minW = isCompactSurface ? 100 : 180;
                const minH = isCompactSurface ? 56 : 100;
                const reqW = route.serviceID === '_generic' ? (isCompactSurface ? 100 : 320) : minW;
                const reqH = route.serviceID === '_generic' ? (isCompactSurface ? 56 : 180) : minH;
                if (!(wasCleanBox && video.readyState > 0) && (vRect.width < reqW || vRect.height < reqH)) {
                    return null;
                }
                if (route.serviceID === '_generic' && video.readyState < 2) {
                    return null;
                }

                let resolvedRoot = null;
                if (profile && Array.isArray(profile.playerSelectors)) {
                    for (let i = 0; i < profile.playerSelectors.length; i += 1) {
                        const sel = profile.playerSelectors[i];
                        const cand = (typeof lightEl.closest === 'function') ? lightEl.closest(sel) : null;
                        if (!cand || cand === document.body || cand === document.documentElement) continue;
                        if (cand.id === 'root' || cand.id === 'app' || cand.id === '__next') continue;
                        if (cand.querySelector && cand.querySelector('nav, header[role="banner"], footer, [data-a-target="chat-scroller"]')) continue;
                        if (cand.querySelectorAll && cand.querySelectorAll('a[href]').length > 16) continue;
                        if (route.type === 'watch' && !(wasCleanBox && cand === activeCleanBoxState.root)) {
                            const candRect = cand.getBoundingClientRect();
                            if (candRect.height > vRect.height * 1.45 + 140) {
                                const topPad = vRect.top - candRect.top;
                                const bottomPad = candRect.bottom - vRect.bottom;
                                const tooTall = candRect.height > (window.innerHeight || 0) * 1.1;
                                const asymmetricBelow = bottomPad > topPad + 120;
                                const hasDocChrome = Boolean(cand.querySelector && cand.querySelector('h1, article, footer'));
                                if (tooTall || asymmetricBelow || hasDocChrome) {
                                    continue;
                                }
                            }
                        }
                        resolvedRoot = cand;
                        break;
                    }
                }

                if (route.type === 'overlaySDK') {
                    if (!resolvedRoot) return null;
                    const already = wasCleanBox && activeCleanBoxState.root === resolvedRoot && video.readyState > 0;
                    if (hasHiddenAncestor(resolvedRoot, already)) return null;
                    const r = resolvedRoot.getBoundingClientRect();
                    if (!already && (r.width < reqW || r.height < reqH)) return null;
                } else {
                    if (!resolvedRoot) {
                        resolvedRoot = resolveGenericPlayerBox(lightEl);
                    }
                    if (!resolvedRoot) return null;
                    const already = wasCleanBox && activeCleanBoxState.root === resolvedRoot && video.readyState > 0;
                    if (hasHiddenAncestor(resolvedRoot, already)) return null;
                }

                const lightVideo = (video.getRootNode && video.getRootNode() === document) ? video : null;
                const area = Math.max(0, vRect.width) * Math.max(0, vRect.height);
                return {
                    root: resolvedRoot,
                    iframe: null,
                    video: lightVideo,
                    mediaAnchor: lightEl,
                    area,
                    videoObj: video
                };
            }

            function evaluateCompanionCleanBoxCandidate(cfg) {
                cleanBoxBlockedByModal = false;
                const none = { eligible: false, activate: false, root: null, iframe: null, video: null, mediaAnchor: null };
                if (!isWebCompanionHost() || isCompanionAuthPage()) return none;
                const route = isCleanBoxWatchPage();
                if (!route || route.type === 'browse') return none;

                const isCompactSurface = Boolean(cfg && (cfg.miniPlayerActive || cfg.multiviewTileActive));
                const profile = CLEANBOX_PLAYER_SELECTORS[route.serviceID] || null;
                if (profile && profile.strategy === 'companionPassthrough') return none;
                const isCatalog = route.serviceID !== '_generic';
                const wasCleanBox = document.documentElement.dataset.ytmacCleanBox === 'true';

                if (route.serviceID === '_generic') {
                    if (!(cfg && (cfg.miniPlayerActive || cfg.multiviewTileActive || cfg.focusModeActive))) {
                        return none;
                    }
                }

                let chosen = null;
                if (route.type === 'overlaySDK' || route.serviceID === '_generic') {
                    chosen = resolveInlineVideoCandidate(profile, route, isCompactSurface, wasCleanBox);
                } else if (profile && profile.strategy === 'companionIframe') {
                    const inlineCand = resolveInlineVideoCandidate(profile, route, isCompactSurface, wasCleanBox);
                    const iframeCand = resolveIframeCandidate(profile, isCompactSurface, wasCleanBox);
                    if (inlineCand && iframeCand) {
                        const v = inlineCand.videoObj;
                        const inlineActive = Boolean(v && ((!v.paused && !v.ended) || (v.readyState >= 1 && inlineCand.area >= iframeCand.area)));
                        chosen = inlineActive ? inlineCand : iframeCand;
                    } else {
                        chosen = inlineCand || iframeCand;
                    }
                } else {
                    chosen = resolveInlineVideoCandidate(profile, route, isCompactSurface, wasCleanBox);
                    if (!chosen && profile && Array.isArray(profile.iframeSelectors) && profile.iframeSelectors.length > 0) {
                        chosen = resolveIframeCandidate(profile, isCompactSurface, wasCleanBox);
                    }
                }

                if (!chosen || !chosen.root) return none;

                if (hasVisibleExternalModal(chosen.root)) {
                    cleanBoxBlockedByModal = true;
                    return none;
                }

                const wantBySurface = Boolean(cfg && (cfg.miniPlayerActive || cfg.multiviewTileActive || cfg.focusModeActive || (isCatalog && cfg.cleanWebChrome)));
                const activate = wantBySurface && Boolean(cfg && cfg.cleanBoxStreamingPlayers) && !Boolean(cfg && cfg.cleanBoxBypassed);
                return {
                    eligible: true,
                    activate,
                    root: chosen.root,
                    iframe: chosen.iframe,
                    video: chosen.video,
                    mediaAnchor: chosen.mediaAnchor
                };
            }

            function syncCompanionCleanBox(reason) {
                if (!isWebCompanionHost()) {
                    lastCleanBoxEligible = false;
                    cleanBoxBlockedByModal = false;
                    return false;
                }
                if (isCompanionAuthPage()) {
                    lastCleanBoxEligible = false;
                    cleanBoxBlockedByModal = false;
                    clearCleanBoxSettleTimers();
                    const changed = releaseCompanionCleanBox(true, true);
                    if (changed) emitMediaState(true);
                    return false;
                }
                if (document.fullscreenElement || document.webkitFullscreenElement) {
                    return lastCleanBoxActive;
                }

                const cfg = window.__ytmacConfig || initialConfig;
                const cand = evaluateCompanionCleanBoxCandidate(cfg);
                lastCleanBoxEligible = cand.eligible;

                const rootEl = document.documentElement;
                if (!cand.activate || !cand.root) {
                    const wasActive = releaseCompanionCleanBox(false, true);
                    if (wasActive) {
                        requestAnimationFrame(() => window.dispatchEvent(new Event('resize')));
                        if (reason !== 'configOnly') emitMediaState(true);
                    }
                    if (reason === 'subframe' && cfg.cleanBoxStreamingPlayers && !cfg.cleanBoxBypassed) {
                        scheduleCleanBoxSettleTimers();
                    }
                    return false;
                }

                ensureCleanBoxStyleElement();
                const targetChanged = activeCleanBoxState.root !== cand.root
                    || activeCleanBoxState.iframe !== cand.iframe
                    || activeCleanBoxState.video !== cand.video
                    || activeCleanBoxState.mediaAnchor !== cand.mediaAnchor;
                const wasActive = Boolean(rootEl && rootEl.dataset.ytmacCleanBox === 'true');
                const needsRepair = !wasActive || targetChanged || !isCleanBoxStateIntact();

                if (needsRepair) {
                    stripCleanBoxAttributes();
                    cand.root.setAttribute('data-ytmac-cb', 'player');
                    if (cand.iframe && cand.iframe !== cand.root) {
                        cand.iframe.setAttribute('data-ytmac-cb', 'iframe');
                    }
                    if (cand.video && cand.video !== cand.root) {
                        cand.video.setAttribute('data-ytmac-cb', 'video');
                    }

                    const chain = [];
                    if (cand.mediaAnchor && cand.mediaAnchor !== cand.root && cand.mediaAnchor !== cand.video && cand.mediaAnchor !== cand.iframe) {
                        cand.mediaAnchor.setAttribute('data-ytmac-cb', 'chain');
                        chain.push(cand.mediaAnchor);
                    }
                    let chainCur = cand.mediaAnchor ? cand.mediaAnchor.parentElement : null;
                    while (chainCur && chainCur !== cand.root && chainCur !== document.body && chainCur !== document.documentElement && chain.length < 24) {
                        chainCur.setAttribute('data-ytmac-cb', 'chain');
                        chain.push(chainCur);
                        chainCur = chainCur.parentElement;
                    }

                    const ancestors = [];
                    let cur = cand.root.parentElement;
                    while (cur && cur !== document.body && cur !== document.documentElement) {
                        cur.setAttribute('data-ytmac-cb', 'ancestor');
                        ancestors.push(cur);
                        cur = cur.parentElement;
                    }
                    activeCleanBoxState = {
                        root: cand.root,
                        iframe: cand.iframe,
                        video: cand.video,
                        mediaAnchor: cand.mediaAnchor,
                        chain,
                        ancestors
                    };
                }

                if (rootEl) {
                    setDatasetFlag(rootEl, 'ytmacCleanBox', true);
                }
                lastCleanBoxActive = true;
                clearCleanBoxSettleTimers();

                if (!wasActive || targetChanged) {
                    requestAnimationFrame(() => window.dispatchEvent(new Event('resize')));
                    if (reason !== 'configOnly') emitMediaState(true);
                }
                return true;
            }

            window.__ytmacSyncCleanBox = (reason) => syncCompanionCleanBox(reason || 'manual');

            function scheduleCleanBoxSettleTimers() {
                if (!isWebCompanionHost() || isCompanionAuthPage()) return;
                const route = isCleanBoxWatchPage();
                if (!route || route.type === 'browse') return;
                const profile = CLEANBOX_PLAYER_SELECTORS[route.serviceID] || null;
                if (profile && profile.strategy === 'companionPassthrough') return;
                const cfg = window.__ytmacConfig || initialConfig;
                if (!cfg || !cfg.cleanBoxStreamingPlayers || cfg.cleanBoxBypassed) return;
                clearCleanBoxSettleTimers();
                const delays = [650, 1500, 3000, 5500];
                for (let i = 0; i < delays.length; i += 1) {
                    const ms = delays[i];
                    const id = setTimeout(() => {
                        if (lastCleanBoxActive) {
                            clearCleanBoxSettleTimers();
                            return;
                        }
                        syncCompanionCleanBox('settle' + ms);
                    }, ms);
                    cleanBoxSettleTimers.push(id);
                }
            }

            function setDatasetFlag(root, key, enabled) {
                const value = enabled ? 'true' : 'false';
                if (root.dataset[key] !== value) {
                    root.dataset[key] = value;
                }
            }

            function isWatchPage() {
                if (isYouTubeTVHost()) {
                    // YouTube TV uses path-based /watch/<id>; /live is the Live EPG Guide (not a watch page).
                    return /^\\/watch\\/[^/?#]+/.test(location.pathname);
                }
                if (isWebCompanionHost()) {
                    return false;
                }
                return location.pathname.startsWith('/watch') || /^\\/live\\/[^/?#]+/.test(location.pathname);
            }

            function getPlayer() {
                if (isWebCompanionHost()) return null;
                return document.getElementById('movie_player') || document.querySelector('.html5-video-player');
            }

            function isWatchPageWithPlayer() {
                return isWatchPage() && Boolean(getPlayer() || document.querySelector('video.html5-main-video'));
            }

            function collectVideos(root, depth) {
                const results = [];
                if (!root || depth > 4) return results;
                const visitedShadow = new Set();
                const pushNested = (host) => {
                    if (!host || !host.shadowRoot || visitedShadow.has(host)) return;
                    visitedShadow.add(host);
                    const nested = collectVideos(host.shadowRoot, depth + 1);
                    for (let j = 0; j < nested.length; j += 1) {
                        results.push(nested[j]);
                    }
                };
                try {
                    const direct = root.querySelectorAll ? root.querySelectorAll('video') : [];
                    for (let i = 0; i < direct.length; i += 1) {
                        results.push(direct[i]);
                    }
                    if (depth < 4 && root.querySelectorAll) {
                        const priorityHosts = root.querySelectorAll('apple-tv-plus-player, amp-chrome-player, amp-video-player, amp-video-player-internal, disney-web-player, btm-media-client-element, video-js, media-controller, shaka-player');
                        for (let i = 0; i < priorityHosts.length; i += 1) {
                            pushNested(priorityHosts[i]);
                        }
                        if (root === document && document.body && document.body.children) {
                            const bodyKids = document.body.children;
                            for (let i = 0; i < bodyKids.length; i += 1) {
                                pushNested(bodyKids[i]);
                            }
                        }
                        const allEls = root.querySelectorAll('*');
                        const limit = Math.min(allEls.length, 600);
                        for (let i = 0; i < limit; i += 1) {
                            pushNested(allEls[i]);
                        }
                        if (allEls.length > 600) {
                            let customChecked = 0;
                            for (let i = 600; i < allEls.length && customChecked < 300; i += 1) {
                                const el = allEls[i];
                                if (el && el.tagName && el.tagName.indexOf('-') !== -1) {
                                    customChecked += 1;
                                    pushNested(el);
                                }
                            }
                        }
                    }
                } catch (_) {}
                return results;
            }

            function findPrimaryWebVideo() {
                const videos = collectVideos(document, 0);
                if (!videos || videos.length === 0) return null;
                let bestPlaying = null;
                let bestPlayingArea = -1;
                let bestVisible = null;
                let bestVisibleArea = -1;
                let fallback = null;
                for (let i = 0; i < videos.length; i += 1) {
                    const v = videos[i];
                    if (!v || !v.isConnected) continue;
                    if (!hasMediaSource(v) || isAmbientTrailerVideo(v)) continue;
                    const isPlayingNow = !v.paused && !v.ended && v.readyState >= 2;
                    const isPiP = document.pictureInPictureElement === v ||
                        (typeof v.webkitPresentationMode === 'string' && v.webkitPresentationMode === 'picture-in-picture');
                    let hidden = false;
                    try {
                        const cs = getComputedStyle(v);
                        hidden = cs.display === 'none' || cs.visibility === 'hidden';
                    } catch (_) {}
                    if (hidden && !isPlayingNow && !isPiP) continue;
                    if (!fallback) fallback = v;
                    const rect = v.getBoundingClientRect();
                    const area = Math.max(0, rect.width) * Math.max(0, rect.height);
                    if (isPlayingNow) {
                        if (area >= bestPlayingArea) {
                            bestPlaying = v;
                            bestPlayingArea = area;
                        }
                    }
                    if (area >= 160 * 90 && area > bestVisibleArea) {
                        bestVisible = v;
                        bestVisibleArea = area;
                    }
                }
                return bestPlaying || bestVisible || fallback;
            }

            function getMainVideo() {
                if (isWebCompanionHost()) {
                    return findPrimaryWebVideo();
                }
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

            window.__ytmacGetMainVideo = getMainVideo;

            let lastProgrammaticMuteActionAt = 0;
            let lastKnownMuted = null;
            let lastMutedVideoId = '';
            let airPlayTargetAvailable = false;

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
                if (!isStandardYouTubeHost()) return;
                const root = document.documentElement;
                if (!root || root.dataset.ytmacTilePlayer !== 'true' || root.dataset.ytmacOnWatch !== 'true') return;
                if (document.fullscreenElement) return;

                const syncOnce = () => {
                    if (document.fullscreenElement || !isStandardYouTubeHost()) return;
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
                const isStdYT = isStandardYouTubeHost();
                const isWeb = isWebCompanionHost();
                const hostTag = isYTTV ? 'yttv' : (isStdYT ? 'youtube' : 'web');
                if (root.dataset.ytmacHost !== hostTag) {
                    root.dataset.ytmacHost = hostTag;
                }

                const prevOnWatch = root.dataset.ytmacOnWatch === 'true';
                const prevTilePlayer = root.dataset.ytmacTilePlayer === 'true';
                const onWatch = !isWeb && isWatchPageWithPlayer();
                const bypassed = Boolean(cfg.cleanBoxBypassed);
                const tilePlayer = !isWeb && Boolean(cfg.miniPlayerActive || (cfg.multiviewTileActive && !bypassed));
                const ytCleanBox = isStdYT && onWatch && Boolean(cfg.cleanBoxStreamingPlayers && !bypassed && cfg.focusModeActive);
                const yttvCleanBox = isYTTV && onWatch && Boolean(cfg.cleanBoxStreamingPlayers && !bypassed && (cfg.miniPlayerActive || cfg.multiviewTileActive || cfg.focusModeActive));

                // Force YouTube-only flags to false on tv.youtube.com and third-party Companion web hosts.
                setDatasetFlag(root, 'ytmacHideShorts', isStdYT && cfg.hideShorts);
                setDatasetFlag(root, 'ytmacCleanChrome', isStdYT && cfg.cleanWebChrome);
                setDatasetFlag(root, 'ytmacHideHeader', isStdYT && cfg.hideWebHeader);
                setDatasetFlag(root, 'ytmacHideEndScreens', isStdYT && cfg.hideEndScreens);
                setDatasetFlag(root, 'ytmacHideWatchRecs', isStdYT && cfg.hideWatchRecommendations);
                setDatasetFlag(root, 'ytmacHideComments', isStdYT && cfg.hideComments);
                setDatasetFlag(root, 'ytmacHideHomeFeed', isStdYT && cfg.hideHomeFeed);
                setDatasetFlag(root, 'ytmacDisableAmbient', !isWeb && (cfg.disableAmbientMode || Boolean(cfg.multiviewTileActive)));
                setDatasetFlag(root, 'ytmacMiniPlayer', !isWeb && cfg.miniPlayerActive);
                setDatasetFlag(root, 'ytmacTilePlayer', tilePlayer);
                setDatasetFlag(root, 'ytmacOnWatch', onWatch);
                setDatasetFlag(root, 'ytmacAutoTheater', isStdYT && cfg.autoTheaterMode);
                setDatasetFlag(root, 'ytmacRedirectShorts', isStdYT && cfg.redirectShortsToWatch);

                if (isStdYT) {
                    setDatasetFlag(root, 'ytmacCleanBox', ytCleanBox);
                    lastCleanBoxEligible = onWatch;
                    lastCleanBoxActive = ytCleanBox || (tilePlayer && onWatch);
                    applyTheme(cfg);
                    if (cfg.autoTheaterMode && !document.cookie.includes('wide=1')) {
                        document.cookie = 'wide=1; path=/; domain=.youtube.com; max-age=31536000; SameSite=Lax';
                    }
                    if (tilePlayer && onWatch && (!prevOnWatch || !prevTilePlayer)) {
                        scheduleTileWatchResizeSync();
                    }
                } else if (isYTTV) {
                    setDatasetFlag(root, 'ytmacCleanBox', yttvCleanBox);
                    lastCleanBoxEligible = onWatch;
                    lastCleanBoxActive = yttvCleanBox;
                }
            }

            function markShortsElements() {
                if (!isStandardYouTubeHost()) return;
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
                if (!isStandardYouTubeHost()) return false;
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
                if (isWebCompanionHost()) {
                    return '';
                }
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
                if (!isStandardYouTubeHost()) return;
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
                if (!isStandardYouTubeHost()) return;
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
                if (isWebCompanionHost()) return;
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
                if (isWebCompanionHost()) return;
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
                if (isWebCompanionHost()) return;
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
                if (!isStandardYouTubeHost()) return;
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
                if (!isStandardYouTubeHost()) return;
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
                if (isWebCompanionHost()) {
                    const hostLabel = (location.hostname || '').replace(/^www\\./i, '');
                    const title = (document.title || hostLabel || 'Web').trim();
                    return { title, channel: hostLabel, channelURL: '' };
                }
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

            function clipContextText(raw) {
                return String(raw || '').replace(/\\s+/g, ' ').trim().slice(0, 200);
            }

            const EMPTY_STREAM_CONTEXT = {
                mediaSessionTitle: '',
                mediaSessionArtist: '',
                mediaSessionAlbum: '',
                ogTitle: '',
                headingHint: ''
            };

            function extractStreamContextMetadata() {
                if (isCompanionAuthPage()) {
                    return EMPTY_STREAM_CONTEXT;
                }
                let mediaSessionTitle = '';
                let mediaSessionArtist = '';
                let mediaSessionAlbum = '';
                let ogTitle = '';
                let headingHint = '';
                try {
                    const meta = (typeof navigator !== 'undefined' && navigator.mediaSession) ? navigator.mediaSession.metadata : null;
                    if (meta) {
                        mediaSessionTitle = clipContextText(meta.title);
                        mediaSessionArtist = clipContextText(meta.artist);
                        mediaSessionAlbum = clipContextText(meta.album);
                    }
                } catch (_) {}
                try {
                    const ogMeta = document.querySelector('meta[property="og:title"]');
                    if (ogMeta && typeof ogMeta.content === 'string') {
                        ogTitle = clipContextText(ogMeta.content);
                    }
                } catch (_) {}
                try {
                    const isWatch = isWatchPage() || (isWebCompanionHost() && (() => {
                        const r = isCleanBoxWatchPage();
                        return Boolean(r && r.type !== 'browse');
                    })());
                    if (isWatch) {
                        const h1 = document.querySelector('h1');
                        if (h1 && typeof h1.textContent === 'string') {
                            headingHint = clipContextText(h1.textContent);
                        }
                    }
                } catch (_) {}
                return {
                    mediaSessionTitle,
                    mediaSessionArtist,
                    mediaSessionAlbum,
                    ogTitle,
                    headingHint
                };
            }

            let boundVideo = null;
            let lastTimeEmit = 0;
            let lastEmittedKey = '';
            let cachedStreamContext = EMPTY_STREAM_CONTEXT;
            let lastContextExtractAt = 0;
            let lastContextURL = '';

            function emitMediaState(force) {
                const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);
                if (!handler) return;

                const now = Date.now();
                if (!force && now - lastTimeEmit < 1000) return;

                if (force === true || location.href !== lastContextURL || (now - lastContextExtractAt >= 10000)) {
                    cachedStreamContext = extractStreamContextMetadata();
                    lastContextExtractAt = now;
                    lastContextURL = location.href;
                }
                const streamCtx = cachedStreamContext;

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
                    volumePercent: 100,
                    isPiP: false,
                    isTheater,
                    isHDR: false,
                    playbackRate: 1.0,
                    isHomeFeedEmpty,
                    airPlayAvailable: false,
                    isAirPlayActive: false,
                    isCleanBoxActive: Boolean(lastCleanBoxActive),
                    isCleanBoxEligible: Boolean(lastCleanBoxEligible),
                    mediaSessionTitle: streamCtx.mediaSessionTitle,
                    mediaSessionArtist: streamCtx.mediaSessionArtist,
                    mediaSessionAlbum: streamCtx.mediaSessionAlbum,
                    ogTitle: streamCtx.ogTitle,
                    headingHint: streamCtx.headingHint
                } : (() => {
                    const isPiP = document.pictureInPictureElement === video ||
                        (typeof video.webkitPresentationMode === 'string' && video.webkitPresentationMode === 'picture-in-picture');
                    const hasVideo = (isWebCompanionHost() || isWatchPage())
                        && Boolean(video.src || video.currentSrc || video.srcObject || video.readyState > 0 || (isWebCompanionHost() && video.querySelector && video.querySelector('source[src]')));
                    let isMuted = Boolean(video.muted || video.volume === 0);
                    let volumePercent = 100;
                    try {
                        if (player && typeof player.isMuted === 'function') {
                            isMuted = Boolean(player.isMuted());
                        }
                        const rawVol = (player && typeof player.getVolume === 'function' && Number.isFinite(player.getVolume()))
                            ? (player.getVolume() / 100)
                            : Number(video.volume ?? 1);
                        volumePercent = Math.round(Math.min(Math.max(Number.isFinite(rawVol) ? rawVol : 1, 0), 1) * 100);
                    } catch (_) {
                        const fallbackVol = Number(video.volume ?? 1);
                        volumePercent = Math.round(Math.min(Math.max(Number.isFinite(fallbackVol) ? fallbackVol : 1, 0), 1) * 100);
                    }
                    const rate = Number.isFinite(video.playbackRate) && video.playbackRate > 0 ? video.playbackRate : 1.0;
                    const rawPlaying = hasVideo && !video.paused && !video.ended && video.readyState >= 2;
                    const effectivePlaying = (isScrubSuppressingStateChange(video) && wasPlayingBeforeScrub && hasVideo)
                        ? true
                        : rawPlaying;
                    const isAirPlayActive = hasVideo && Boolean(video.webkitCurrentPlaybackTargetIsWireless);
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
                        volumePercent,
                        isPiP: Boolean(isPiP),
                        isTheater,
                        isHDR: hasVideo && detectHDR(),
                        playbackRate: rate,
                        isHomeFeedEmpty,
                        airPlayAvailable: hasVideo && Boolean(airPlayTargetAvailable),
                        isAirPlayActive,
                        isCleanBoxActive: Boolean(lastCleanBoxActive),
                        isCleanBoxEligible: Boolean(lastCleanBoxEligible),
                        mediaSessionTitle: streamCtx.mediaSessionTitle,
                        mediaSessionArtist: streamCtx.mediaSessionArtist,
                        mediaSessionAlbum: streamCtx.mediaSessionAlbum,
                        ogTitle: streamCtx.ogTitle,
                        headingHint: streamCtx.headingHint
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
                    payload.volumePercent,
                    payload.isPiP,
                    payload.isTheater,
                    payload.isHDR,
                    rateKey,
                    payload.isHomeFeedEmpty,
                    payload.airPlayAvailable,
                    payload.isAirPlayActive,
                    payload.isCleanBoxActive,
                    payload.isCleanBoxEligible,
                    payload.mediaSessionTitle,
                    payload.mediaSessionArtist,
                    payload.mediaSessionAlbum,
                    payload.ogTitle,
                    payload.headingHint,
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
                    airPlayTargetAvailable = false;
                    emitMediaState(true);
                    return;
                }

                // Enable native WebKit AirPlay video target availability & wireless state reporting.
                try {
                    video.setAttribute('x-webkit-airplay', 'allow');
                    if ('disableRemotePlayback' in video) {
                        video.disableRemotePlayback = false;
                    }
                } catch (_) {}
                video.addEventListener('webkitplaybacktargetavailabilitychanged', (ev) => {
                    airPlayTargetAvailable = Boolean(ev && ev.availability === 'available');
                    emitMediaState(true);
                });
                video.addEventListener('webkitcurrentplaybacktargetiswirelesschanged', () => {
                    emitMediaState(true);
                });

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
                            const mediaKey = isWebCompanionHost() ? location.href : currentVideoId();
                            const eligiblePage = isWebCompanionHost() || isWatchPage();
                            if (eligiblePage
                                && (Date.now() - lastProgrammaticMuteActionAt > 500)
                                && lastKnownMuted === true
                                && nowMuted === false
                                && mediaKey
                                && mediaKey === lastMutedVideoId) {
                                const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);
                                if (handler) {
                                    handler.postMessage({
                                        event: 'userUnmuted',
                                        urlString: location.href
                                    });
                                }
                            }
                            lastKnownMuted = nowMuted;
                            lastMutedVideoId = mediaKey;
                        } else if (evt === 'loadedmetadata') {
                            const player = getPlayer();
                            lastKnownMuted = resolveMutedState(player, video);
                            lastMutedVideoId = isWebCompanionHost() ? location.href : currentVideoId();
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
                lastMutedVideoId = isWebCompanionHost() ? location.href : currentVideoId();
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

                if (!isStandardYouTubeHost() || !isWatchPage()) {
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

                const cappedDescription = description ? description.slice(0, 16384) : '';
                const sig = vid + '|' + structured.length + '|' + (structured.length ? structured[0].title : '') + '|' + cappedDescription.length;
                if (sig === lastEmittedChaptersSig) return;
                lastEmittedChaptersSig = sig;

                handler.postMessage({
                    event: 'chaptersUpdated',
                    videoId: vid,
                    chapters: structured,
                    description: cappedDescription
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
                const prevActive = lastCleanBoxActive;
                const prevEligible = lastCleanBoxEligible;
                applyDatasetConfig(cfg);
                if (isWebCompanionHost()) {
                    syncCompanionCleanBox('configOnly');
                    if (!lastCleanBoxActive && cfg.cleanBoxStreamingPlayers && !cfg.cleanBoxBypassed) {
                        scheduleCleanBoxSettleTimers();
                    }
                }
                if (prevActive !== lastCleanBoxActive || prevEligible !== lastCleanBoxEligible) {
                    emitMediaState(true);
                }
                if (cfg.hideShorts && isStandardYouTubeHost()) {
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
                const cfg = window.__ytmacConfig || initialConfig;
                applyDatasetConfig(cfg);
                if (isWebCompanionHost()) {
                    syncCompanionCleanBox('runtime');
                    scheduleCleanBoxSettleTimers();
                }
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
                        if (isWebCompanionHost()) {
                            window.__ytmacSubframeMediaActive = false;
                            cleanBoxBlockedByModal = false;
                            clearCleanBoxSettleTimers();
                            clearCleanBoxCloseTimers();
                            releaseCompanionCleanBox(isCompanionAuthPage(), true);
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
                        if (cfg.appearance === 'system' && isStandardYouTubeHost()) {
                            applyTheme(cfg);
                        }
                    };
                    if (typeof colorSchemeQuery.addEventListener === 'function') {
                        colorSchemeQuery.addEventListener('change', handleColorSchemeChange);
                    }
                }

                // Zero-overhead capture-phase detection for dynamically mounted HTML5 <video> elements (including open Shadow DOM).
                const handleCapturedVideoEvent = (ev) => {
                    const target = (ev && typeof ev.composedPath === 'function' && ev.composedPath()[0]) || (ev && ev.target);
                    if (!target || target.tagName !== 'VIDEO') return;
                    if (isWebCompanionHost()) {
                        bindVideoListeners();
                        syncCompanionCleanBox('video:' + (ev.type || ''));
                        emitMediaState(true);
                    } else if (boundVideo !== target) {
                        bindVideoListeners();
                        emitMediaState(true);
                    }
                };
                window.addEventListener('play', handleCapturedVideoEvent, true);
                window.addEventListener('playing', handleCapturedVideoEvent, true);
                window.addEventListener('loadedmetadata', handleCapturedVideoEvent, true);
                window.addEventListener('loadeddata', handleCapturedVideoEvent, true);
                window.addEventListener('canplay', handleCapturedVideoEvent, true);
                window.addEventListener('pause', handleCapturedVideoEvent, true);
                window.addEventListener('emptied', handleCapturedVideoEvent, true);
                window.addEventListener('ended', handleCapturedVideoEvent, true);
                window.addEventListener('load', (ev) => {
                    const target = ev && ev.target;
                    if (!target || target.tagName !== 'IFRAME') return;
                    if (isWebCompanionHost()) {
                        syncCompanionCleanBox('iframe:load');
                    }
                }, { capture: true, passive: true });

                const scheduleOverlayCloseRecheck = () => {
                    if (!isWebCompanionHost() || (!activeCleanBoxState.root && !cleanBoxBlockedByModal)) return;
                    clearCleanBoxCloseTimers();
                    cleanBoxCloseTimer1 = setTimeout(() => {
                        cleanBoxCloseTimer1 = null;
                        syncCompanionCleanBox('overlayCheck1');
                    }, 150);
                    cleanBoxCloseTimer2 = setTimeout(() => {
                        cleanBoxCloseTimer2 = null;
                        syncCompanionCleanBox('overlayCheck2');
                    }, 500);
                };
                window.addEventListener('click', scheduleOverlayCloseRecheck, true);
                window.addEventListener('keydown', (ev) => {
                    if (ev && ev.key === 'Escape') {
                        scheduleOverlayCloseRecheck();
                    }
                }, true);

                const handleFullscreenChange = () => {
                    if (document.fullscreenElement || document.webkitFullscreenElement) return;
                    if (isWebCompanionHost()) {
                        syncCompanionCleanBox('fullscreenExit');
                    }
                };
                document.addEventListener('fullscreenchange', handleFullscreenChange, true);
                document.addEventListener('webkitfullscreenchange', handleFullscreenChange, true);

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
                    if (!isStandardYouTubeHost()) return;
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
            if (typeof window.__ytmacApplyConfigOnly === 'function') {
                window.__ytmacConfig = \(configJSON);
                window.__ytmacApplyConfigOnly();
            }\(resizeLine)
        })();
        """
    }

    /// One-shot viewport & YouTube player resize notification fired strictly after a WKWebView returns to full single-tab layout.
    public static let notifyViewportResizeScript = """
    (() => {
        const ds = document.documentElement.dataset;
        if (document.fullscreenElement || document.webkitFullscreenElement || ds.ytmacMiniPlayer === 'true' || ds.ytmacTilePlayer === 'true') return;
        requestAnimationFrame(() => {
            const d = document.documentElement.dataset;
            if (document.fullscreenElement || document.webkitFullscreenElement || d.ytmacMiniPlayer === 'true' || d.ytmacTilePlayer === 'true') return;
            if (typeof window.__ytmacSyncCleanBox === 'function') {
                window.__ytmacSyncCleanBox('resizeSync');
            }
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
    const hostLower = location.hostname.toLowerCase();
    const isYTTVHost = hostLower === 'tv.youtube.com';
    const isStdYTHost = !isYTTVHost && /(^|\\.)(youtube\\.com|youtu\\.be|youtube-nocookie\\.com)$/i.test(hostLower);
    const p = (isYTTVHost || isStdYTHost)
        ? (document.getElementById('movie_player') || document.querySelector('.html5-video-player'))
        : null;
    const isWatchPath = isYTTVHost
        ? /^\\/watch\\/[^/?#]+/.test(location.pathname)
        : (isStdYTHost && (location.pathname.startsWith('/watch') || /^\\/live\\/[^/?#]+/.test(location.pathname)));
    let v = (typeof window.__ytmacGetMainVideo === 'function') ? window.__ytmacGetMainVideo() : null;
    if (!v) {
        if (isYTTVHost || isStdYTHost) {
            v = (p && (p.querySelector('video.html5-main-video') || p.querySelector('video')))
                || (isWatchPath ? (document.querySelector('video.html5-main-video') || document.querySelector('video')) : null);
        } else {
            const collectVids = (root, depth) => {
                const out = [];
                if (!root || depth > 4) return out;
                const seen = new Set();
                const pushHost = (host) => {
                    if (!host || !host.shadowRoot || seen.has(host)) return;
                    seen.add(host);
                    const sub = collectVids(host.shadowRoot, depth + 1);
                    for (let j = 0; j < sub.length; j += 1) out.push(sub[j]);
                };
                try {
                    const list = root.querySelectorAll ? root.querySelectorAll('video') : [];
                    for (let i = 0; i < list.length; i += 1) out.push(list[i]);
                    if (depth < 4 && root.querySelectorAll) {
                        const priority = root.querySelectorAll('apple-tv-plus-player, amp-chrome-player, amp-video-player, amp-video-player-internal, disney-web-player, btm-media-client-element, video-js, media-controller, shaka-player');
                        for (let i = 0; i < priority.length; i += 1) pushHost(priority[i]);
                        if (root === document && document.body && document.body.children) {
                            const kids = document.body.children;
                            for (let i = 0; i < kids.length; i += 1) pushHost(kids[i]);
                        }
                        const els = root.querySelectorAll('*');
                        const cap = Math.min(els.length, 600);
                        for (let i = 0; i < cap; i += 1) {
                            pushHost(els[i]);
                        }
                        if (els.length > 600) {
                            let customChecked = 0;
                            for (let i = 600; i < els.length && customChecked < 300; i += 1) {
                                const el = els[i];
                                if (el && el.tagName && el.tagName.indexOf('-') !== -1) {
                                    customChecked += 1;
                                    pushHost(el);
                                }
                            }
                        }
                    }
                } catch (_) {}
                return out;
            };
            const vids = collectVids(document, 0);
            let bestPlaying = null, bestPlayingArea = -1, bestVisible = null, bestVisibleArea = -1, firstMedia = null;
            for (let i = 0; i < vids.length; i += 1) {
                const cand = vids[i];
                if (!cand || !(cand.src || cand.currentSrc || cand.srcObject || cand.readyState > 0 || (cand.querySelector && cand.querySelector('source[src]')))) continue;
                if (!firstMedia) firstMedia = cand;
                const r = cand.getBoundingClientRect();
                const area = Math.max(0, r.width) * Math.max(0, r.height);
                if (!cand.paused && !cand.ended && cand.readyState >= 2 && area >= bestPlayingArea) {
                    bestPlaying = cand; bestPlayingArea = area;
                }
                if (area >= 160 * 90 && area > bestVisibleArea) {
                    bestVisible = cand; bestVisibleArea = area;
                }
            }
            v = bestPlaying || bestVisible || firstMedia;
        }
    }
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

    public static let playScript = """
    (() => {
        \(resolveMainVideoSnippet)
        if (!v) return false;
        if (v.paused || v.ended) {
            try {
                if (p && typeof p.playVideo === 'function') {
                    p.playVideo();
                } else {
                    v.play().catch(() => {});
                }
            } catch (_) {
                v.play().catch(() => {});
            }
        }
        if (typeof window.__ytmacEmitStateNow === 'function') window.__ytmacEmitStateNow();
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
        let safeDelta = seconds.isFinite ? seconds : 0
        return """
        (() => {
            \(resolveMainVideoSnippet)
            if (!v) return false;
            const cur = Number.isFinite(v.currentTime) ? v.currentTime : 0;
            let next = cur + (\(safeDelta));
            if (v.seekable && v.seekable.length > 0) {
                const minT = v.seekable.start(0);
                const maxT = v.seekable.end(v.seekable.length - 1);
                if (Number.isFinite(minT) && Number.isFinite(maxT) && maxT >= minT) {
                    const ceiling = Number.isFinite(v.duration) ? maxT : Math.max(minT, maxT - 0.25);
                    next = Math.max(minT, Math.min(ceiling, next));
                } else {
                    next = Math.max(0, next);
                }
            } else if (Number.isFinite(v.duration) && v.duration > 0) {
                next = Math.max(0, Math.min(v.duration, next));
            } else {
                next = Math.max(0, next);
            }
            v.currentTime = next;
            if (typeof window.__ytmacEmitStateNow === 'function') window.__ytmacEmitStateNow();
            return true;
        })();
        """
    }

    /// Jumps a live HLS/DASH/MSE stream cleanly to its live edge (`maxSeekable - 0.5s`) without tip-of-buffer stalls.
    public static let seekToLiveEdgeScript = """
    (() => {
        \(resolveMainVideoSnippet)
        if (!v || !v.seekable || v.seekable.length === 0) return false;
        const minT = v.seekable.start(0);
        const maxT = v.seekable.end(v.seekable.length - 1);
        if (!Number.isFinite(maxT) || maxT <= 0) return false;
        const safeMin = Number.isFinite(minT) ? minT : 0;
        const target = Math.max(safeMin, maxT - 0.5);
        v.currentTime = target;
        if (typeof window.__ytmacEmitStateNow === 'function') window.__ytmacEmitStateNow();
        return true;
    })();
    """

    /// One-shot player viewport resize sync fired when toggling Multiview Solo mode (strictly skipped in HTML5 fullscreen).
    public static let syncPlayerSizeScript = """
    (() => {
        if (document.fullscreenElement || document.webkitFullscreenElement) return false;
        const syncNow = () => {
            if (document.fullscreenElement || document.webkitFullscreenElement) return;
            if (typeof window.__ytmacSyncCleanBox === 'function') {
                window.__ytmacSyncCleanBox('resizeSync');
            }
            try { window.dispatchEvent(new Event('resize')); } catch (_) {}
            try {
                const p = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (p && typeof p.setSize === 'function') p.setSize();
                if (p && typeof p.setInternalSize === 'function') p.setInternalSize();
            } catch (_) {}
        };
        if (typeof requestAnimationFrame === 'function') {
            requestAnimationFrame(syncNow);
        } else {
            syncNow();
        }
        return true;
    })();
    """

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

    /// Triggers WebKit's native element-level AirPlay target picker when supported, returning a structured
    /// status string (`'ok'`, `'mse_unsupported'`, `'unavailable'`, or `'no_video'`) so UI never fails silently.
    public static let teardownCompanionCleanBoxScript = """
    (() => {
        if (typeof window.__ytmacSyncCleanBox === 'function') {
            window.__ytmacSyncCleanBox('authTeardown');
        }
        const root = document.documentElement;
        if (root) delete root.dataset.ytmacCleanBox;
        const tagged = document.querySelectorAll('[data-ytmac-cb]');
        for (let i = 0; i < tagged.length; i += 1) {
            tagged[i].removeAttribute('data-ytmac-cb');
        }
        const styleEl = document.getElementById('ytmac-cleanbox-style');
        if (styleEl) styleEl.remove();
        return true;
    })();
    """

    /// One-shot Clean-Box re-evaluation hook invoked on main frame when a subframe player detects active `<video>`.
    public static let syncCompanionCleanBoxScript = """
    (() => {
        window.__ytmacSubframeMediaActive = true;
        if (typeof window.__ytmacSyncCleanBox === 'function') {
            return Boolean(window.__ytmacSyncCleanBox('subframe'));
        }
        return false;
    })();
    """

    /// Resets the verified subframe-media indicator on the main frame when subframe state clears or navigates.
    public static let clearSubframeMediaActiveScript = """
    (() => {
        window.__ytmacSubframeMediaActive = false;
    })();
    """

    /// Lightweight `forMainFrameOnly: false` media telemetry & control bridge strictly for allowlisted cross-origin player iframes.
    /// Zero CSS, zero observers, zero DOM polling; returns immediately in non-subframes or disallowed origins.
    public static func subframeMediaBridgeScript() -> String {
        let quotedSuffixes = CleanBoxRules.allAllowedPlayerIframeHostSuffixes
            .map { "\"\(escapeJSString($0))\"" }
            .joined(separator: ", ")

        return """
        (() => {
            if (window === window.top) return;
            const host = (location.hostname || '').toLowerCase();
            if (!host) return;
            if (/^(sso|auth|login|signin|sign-in|passport|identity|id|ids|accounts|oauth)\\./i.test(host)) return;
            if (/(doubleclick\\.net|googlesyndication\\.com|imasdk\\.googleapis\\.com|adservice\\.google\\.com|amazon-adsystem\\.com|scorecardresearch\\.com|moatads\\.com)$/i.test(host)) return;
            const allowedSuffixes = [\(quotedSuffixes)];
            if (!allowedSuffixes.some((s) => host === s || host.endsWith('.' + s))) return;

            function hasSubframeSize() {
                return window.innerWidth >= 100 && window.innerHeight >= 56;
            }

            function hasSubframeMediaSource(v) {
                return Boolean(v && (v.src || v.currentSrc || v.srcObject || v.readyState > 0 || (v.querySelector && v.querySelector('source[src]'))));
            }

            function getSubframeVideo() {
                if (!hasSubframeSize()) return null;
                const list = document.querySelectorAll('video');
                let best = null;
                let bestArea = -1;
                for (let i = 0; i < list.length; i += 1) {
                    const v = list[i];
                    if (!v || !v.isConnected) continue;
                    if (!hasSubframeMediaSource(v)) continue;
                    const r = v.getBoundingClientRect();
                    const area = Math.max(0, r.width) * Math.max(0, r.height);
                    if (!v.paused && !v.ended && v.readyState >= 2) return v;
                    if (area >= bestArea) { best = v; bestArea = area; }
                }
                return best;
            }

            window.__ytmacGetMainVideo = getSubframeVideo;

            let lastProgMuteAt = 0;
            let lastMutedState = null;
            let lastSubframeHasVideo = false;
            let lastTimeSent = 0;
            let lastSig = '';
            let bound = null;
            let airPlayAvail = false;

            window.__ytmacMarkProgrammaticMute = () => {
                lastProgMuteAt = Date.now();
            };

            function emitSubframeState(force) {
                const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);
                if (!handler) return;
                const now = Date.now();
                if (!force && now - lastTimeSent < 1000) return;
                const v = getSubframeVideo();
                const hasVideo = hasSubframeMediaSource(v);
                lastSubframeHasVideo = hasVideo;
                const isMuted = Boolean(v && (v.muted || v.volume === 0));
                const rawVol = v ? Number(v.volume ?? 1) : 1;
                const volumePercent = Math.round(Math.min(Math.max(Number.isFinite(rawVol) ? rawVol : 1, 0), 1) * 100);
                const isPlaying = Boolean(hasVideo && v && !v.paused && !v.ended && v.readyState >= 2);
                const currentTime = (v && Number.isFinite(v.currentTime)) ? v.currentTime : 0;
                const duration = (v && Number.isFinite(v.duration)) ? v.duration : 0;
                const playbackRate = (v && Number.isFinite(v.playbackRate) && v.playbackRate > 0) ? v.playbackRate : 1.0;
                const isPiP = Boolean(v && (document.pictureInPictureElement === v || v.webkitPresentationMode === 'picture-in-picture'));
                const isAirPlayActive = Boolean(hasVideo && v && v.webkitCurrentPlaybackTargetIsWireless);

                const sig = [
                    hasVideo, isPlaying, isMuted, volumePercent, isPiP,
                    Math.round(playbackRate * 100),
                    airPlayAvail, isAirPlayActive,
                    Math.floor(currentTime), Math.floor(duration)
                ].join('|');
                if (sig === lastSig && !force) return;
                lastSig = sig;
                lastTimeSent = now;
                handler.postMessage({
                    subframeMedia: true,
                    hasVideo,
                    isPlaying,
                    isMuted,
                    volumePercent,
                    isPiP,
                    playbackRate,
                    airPlayAvailable: hasVideo && airPlayAvail,
                    isAirPlayActive,
                    currentTime,
                    duration
                });
            }

            window.__ytmacEmitStateNow = () => emitSubframeState(true);

            function bindSubframeVideo() {
                const v = getSubframeVideo();
                if (v === bound) return;
                bound = v;
                if (!v) {
                    airPlayAvail = false;
                    emitSubframeState(true);
                    return;
                }
                try {
                    v.setAttribute('x-webkit-airplay', 'allow');
                    if ('disableRemotePlayback' in v) v.disableRemotePlayback = false;
                } catch (_) {}
                lastMutedState = Boolean(v.muted || v.volume === 0);
                v.addEventListener('webkitplaybacktargetavailabilitychanged', (ev) => {
                    airPlayAvail = Boolean(ev && ev.availability === 'available');
                    emitSubframeState(true);
                });
                v.addEventListener('webkitcurrentplaybacktargetiswirelesschanged', () => emitSubframeState(true));
                for (const evt of ['play', 'playing', 'pause', 'ended', 'seeked', 'loadedmetadata', 'loadeddata', 'canplay', 'durationchange', 'volumechange', 'ratechange', 'emptied']) {
                    v.addEventListener(evt, () => {
                        const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);
                        if (evt === 'ended' && handler) {
                            handler.postMessage({ event: 'videoEnded', urlString: location.href });
                        } else if (evt === 'volumechange') {
                            const nowMuted = Boolean(v.muted || v.volume === 0);
                            if ((Date.now() - lastProgMuteAt > 500) && lastMutedState === true && nowMuted === false && handler) {
                                handler.postMessage({ event: 'userUnmuted', urlString: location.href });
                            }
                            lastMutedState = nowMuted;
                        }
                        emitSubframeState(true);
                    }, { passive: true });
                }
                v.addEventListener('timeupdate', () => emitSubframeState(false), { passive: true });
                emitSubframeState(true);
            }

            if (!window.__ytmacSubframeInit) {
                window.__ytmacSubframeInit = true;
                const onCapture = (ev) => {
                    const target = ev && ev.target;
                    if (!target || target.tagName !== 'VIDEO') return;
                    bindSubframeVideo();
                    emitSubframeState(true);
                };
                window.addEventListener('play', onCapture, true);
                window.addEventListener('playing', onCapture, true);
                window.addEventListener('loadedmetadata', onCapture, true);
                window.addEventListener('loadeddata', onCapture, true);
                window.addEventListener('canplay', onCapture, true);
                window.addEventListener('emptied', onCapture, true);
                window.addEventListener('resize', () => {
                    if ((!bound || !lastSubframeHasVideo) && hasSubframeSize()) {
                        bindSubframeVideo();
                        emitSubframeState(true);
                    }
                }, { passive: true });
                window.addEventListener('pagehide', () => {
                    const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);
                    if (handler) {
                        handler.postMessage({
                            subframeMedia: true,
                            hasVideo: false,
                            isPlaying: false,
                            isMuted: false,
                            volumePercent: 100,
                            isPiP: false,
                            playbackRate: 1.0,
                            airPlayAvailable: false,
                            isAirPlayActive: false,
                            currentTime: 0,
                            duration: 0
                        });
                    }
                });
            }

            bindSubframeVideo();
        })();
        """
    }

    /// Triggers WebKit's native element-level AirPlay target picker when supported, returning a structured
    /// status string (`'ok'`, `'mse_unsupported'`, `'unavailable'`, or `'no_video'`) so UI never fails silently.
    public static let showAirPlayPickerScript = """
    (() => {
        \(resolveMainVideoSnippet)
        if (!v) return 'no_video';
        try {
            v.setAttribute('x-webkit-airplay', 'allow');
            if ('disableRemotePlayback' in v) v.disableRemotePlayback = false;
        } catch (_) {}
        const src = String(v.currentSrc || v.src || '');
        const isMSEBlob = src.startsWith('blob:');
        if (typeof v.webkitShowPlaybackTargetPicker === 'function') {
            if (isMSEBlob && !v.webkitCurrentPlaybackTargetIsWireless) {
                try {
                    v.webkitShowPlaybackTargetPicker();
                    return 'mse_unsupported';
                } catch (_) {
                    return 'mse_unsupported';
                }
            }
            try {
                v.webkitShowPlaybackTargetPicker();
                return 'ok';
            } catch (_) {
                return isMSEBlob ? 'mse_unsupported' : 'unavailable';
            }
        }
        return isMSEBlob ? 'mse_unsupported' : 'unavailable';
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

    static func encodeCleanBoxProfilesJSON() -> String {
        let companionProfiles = CleanBoxRules.allProfiles.filter {
            $0.serviceID != "youtube" && $0.serviceID != "yttv"
        }
        let entries = companionProfiles.map { prof -> String in
            let pSels = prof.playerSelectors.map { "\"\(escapeJSString($0))\"" }.joined(separator: ",")
            let iSels = prof.iframeSelectors.map { "\"\(escapeJSString($0))\"" }.joined(separator: ",")
            let aHosts = prof.allowedIframeHostSuffixes.map { "\"\(escapeJSString($0))\"" }.joined(separator: ",")
            return """
            "\(escapeJSString(prof.serviceID))": {
              "strategy": "\(escapeJSString(prof.strategy.rawValue))",
              "playerSelectors": [\(pSels)],
              "iframeSelectors": [\(iSels)],
              "allowedIframeHostSuffixes": [\(aHosts)]
            }
            """
        }.joined(separator: ",\n")
        return "{\n\(entries)\n}"
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
          "multiviewTileActive": \(boolString(config.multiviewTileActive)),
          "cleanBoxStreamingPlayers": \(boolString(config.cleanBoxStreamingPlayers)),
          "cleanBoxBypassed": \(boolString(config.cleanBoxBypassed))
        }
        """
    }

    static let cleanBoxCSSRules = """
    html[data-ytmac-host="web"][data-ytmac-clean-box="true"],
    html[data-ytmac-host="web"][data-ytmac-clean-box="true"] body {
        overflow: hidden !important;
        background: #000 !important;
        margin: 0 !important;
        padding: 0 !important;
        width: 100vw !important;
        height: 100vh !important;
    }

    html[data-ytmac-host="web"][data-ytmac-clean-box="true"] [data-ytmac-cb="ancestor"] {
        transform: none !important;
        translate: none !important;
        scale: none !important;
        rotate: none !important;
        perspective: none !important;
        filter: none !important;
        backdrop-filter: none !important;
        -webkit-backdrop-filter: none !important;
        contain: none !important;
        content-visibility: visible !important;
        container-type: normal !important;
        will-change: auto !important;
        clip-path: none !important;
        -webkit-clip-path: none !important;
        mask: none !important;
        -webkit-mask: none !important;
        isolation: auto !important;
        mix-blend-mode: normal !important;
        overflow: visible !important;
        z-index: auto !important;
    }

    html[data-ytmac-host="web"][data-ytmac-clean-box="true"] [data-ytmac-cb="player"] {
        position: fixed !important;
        inset: 0 !important;
        top: 0 !important;
        left: 0 !important;
        right: 0 !important;
        bottom: 0 !important;
        width: 100vw !important;
        height: 100vh !important;
        max-width: 100vw !important;
        max-height: 100vh !important;
        min-width: 100vw !important;
        min-height: 100vh !important;
        margin: 0 !important;
        padding: 0 !important;
        border: 0 !important;
        border-radius: 0 !important;
        aspect-ratio: auto !important;
        transform: none !important;
        z-index: 2147483640 !important;
        background: #000 !important;
        box-sizing: border-box !important;
        overflow: hidden !important;
    }

    html[data-ytmac-host="web"][data-ytmac-clean-box="true"] iframe[data-ytmac-cb="player"],
    html[data-ytmac-host="web"][data-ytmac-clean-box="true"] video[data-ytmac-cb="player"] {
        display: block !important;
    }

    html[data-ytmac-host="web"][data-ytmac-clean-box="true"] [data-ytmac-cb="chain"] {
        top: 0 !important;
        left: 0 !important;
        right: auto !important;
        bottom: auto !important;
        width: 100% !important;
        height: 100% !important;
        min-width: 0 !important;
        min-height: 0 !important;
        max-width: 100% !important;
        max-height: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
        border: 0 !important;
        border-radius: 0 !important;
        aspect-ratio: auto !important;
        transform: none !important;
        box-sizing: border-box !important;
    }

    html[data-ytmac-host="web"][data-ytmac-clean-box="true"] [data-ytmac-cb="iframe"] {
        display: block !important;
        top: 0 !important;
        left: 0 !important;
        right: auto !important;
        bottom: auto !important;
        width: 100% !important;
        height: 100% !important;
        min-width: 0 !important;
        min-height: 0 !important;
        max-width: 100% !important;
        max-height: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
        border: 0 !important;
        transform: none !important;
    }

    html[data-ytmac-host="web"][data-ytmac-clean-box="true"] [data-ytmac-cb="video"] {
        display: block !important;
        top: 0 !important;
        left: 0 !important;
        right: auto !important;
        bottom: auto !important;
        width: 100% !important;
        height: 100% !important;
        min-width: 0 !important;
        min-height: 0 !important;
        max-width: 100% !important;
        max-height: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
        border: 0 !important;
        transform: none !important;
        object-fit: contain !important;
    }
    """

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
    html[data-ytmac-host="youtube"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"],
    html[data-ytmac-host="youtube"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"] body,
    html[data-ytmac-host="yttv"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"],
    html[data-ytmac-host="yttv"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] body,
    html[data-ytmac-host="yttv"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"],
    html[data-ytmac-host="yttv"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"] body {
        overflow: hidden !important;
        background: #000 !important;
    }

    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] #masthead-container,
    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] #below,
    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] #secondary,
    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] #guide,
    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] ytd-mini-guide-renderer,
    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] #panels-full-bleed-container,
    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] #chat-container,
    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] ytd-live-chat-frame,
    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] #chat,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #masthead-container,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #below,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #secondary,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #guide,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] ytd-mini-guide-renderer,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #panels-full-bleed-container,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #chat-container,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] ytd-live-chat-frame,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #chat,
    html[data-ytmac-host="youtube"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"] #masthead-container,
    html[data-ytmac-host="youtube"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"] #below,
    html[data-ytmac-host="youtube"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"] #secondary,
    html[data-ytmac-host="youtube"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"] #guide,
    html[data-ytmac-host="youtube"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"] ytd-mini-guide-renderer,
    html[data-ytmac-host="youtube"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"] #panels-full-bleed-container,
    html[data-ytmac-host="youtube"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"] #chat-container,
    html[data-ytmac-host="youtube"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"] ytd-live-chat-frame,
    html[data-ytmac-host="youtube"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"] #chat {
        display: none !important;
    }

    html[data-ytmac-mini-player="true"][data-ytmac-on-watch="true"] #movie_player,
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #movie_player,
    html[data-ytmac-host="youtube"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"] #movie_player {
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
    html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"] #movie_player video.html5-main-video,
    html[data-ytmac-host="youtube"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"] #movie_player .html5-video-container,
    html[data-ytmac-host="youtube"][data-ytmac-clean-box="true"][data-ytmac-on-watch="true"] #movie_player video.html5-main-video {
        width: 100% !important;
        height: 100% !important;
        left: 0 !important;
        top: 0 !important;
        object-fit: contain !important;
    }
    """
}
