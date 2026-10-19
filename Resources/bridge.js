// bridge.js — injected into music.youtube.com by the app (see Player.swift).
//
// The hidden web page does the actual playback and owns the signed-in session. This script:
//   1. reports what's playing to Swift (window.webkit.messageHandlers.ytm), and
//   2. exposes `window.ytmBridge`, which Swift calls to search, browse, play, edit the queue and run
//      account actions. Everything goes through YouTube Music's own internal API ("youtubei") and
//      its in-page router/queue, so it reuses the page's session exactly like the web app does.
//
// Results go back to Swift as JSON strings shaped like the Codable models in Models.swift.
// YouTube Music's responses are undocumented and change over time; the parsers below look for the
// renderer objects by name rather than by fixed paths so small layout changes don't break them.

(() => {
  // MARK: - Generic helpers

  /** Joins a YouTube "runs" text object (or simpleText) into a plain string. */
  const text = o => (o && o.runs ? o.runs.map(r => r.text).join('') : (o && o.simpleText) || '');

  /** Largest thumbnail URL of a music thumbnail renderer. */
  const thumb = o => {
    const r = o && (o.musicThumbnailRenderer || o.croppedSquareThumbnailRenderer);
    const t = (r && r.thumbnail && r.thumbnail.thumbnails) || [];
    if (!t.length) return null;
    const url = t[t.length - 1].url;
    return url.startsWith('//') ? 'https:' + url : url;
  };

  /** Depth-first search for the first value stored under `key`. */
  const find = (o, key, depth = 0) => {
    if (!o || typeof o !== 'object' || depth > 25) return undefined;
    if (o[key] !== undefined) return o[key];
    for (const v of Object.values(o)) {
      const found = find(v, key, depth + 1);
      if (found !== undefined) return found;
    }
    return undefined;
  };

  /** Every value stored under `key`, anywhere. */
  const findAll = (o, key, out = [], depth = 0) => {
    if (!o || typeof o !== 'object' || depth > 25) return out;
    if (o[key] !== undefined) out.push(o[key]);
    for (const v of Object.values(o)) findAll(v, key, out, depth + 1);
    return out;
  };

  /** Target of a browse link: its id and page type (artist, album, playlist, …). */
  const browseInfo = ep => {
    const b = ep && ep.browseEndpoint;
    if (!b) return { browseId: null, pageType: null };
    const c = b.browseEndpointContextSupportedConfigs && b.browseEndpointContextSupportedConfigs.browseEndpointContextMusicConfig;
    return { browseId: b.browseId || null, pageType: (c && c.pageType) || null };
  };

  /**
   * An endpoint from the web app, serialized for Swift to hand back later verbatim. Reusing the
   * page's own requests keeps details a hand-built one lacks (e.g. musicVideoType: ATV, which makes
   * YouTube play the song rather than its music video).
   */
  const endpointJSON = ep => {
    if (!ep) return null;
    const { clickTrackingParams, commandMetadata, ...rest } = ep;
    return JSON.stringify(rest);
  };

  /** Whether a row, card or queue entry carries the explicit badge. */
  const isExplicit = o => JSON.stringify((o && (o.badges || o.subtitleBadges)) || []).includes('MUSIC_EXPLICIT_BADGE');

  const menuItems = menu => (menu && menu.menuRenderer && menu.menuRenderer.items) || [];

  /** The item's "Start mix" request (mix playlists start with RDA…, mix params are "wAEB"). */
  const mixOf = menu => {
    for (const item of menuItems(menu)) {
      const ep = item.menuNavigationItemRenderer && item.menuNavigationItemRenderer.navigationEndpoint;
      const w = ep && (ep.watchEndpoint || ep.watchPlaylistEndpoint);
      if (w && (w.params === 'wAEB' || /^RDA[MO]/.test(w.playlistId || ''))) return endpointJSON(ep);
    }
    return null;
  };

  /** A "Save to library" toggle (menu item or header button), recognized by its bookmark icon. */
  const libraryToggle = t => (t && t.defaultIcon && t.defaultIcon.iconType === 'BOOKMARK_BORDER'
    ? { inLibrary: !!t.isToggled, libraryAdd: endpointJSON(t.defaultServiceEndpoint),
        libraryRemove: endpointJSON(t.toggledServiceEndpoint) }
    : null);

  const libraryOf = menu => {
    for (const item of menuItems(menu)) {
      const found = libraryToggle(item.toggleMenuServiceItemRenderer);
      if (found) return found;
    }
    return {};
  };

  /**
   * A subtitle as segments, keeping the artist/album/creator links so the UI can make them
   * clickable, plus the first artist, album and creator for menus.
   */
  const linksOf = runLists => {
    const out = { segments: [], artistId: null, artistName: null, albumId: null, creatorId: null, creatorName: null };
    for (const runs of runLists) {
      if (!runs || !runs.length) continue;
      if (out.segments.length) out.segments.push({ text: ' • ' });
      for (const r of runs) {
        const b = browseInfo(r.navigationEndpoint);
        out.segments.push({ text: r.text, id: b.browseId, type: b.pageType });
        if (b.pageType === 'MUSIC_PAGE_TYPE_ARTIST' && !out.artistId) { out.artistId = b.browseId; out.artistName = r.text; }
        if (b.pageType === 'MUSIC_PAGE_TYPE_ALBUM' && !out.albumId) out.albumId = b.browseId;
        if (b.pageType === 'MUSIC_PAGE_TYPE_USER_CHANNEL' && !out.creatorId) { out.creatorId = b.browseId; out.creatorName = r.text; }
      }
    }
    return out;
  };

  // MARK: - Item parsers (each returns one SearchItem)

  /** A list row: songs, videos, and search results of any kind. */
  const listItem = it => {
    const { menu, ...rest } = it; // menus hold mix/shuffle endpoints that aren't the item's own
    const columns = (it.flexColumns || []).map(c => c.musicResponsiveListItemFlexColumnRenderer && c.musicResponsiveListItemFlexColumnRenderer.text);
    const watch = find(rest, 'watchEndpoint');
    const list = find(rest, 'watchPlaylistEndpoint');
    const data = it.playlistItemData || {};
    return {
      style: 'row',
      title: text(columns[0]),
      subtitle: columns.slice(1).map(text).filter(Boolean).join(' • '),
      thumbnail: thumb(it.thumbnail),
      explicit: isExplicit(it),
      videoId: data.videoId || (watch && watch.videoId) || null,
      playlistId: (list && list.playlistId) || (watch && watch.playlistId) || null,
      setVideoId: data.playlistSetVideoId || null, // the entry's id within its playlist, to remove/move it
      likeStatus: (find(menu, 'likeButtonRenderer') || {}).likeStatus || null,
      playEndpoint: watch ? endpointJSON({ watchEndpoint: watch }) : null,
      mixEndpoint: mixOf(menu),
      ...libraryOf(menu),
      ...linksOf(columns.slice(1).map(c => c && c.runs)),
      ...browseInfo(it.navigationEndpoint)
    };
  };

  /** A card in a carousel or grid: albums, playlists, artists, mixes. */
  const twoRowItem = it => {
    const ep = it.navigationEndpoint || {};
    const list = ep.watchPlaylistEndpoint || find(it.thumbnailOverlay, 'watchPlaylistEndpoint');
    return {
      style: 'card',
      title: text(it.title),
      subtitle: text(it.subtitle),
      thumbnail: thumb(it.thumbnailRenderer),
      explicit: isExplicit(it),
      videoId: (ep.watchEndpoint && ep.watchEndpoint.videoId) || null,
      playlistId: (list && list.playlistId) || (ep.watchEndpoint && ep.watchEndpoint.playlistId) || null,
      playEndpoint: ep.watchEndpoint ? endpointJSON({ watchEndpoint: ep.watchEndpoint }) : null,
      mixEndpoint: mixOf(it.menu),
      ...libraryOf(it.menu),
      ...linksOf([it.subtitle && it.subtitle.runs]),
      ...browseInfo(ep)
    };
  };

  /** The big "Top result" card at the top of search results. */
  const topResultItem = c => {
    const ep = (c.title && c.title.runs && c.title.runs[0].navigationEndpoint) || c.onTap || {};
    const list = find(c.buttons, 'watchPlaylistEndpoint');
    return {
      style: 'row',
      title: text(c.title),
      subtitle: text(c.subtitle),
      thumbnail: thumb(c.thumbnail),
      explicit: isExplicit(c),
      videoId: (ep.watchEndpoint && ep.watchEndpoint.videoId) || null,
      playlistId: (list && list.playlistId) || null,
      playEndpoint: ep.watchEndpoint ? endpointJSON({ watchEndpoint: ep.watchEndpoint }) : null,
      mixEndpoint: mixOf(c.menu),
      ...libraryOf(c.menu),
      ...linksOf([c.subtitle && c.subtitle.runs]),
      ...browseInfo(ep)
    };
  };

  /**
   * Walks a response, calling add(item, sectionTitle) for every row/card it finds and
   * more(sectionTitle, browseEndpoint) for shelves that have a "See all" page.
   */
  const walk = (o, section, add, more) => {
    if (!o || typeof o !== 'object') return;
    if (Array.isArray(o)) { for (const x of o) walk(x, section, add, more); return; }

    if (o.musicCardShelfRenderer) {
      add(topResultItem(o.musicCardShelfRenderer), 'Top result');
      walk(o.musicCardShelfRenderer.contents, 'Top result', add, more);
      return;
    }
    if (o.musicShelfRenderer) {
      const shelf = o.musicShelfRenderer;
      const title = text(shelf.title) || section;
      if (more && title && shelf.bottomEndpoint && shelf.bottomEndpoint.browseEndpoint) more(title, shelf.bottomEndpoint.browseEndpoint);
      walk(shelf.contents, title, add, more);
      return;
    }
    if (o.musicCarouselShelfRenderer) {
      const shelf = o.musicCarouselShelfRenderer;
      const header = shelf.header && shelf.header.musicCarouselShelfBasicHeaderRenderer;
      const title = (header && text(header.title)) || section;
      const button = header && header.moreContentButton && header.moreContentButton.buttonRenderer;
      const ep = button && button.navigationEndpoint;
      if (more && title && ep && ep.browseEndpoint) more(title, ep.browseEndpoint);
      walk(shelf.contents, title, add, more);
      return;
    }
    if (o.musicPlaylistShelfRenderer) { walk(o.musicPlaylistShelfRenderer.contents, section, add, more); return; }
    if (o.musicResponsiveListItemRenderer) { add(listItem(o.musicResponsiveListItemRenderer), section); return; }
    if (o.musicTwoRowItemRenderer) { add(twoRowItem(o.musicTwoRowItemRenderer), section); return; }
    if (o.musicResponsiveHeaderRenderer || o.musicImmersiveHeaderRenderer) return; // parsed separately
    for (const k in o) walk(o[k], section, add, more);
  };

  /**
   * Collects items, giving each a stable id and dropping duplicates and non-actionable tiles.
   * Playlist entries are keyed by their entry id, so a song that's in a playlist twice stays twice.
   */
  const collector = () => {
    const items = [];
    const seen = new Set();
    return {
      items,
      add(item, section) {
        const key = item.setVideoId || item.videoId || item.playlistId || item.browseId;
        if (!item.title || !key) return; // e.g. the "New playlist" tile
        item.section = section;
        item.id = section + '|' + key;
        if (seen.has(item.id)) return;
        seen.add(item.id);
        items.push(item);
      }
    };
  };

  /** Follows "nextContinuationData" tokens to load further pages of a shelf or feed. */
  const nextToken = o => (find(o, 'nextContinuationData') || {}).continuation;

  // MARK: - API

  /**
   * Signed-in requests need Google's SAPISIDHASH authorization header on top of the cookies;
   * without it every call is answered anonymously (no library, no personalized results).
   */
  const authHeaders = async () => {
    const m = document.cookie.match(/(?:^|; )(?:__Secure-3PAPISID|SAPISID)=([^;]+)/);
    if (!m) return {};
    const ts = Math.floor(Date.now() / 1000);
    const digest = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(ts + ' ' + m[1] + ' ' + location.origin));
    const hex = [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
    return {
      Authorization: 'SAPISIDHASH ' + ts + '_' + hex,
      'X-Origin': location.origin,
      'X-Goog-AuthUser': String(ytcfg.get('SESSION_INDEX') || 0),
      'X-Goog-Visitor-Id': ytcfg.get('VISITOR_DATA') || ''
    };
  };

  /** POSTs to youtubei/v1/<endpoint> with the page's client context. */
  const api = async (endpoint, body) => {
    const key = ytcfg.get('INNERTUBE_API_KEY');
    const response = await fetch('/youtubei/v1/' + endpoint + '?prettyPrint=false' + (key ? '&key=' + key : ''), {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json', ...(await authHeaders()) },
      body: JSON.stringify({ context: ytcfg.get('INNERTUBE_CONTEXT'), ...body })
    });
    if (!response.ok) throw new Error('HTTP ' + response.status);
    return response.json();
  };

  // MARK: - Search & browse

  /** Search results carry no shelf titles any more, so they're grouped by their subtitle's type word. */
  const resultGroups = { Song: 'Songs', Album: 'Albums', Single: 'Albums', EP: 'Albums', Artist: 'Artists',
                         Video: 'Videos', Playlist: 'Playlists' };

  /** Filter chips (Songs, Albums, …), matched by their params prefix since their labels are localized. */
  const filterKinds = [['EgWKAQII', 'Songs'], ['EgWKAQIY', 'Albums'], ['EgWKAQIg', 'Artists'],
                       ['EgWKAQIQ', 'Videos'], ['EgeKAQQoAEAB', 'Playlists']];

  const searchFilters = json => {
    const out = {};
    for (const chip of ((find(json, 'chipCloudRenderer') || {}).chips || [])) {
      const ep = chip.chipCloudChipRenderer && chip.chipCloudChipRenderer.navigationEndpoint;
      const params = ep && ep.searchEndpoint && ep.searchEndpoint.params;
      const kind = params && filterKinds.find(([prefix]) => params.startsWith(prefix));
      if (kind) out[kind[1]] = params;
    }
    return out;
  };

  /**
   * Searches. Without `params`: all result kinds grouped by type, plus each kind's filter params
   * (for "View all"). With `params`: that kind only, listed under `section`, with `maxPages` more pages.
   */
  const search = async (query, params = '', maxPages = 0, section = '') => {
    const json = await api('search', params ? { query, params } : { query });
    const c = collector();
    if (!params) {
      walk(json.contents, null, (item, shelf) => {
        const kind = resultGroups[item.subtitle.split(' • ')[0]];
        if (shelf || kind) c.add(item, shelf || kind); // drops podcasts, episodes, profiles
      });
      return JSON.stringify({ items: c.items, filters: searchFilters(json) });
    }
    const add = item => c.add(item, section);
    walk(json.contents, section, add);
    let token = nextToken(json.contents);
    for (let i = 0; token && i < maxPages; i++) {
      const more = await api('search', { continuation: token });
      const shelf = more.continuationContents && more.continuationContents.musicShelfContinuation;
      if (!shelf) break;
      walk(shelf.contents, section, add);
      token = nextToken(shelf);
    }
    return JSON.stringify({ items: c.items });
  };

  /** The header of a browse page, in its various forms (artist, album, playlist, profile). */
  const pageHeader = json => {
    const h = json.header || {};
    return h.musicImmersiveHeaderRenderer || h.musicVisualHeaderRenderer || h.musicDetailHeaderRenderer
      || find(json.contents, 'musicResponsiveHeaderRenderer') || {};
  };

  /** Who made a page: a playlist's creator (facepile) or an album's artist (strapline). */
  const pageOwner = h => {
    const run = h.straplineTextOne && h.straplineTextOne.runs && h.straplineTextOne.runs.find(r => r.navigationEndpoint);
    const ep = (h.facepile && find(h.facepile, 'browseEndpoint')) || (run && run.navigationEndpoint.browseEndpoint);
    const owner = ep ? browseInfo({ browseEndpoint: ep }) : {};
    return {
      ownerId: owner.browseId || null,
      ownerType: owner.pageType || null,
      ownerName: (h.facepile && find(h.facepile, 'content')) || text(h.straplineTextOne) || null // all the album's artists
    };
  };

  /**
   * Opens a browse page (home, artist, album, playlist, library tab, "See all" page) and returns it
   * as a Page. Items without a shelf title go under `defaultSection`; `maxPages` follows continuations.
   */
  const browse = async (browseId, maxPages = 0, defaultSection = 'Songs', params = '') => {
    const json = await api('browse', params ? { browseId, params } : { browseId });
    const h = pageHeader(json);
    const headerThumb = thumb(h.thumbnail) || thumb(h.foregroundThumbnail);

    const c = collector();
    const add = (item, section) => {
      if (!item.thumbnail) item.thumbnail = headerThumb; // album tracks have no artwork of their own
      c.add(item, section || defaultSection);
    };
    const more = {};
    walk(json.contents, null, add, (title, b) => {
      more[title] = { browseId: b.browseId, params: b.params || null, pageType: browseInfo({ browseEndpoint: b }).pageType };
    });
    let token = maxPages > 0 ? nextToken(json.contents) : null;
    for (let i = 0; token && i < maxPages; i++) {
      const next = await api('browse', { continuation: token });
      const body = next.continuationContents || next.contents;
      walk(body, null, add);
      token = nextToken(body);
    }

    const playAll = find(h, 'watchPlaylistEndpoint') || find(h, 'watchEndpoint');
    const firstList = c.items.find(x => x.playlistId);
    const editable = find(json.contents, 'musicEditablePlaylistDetailHeaderRenderer'); // only on your own playlists
    const edit = editable && find(editable, 'musicPlaylistEditHeaderRenderer');
    // Albums and playlists keep it in a description shelf; artist headers carry plain text.
    const shelf = h.description && h.description.musicDescriptionShelfRenderer;
    const description = shelf ? text(shelf.description) : text(h.description);
    return JSON.stringify({
      title: text(h.title) || null,
      subtitle: text(h.subtitle) || null,     // e.g. "EP • 2009"
      stats: text(h.secondSubtitle) || null,  // e.g. "6 songs • 23 minutes"
      thumbnail: headerThumb,
      playlistId: (playAll && playAll.playlistId) || (firstList && firstList.playlistId) || null,
      owned: !!editable,
      privacy: (edit && edit.privacy) || null,
      description: description || null,
      more,
      ...pageOwner(h),
      ...(((h.buttons || []).map(b => libraryToggle(b.toggleButtonRenderer)).find(Boolean)) || {}),
      items: c.items
    });
  };

  /**
   * An album's release date and label, read from its tracks. YouTube's auto-generated track
   * descriptions carry them ("Released on: 2004-02-10", "℗ 2004 UMG Recordings, Inc."), but only the
   * regular YouTube client gets that description, so this asks as that client. Tracks that are
   * music videos have the artist's own description instead, so up to three tracks are tried.
   */
  const albumDetails = async videoIds => {
    const context = ytcfg.get('INNERTUBE_CONTEXT');
    for (const videoId of videoIds.slice(0, 3)) {
      const response = await fetch('/youtubei/v1/player?prettyPrint=false', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          context: { ...context, client: { ...context.client, clientName: 'WEB', clientVersion: '2.20251015.01.00' } },
          videoId
        })
      });
      const description = ((await response.json()).videoDetails || {}).shortDescription || '';
      const released = (description.match(/Released on: (\d{4}-\d{2}-\d{2})/) || [])[1] || null;
      const label = (description.match(/^℗ (.+)$/m) || [])[1] || (description.match(/^Provided to YouTube by (.+)$/m) || [])[1] || null;
      if (released || label) return JSON.stringify({ released, label });
    }
    return JSON.stringify({ released: null, label: null });
  };

  // MARK: - Account actions

  /** Raw API call; Swift builds the bodies for ratings and playlist edits. Returns the response JSON. */
  const call = async (endpoint, body) => JSON.stringify(await api(endpoint, body));

  /** Runs an endpoint taken verbatim from the web app (a library toggle). Returns 'ok' or a reason. */
  const runEndpoint = async json => {
    const ep = JSON.parse(json);
    if (ep.feedbackEndpoint) {
      const r = await api('feedback', { feedbackTokens: [ep.feedbackEndpoint.feedbackToken] });
      return (r.feedbackResponses || []).every(f => f.isProcessed !== false) ? 'ok' : 'not processed';
    }
    if (ep.likeEndpoint) {
      const like = ep.likeEndpoint;
      await api({ LIKE: 'like/like', DISLIKE: 'like/dislike' }[like.status] || 'like/removelike', { target: like.target });
      return 'ok';
    }
    return 'unsupported';
  };

  /** Your own playlists (the ones songs can be added to), as PlaylistRefs. */
  const addTargets = async videoId => {
    const r = await api('playlist/get_add_to_playlist', { videoIds: [videoId] });
    return JSON.stringify(findAll(r, 'playlistAddToOptionRenderer')
      .map(o => ({ id: o.playlistId, title: text(o.title) }))
      .filter(p => p.id && p.id !== 'LM')); // Liked songs has its own button
  };

  // MARK: - What's playing

  const player = () => document.getElementById('movie_player');
  const fromPlayer = method => {
    const p = player();
    try { return (p && p[method] && p[method]()) || null; } catch (e) { return null; }
  };
  const urlParam = key => (location.pathname === '/watch' && new URLSearchParams(location.search).get(key)) || '';

  /**
   * The playing video and the list it plays from. The address alone isn't enough: signed in, YouTube
   * Music can start a track from a browse page without moving to /watch, so the player is asked too.
   */
  const nowPlayingId = () => urlParam('v') || (fromPlayer('getVideoData') || {}).video_id || '';
  const nowPlayingList = () => urlParam('list') || fromPlayer('getPlaylistId') || '';

  // MARK: - Queue (lives only in the page, in the <ytmusic-player-queue> element's Redux store)

  const queueElement = () => document.querySelector('ytmusic-player-queue');
  const queueState = () => {
    const q = queueElement();
    return q && q.getState ? q.getState().queue : null;
  };

  /**
   * A queue entry for a track with both a song and a music-video version wraps both
   * (primaryRenderer + counterpart). Returns the one playing (by video id, then the selected flag),
   * else the primary.
   */
  const queueVersion = (entry, playingId) => {
    const wrapper = entry.playlistPanelVideoWrapperRenderer;
    if (!wrapper) return entry.playlistPanelVideoRenderer;
    const primary = wrapper.primaryRenderer && wrapper.primaryRenderer.playlistPanelVideoRenderer;
    const other = ((wrapper.counterpart || [])[0] || {}).counterpartRenderer;
    const counterpart = other && other.playlistPanelVideoRenderer;
    if (counterpart && playingId && counterpart.videoId === playingId) return counterpart;
    if (primary && playingId && primary.videoId === playingId) return primary;
    return counterpart && counterpart.selected ? counterpart : primary;
  };

  /** Index of the playing entry in the queue's own list (or -1). */
  const currentIndex = (items, playingId) => items.findIndex(entry => {
    const v = queueVersion(entry, playingId);
    return v && (v.videoId === playingId || v.selected);
  });

  /**
   * "Up next" as QueueItems: your queue, then the autoplay mix. Read from the store rather than the
   * rendered rows, which include hidden counterparts. The store's selected flag lags a track change,
   * so "now playing" is decided by the playing video id.
   */
  const queue = () => {
    const st = queueState();
    if (!st) return '[]';
    const playing = nowPlayingId();
    const seen = {};
    const out = [];
    const add = (entry, autoplay, storeIndex) => {
      const v = queueVersion(entry, playing);
      if (!v || !v.videoId) return;
      const thumbs = (v.thumbnail && v.thumbnail.thumbnails) || [];
      seen[v.videoId] = (seen[v.videoId] || 0) + 1;
      out.push({
        index: out.length, storeIndex, autoplay,
        title: text(v.title), subtitle: text(v.shortBylineText), length: text(v.lengthText),
        thumbnail: thumbs.length ? thumbs[thumbs.length - 1].url : null,
        videoId: v.videoId, occurrence: seen[v.videoId] - 1, selected: !!v.selected, explicit: isExplicit(v),
        likeStatus: (find(v.menu, 'likeButtonRenderer') || {}).likeStatus || null
      });
    };
    (st.items || []).forEach((entry, i) => add(entry, false, i));
    (st.automixItems || []).forEach((entry, i) => add(entry, true, i));
    const matches = out.filter(x => x.videoId === playing);
    const current = matches.find(x => x.selected) || matches[0];
    for (const x of out) x.selected = x === current;
    return JSON.stringify(out);
  };

  /** Plays a queue entry by clicking its visible row (hidden counterpart rows are skipped). */
  const queuePlay = (videoId, occurrence) => {
    const rows = [...document.querySelectorAll('ytmusic-player-queue-item')]
      .filter(e => e.data && e.data.videoId === videoId && e.offsetHeight > 0);
    const row = rows[occurrence] || rows[0];
    if (!row) return false;
    (row.querySelector('ytmusic-play-button-renderer, .song-info, .song-title') || row).click();
    return true;
  };

  const queueRemove = (autoplay, storeIndex) => {
    const q = queueElement();
    if (!q || !q.dispatch) return false;
    q.dispatch({ type: autoplay ? 'REMOVE_AUTOMIX_ITEM' : 'REMOVE_ITEM', payload: storeIndex });
    return true;
  };

  /**
   * Removes your queue except the playing track. The autoplay mix stays: with autoplay on, playback
   * carries on into it after this track; with it off, playback stops at the end of this track.
   */
  const queueClear = () => {
    const q = queueElement();
    const st = queueState();
    if (!q || !q.dispatch || !st) return false;
    const items = st.items || [];
    const current = currentIndex(items, nowPlayingId());
    for (let i = items.length - 1; i >= 0; i--) { // back to front, so indexes stay valid
      if (i !== current) { try { q.dispatch({ type: 'REMOVE_ITEM', payload: i }); } catch (e) {} }
    }
    return true;
  };

  /** Whether autoplay is on (the queue keeps going with similar songs after yours run out). */
  const autoplayOn = () => {
    const st = queueState();
    return !st || st.autoplay !== false;
  };

  /**
   * Turns autoplay on or off with the page's own switch (so YouTube Music remembers the choice),
   * or through the queue store if the switch isn't there.
   */
  const setAutoplay = on => {
    if (autoplayOn() === on) return true;
    const toggle = document.querySelector('#automix');
    if (toggle) toggle.click();
    else if (queueElement() && queueElement().dispatch) queueElement().dispatch({ type: 'SET_AUTOPLAY_ENABLED', payload: on });
    return autoplayOn() === on;
  };

  /**
   * Inserts a song (videoId) or a whole album/playlist (playlistId) right after the playing track
   * or at the end of your queue (before the autoplay mix), as the web app's menu does.
   * False when nothing is playing, so Swift plays it instead.
   */
  const enqueue = async (videoId, playlistId, playNext) => {
    const q = queueElement();
    const playing = nowPlayingId();
    if (!q || !q.dispatch || !queueState() || !playing) return false;
    const r = await api('music/get_queue', videoId ? { videoIds: [videoId] } : { playlistId });
    const items = (r.queueDatas || []).map(x => x.content).filter(Boolean);
    if (!items.length) return false;
    const st = queueState();
    const current = currentIndex(st.items, playing);
    q.dispatch({ type: 'ADD_ITEMS', payload: {
      nextQueueItemId: st.nextQueueItemId,
      index: playNext ? (current >= 0 ? current : st.selectedItemIndex || 0) + 1 : st.items.length,
      items, shuffleEnabled: false, shouldAssignIds: true
    } });
    return true;
  };

  // MARK: - Playback

  /**
   * Plays via the app's own router (no page reload): `endpointJson` if given (the item's own
   * request), else a request built from the ids. Resolves true once the player has the requested
   * track, false after 10 s so Swift can fall back to a full load. The first play after launch can
   * take a few seconds while the player warms up.
   */
  const play = async (videoId, playlistId, endpointJson) => {
    const app = document.querySelector('ytmusic-app');
    if (!app) return false;
    let endpoint;
    if (endpointJson) {
      endpoint = JSON.parse(endpointJson);
      const w = endpoint.watchEndpoint || endpoint.watchPlaylistEndpoint || {};
      videoId = w.videoId || '';
      playlistId = w.playlistId || '';
    } else {
      endpoint = { watchEndpoint: { ...(videoId && { videoId }), ...(playlistId && { playlistId }) } };
    }
    app.dispatchEvent(new CustomEvent('yt-navigate', { bubbles: true, composed: true, detail: { endpoint } }));

    // Either source may lag (the address can still show the previous track), so either one counts.
    const started = () => (videoId
      ? urlParam('v') === videoId || (fromPlayer('getVideoData') || {}).video_id === videoId
      : urlParam('list') === playlistId || fromPlayer('getPlaylistId') === playlistId);
    const deadline = Date.now() + 10000; // wall clock: timers are throttled while the page is hidden
    while (Date.now() < deadline) {
      await new Promise(resolve => setTimeout(resolve, 100));
      if (started()) return true;
    }
    return false;
  };

  /** Transport and volume. Prefers the player bar's own buttons and the player's API (which keep
   *  the page in sync and remember the volume), falling back to the <video> element. */
  const control = (command, value) => {
    const video = document.querySelector('video');
    const p = player();
    const click = selector => {
      const button = document.querySelector('ytmusic-player-bar ' + selector);
      if (button) button.click();
      return !!button;
    };
    switch (command) {
      case 'toggle': click('#play-pause-button') || (video && (video.paused ? video.play() : video.pause())); break;
      case 'next': click('.next-button') || (p && p.nextVideo && p.nextVideo()); break;
      case 'previous': click('.previous-button') || (p && p.previousVideo && p.previousVideo()); break;
      case 'seek': if (video) video.currentTime = value; break;
      case 'volume': // 0–100; raising it from silence also unmutes
        if (p && p.setVolume) { p.setVolume(value); if (value > 0 && p.isMuted && p.isMuted()) p.unMute(); }
        else if (video) { video.volume = value / 100; video.muted = value === 0; }
        break;
      case 'mute': // 1 mutes, 0 unmutes
        if (p && p.mute) { value ? p.mute() : p.unMute(); } else if (video) video.muted = !!value;
        break;
    }
  };

  /** The volume (0–100) and whether it's muted, from the player, else the <video> element. */
  const volumeState = () => {
    const video = document.querySelector('video');
    const volume = fromPlayer('getVolume');
    return {
      volume: typeof volume === 'number' ? volume : (video ? Math.round(video.volume * 100) : 100),
      muted: player() && player().isMuted ? !!player().isMuted() : !!(video && video.muted)
    };
  };

  // MARK: - State reporting

  /**
   * Where the playing track came from (artist, album), its mix request and library toggle, read
   * from its queue entry. Cached per video once found.
   */
  let linksFor = '';
  let links = {};
  const currentTrackLinks = videoId => {
    if (videoId === linksFor && links.found) return links;
    const st = queueState();
    let entry = null;
    for (const e of st ? [...(st.items || []), ...(st.automixItems || [])] : []) {
      const v = queueVersion(e, videoId);
      if (v && v.selected && v.videoId === videoId) { entry = v; break; }
    }
    if (!entry) { // the store isn't ready yet; try the rendered rows
      const row = [...document.querySelectorAll('ytmusic-player-queue-item')]
        .find(e => e.data && e.data.selected && e.data.videoId === videoId);
      entry = row && row.data;
    }
    const found = { found: !!entry, artistId: '', artistName: '', albumId: '', mixEndpoint: '',
                    libraryAdd: '', libraryRemove: '', inLibrary: false, explicit: isExplicit(entry) };
    if (entry) {
      Object.assign(found, libraryOf(entry.menu));
      const watch = entry.navigationEndpoint && entry.navigationEndpoint.watchEndpoint;
      found.mixEndpoint = mixOf(entry.menu) || endpointJSON({ watchEndpoint: {
        videoId, playlistId: 'RDAMVM' + videoId, params: 'wAEB',
        watchEndpointMusicSupportedConfigs: watch && watch.watchEndpointMusicSupportedConfigs
      } });
      for (const r of (entry.longBylineText && entry.longBylineText.runs) || []) {
        const b = browseInfo(r.navigationEndpoint);
        if (b.pageType === 'MUSIC_PAGE_TYPE_ARTIST' && !found.artistId) { found.artistId = b.browseId; found.artistName = r.text; }
        if (b.pageType === 'MUSIC_PAGE_TYPE_ALBUM') found.albumId = b.browseId;
      }
    }
    linksFor = videoId;
    links = found;
    return found;
  };

  /** Sends the now-playing state to Swift (Player.userContentController). */
  const post = () => {
    const videoId = nowPlayingId();
    const video = document.querySelector('video');
    const meta = navigator.mediaSession && navigator.mediaSession.metadata;
    const like = document.querySelector('ytmusic-player-bar ytmusic-like-button-renderer');
    window.webkit.messageHandlers.ytm.postMessage({
      title: (meta && meta.title) || '',
      artist: (meta && meta.artist) || '',
      artwork: meta && meta.artwork && meta.artwork.length ? meta.artwork[meta.artwork.length - 1].src : '',
      time: video ? video.currentTime : 0,
      duration: video && isFinite(video.duration) ? video.duration : 0,
      paused: video ? video.paused : true,
      videoId,
      listId: nowPlayingList(),
      likeStatus: (like && like.getAttribute('like-status')) || 'INDIFFERENT',
      autoplay: autoplayOn(),
      ...volumeState(),
      ...currentTrackLinks(videoId)
    });
  };

  // Timers are heavily throttled while the page is hidden, so state is reported from media events
  // (which keep firing during playback). Media events don't bubble, hence capture.
  let lastPost = 0;
  document.addEventListener('timeupdate', () => {
    if (Date.now() - lastPost > 400) { lastPost = Date.now(); post(); }
  }, true);
  for (const type of ['play', 'pause', 'ended', 'seeked', 'durationchange', 'loadedmetadata', 'emptied']) {
    document.addEventListener(type, () => setTimeout(post, 50), true);
  }
  setInterval(post, 1000); // when nothing is playing

  window.ytmBridge = {
    search, browse, albumDetails, play, control,
    queue, queuePlay, queueRemove, queueClear, enqueue, setAutoplay,
    call, runEndpoint, addTargets
  };
})();
