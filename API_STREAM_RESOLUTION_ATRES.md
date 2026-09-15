# Atresplayer — API & Stream Resolution Reference

Reverse-engineered from `plugin.video.atresplayerdidi` (Kodi addon: `default.py`,
`plugintools.py`). Written as a reference for building an equivalent iOS client
(AVPlayer/AVFoundation). None of this is officially documented by Atresmedia —
endpoints and payload shapes can change without notice. All endpoints below were
re-verified live against `api.atresplayer.com` while writing this document
(2026-09-15), and the exact JSON shapes quoted are real captured responses, not
guesses from the source alone.

This is a **private, undocumented API**. Treat everything here as reverse-engineered
and fragile: no versioning guarantees, no public docs, subject to breaking changes.

---

## 1. High-level flow

Unlike Mitele/Mediaset (GraphQL + a legacy scrape proxy + a multi-step signing
handshake), Atresplayer is structurally much simpler: **one plain REST/JSON API**
(`api.atresplayer.com`) backs both browsing and playback. There is no GraphQL, no
persisted-query hashes, and — critically — **no real DRM**: every manifest observed
(live and VOD) is clear HLS/DASH with no `#EXT-X-KEY` encryption tag. The complexity
in this addon is not in the API shape, it's in how the addon *authenticates* (or
rather, fails to).

```
Browsing:  GET api.atresplayer.com/client/v1/row/{id}   (paginated listing, "cards")
           GET api.atresplayer.com/client/v1/page/format/{id}   (show detail + seasons)
           GET api.atresplayer.com/client/v1/row/search?...     (generic filtered listing / search)
                              │
                              ▼
                    user picks a playable item (episode / recording / live channel)
                              │
                              ▼
Playback:  GET api.atresplayer.com/player/v1/episode/{contentId}    (series episodes)
        or GET api.atresplayer.com/player/v1/recording/{contentId}  (movies/specials, "cine")
        or GET api.atresplayer.com/player/v1/live/{channelId}?NODRM=true (live channels)
                              │
                              ▼
                    pick a `sources[]` entry → play directly, no signing/token step
```

There is no Cerbero/Gigya-style signing chain here — the `sources[].src` URLs
returned by the player endpoints are already final, playable, time-limited CDN URLs.
The catch is that **some** `player/v1/episode/{id}` calls require a logged-in session
(`required_registered`) — this addon works around that today by riding a handful of
someone else's already-logged-in session cookies rather than implementing real login
itself (§3), which is fine for a hobby addon but not something to reproduce in a
real app.

---

## 2. Base URLs & constants

| Name | Value | Used for |
|---|---|---|
| `API_BASE` | `https://api.atresplayer.com/` | All browsing + playback calls |
| Row listing | `GET {API_BASE}client/v1/row/{rowId}?size={n}&page={n}` | Curated/editorial listing ("cards") |
| Generic search/listing | `GET {API_BASE}client/v1/row/search?{filters}&size={n}&page={n}` | Category tabs (Programas, Series, Documentales, …) and free-text search |
| Format (show) page | `GET {API_BASE}client/v1/page/format/{formatId}` | Show detail: sub-rows + `seasons[]` |
| Season-scoped format page | `GET {API_BASE}client/v1/page/format/{formatId}?seasonId={seasonId}` | Resolves a season's own `id`/`title`/`description` |
| Episode player | `GET {API_BASE}player/v1/episode/{contentId}` | Series episode → `sources[]` (**sometimes login-gated**, see §3) |
| Recording player | `GET {API_BASE}player/v1/recording/{contentId}` | Movie/special ("cine") → `sources[]` (open, no login seen) |
| Live player | `GET {API_BASE}player/v1/live/{channelId}?NODRM=true` | Live channel → `sources[]`/`sourcesLive[]` (open, no login) |
| U7D hub | `GET {API_BASE}client/v1/page/u7d/{channelGroupId}` | "Últimos 7 días" (last 7 days) hub — a page of per-channel `row` links |
| Live channel list | `GET {API_BASE}client/v1/row/live` | All live channels as a normal `row` listing (itemRows/pageInfo) |

There is no client-identity header analogous to Mediaset's Apollo-iOS
`clientLibrary` block — requests just need a realistic desktop browser `User-Agent`.
The addon uses several different captured UAs across handlers (old Firefox 75/88/107,
newer Firefox 110, desktop Chrome); none of it appears to be checked strictly by the
API for browsing calls — a single modern UA works fine for all of §4's endpoints in
testing.

---

## 3. Session / authentication — the part that's actually broken

**This addon does not implement login at all.** For content that requires it, it
falls back to a hand-maintained pool of stale cookies plus a public HTTP proxy —
and as of this writing, **that entire mechanism is dead** (verified below). This is
the single most important thing to redesign, not port as-is, for iOS.

### 3.1 What actually requires a session

Testing directly against the live API (no cookies, no proxy, current UA only):

| Endpoint | Auth required? | Verified behavior |
|---|---|---|
| `player/v1/live/{channelId}` | **No** | `200`, full `sources`/`sourcesLive` back immediately |
| `player/v1/recording/{contentId}` (movies/cine) | **No** | `200`, full `sources[]` back immediately |
| `player/v1/episode/{contentId}` — news/informational content | **No** | `200` |
| `player/v1/episode/{contentId}` — regular fiction/series content | **Sometimes** | `403 {"error":"required_registered","error_description":"Required registered uer"}` (their typo, not ours) |
| `player/v1/live/{channelId}` — the `atresplayer-premium` FAST channel specifically (§17) | **Yes, paid** | `403 {"error":"required_paid","error_description":"Required paid"}` — a *different* gate than the free-registration one above; a plain `A3PSID` login session is not enough for this, it needs a paid subscription entitlement |

So gating is **per-content**, not per-endpoint, and comes in **two distinct tiers**
— `required_registered` (needs any logged-in account) and `required_paid` (needs a
paid subscription on top) — worth branching on the error code separately rather than
treating every 403 the same way. A given show's episodes may require a
free registered Atresplayer account even when the item is otherwise marked
`"visibility":"FREE"` in the browsing API — "free" apparently means "free tier",
not "no login needed". News clips and movies/specials consistently played back
unauthenticated in testing; scripted-series episodes were the ones that gated.

### 3.2 What this addon does about it (and what's actually load-bearing)

The addon's only auth handling lives in two handlers, `capitulo2()` (series
episodes — the active path from every `programas`/`temporadas`/`capitulos` menu) and
`cine_peliculas2()` (movies from the "últimos 7 días → cine" flow). Both:

1. Route the request through a **hardcoded public HTTP proxy**:
   ```python
   viva = {"http": "http://14.139.189.213:3128"}
   ```
2. Attach an `A3PSID` session cookie (Atresplayer's login cookie) via a `Cookie`
   header, and retry with up to three different cookie values until one returns
   `200`.
3. Always send a fixed `referer` pointing at an unrelated, specific captured episode
   page (`.../pongamos-que-hablo-de-sabina/temporada-1/capitulo-1-los-pecados_.../`)
   regardless of what's actually being played.

The three `A3PSID` cookies differ by call site:
- `capitulo2()` uses **three cookies hardcoded directly in `default.py`** — captured
  once, never refreshed by the addon itself.
- `cine_peliculas2()` instead fetches **two cookies at request time from two public
  Pastebin raw links** (`pastebin.com/raw/Th0mgdXX`, `pastebin.com/raw/kCKm22hH`) —
  i.e. a community-maintained, externally-refreshed pool of session cookies, the
  same pattern Mediaset's addon uses for its GMID value. A third such link
  (`pastebin.com/raw/cZRp0kgP`) appears only in commented-out dead code.

**Verified as of 2026-09-15 (corrected — see note below):**
- Testing all three of `capitulo2()`'s hardcoded cookies **directly against
  `player/v1/episode/{id}`, with no proxy at all**: `cookies1` is expired
  (`401 invalid_session`), but **`cookies2` and `cookies3` are still live, valid
  sessions** — both return `200` with a full response including `userInfo.id`
  (`cookies2`'s account even carries an active `subscriptions[].packageId`). So the
  cookie-based auth genuinely works today, and **the HTTP proxy is not required for
  it to work** — a plain authenticated request succeeds on its own.
- The Pastebin links (`cine_peliculas2()`'s cookie source) are also still alive and
  return fresh `A3PSID=...` values — someone is actively keeping that pool warm.
- The proxy IP `14.139.189.213:3128` could not be reached from the sandbox used to
  write this document (TCP connect failed on ports 80/443/3128 alike, while other
  arbitrary public IPs on port 443 connected fine) — that's more likely a
  reachability quirk of *this particular test environment* (e.g. many small open
  proxies block known cloud/datacenter IP ranges to cut down on abuse) than proof
  the proxy is offline in general. Since real playback was confirmed working on a
  normal device/network, treat the proxy as **unverified from here, not disproven**
  — don't repeat the earlier, over-confident claim that it's dead.

**What this actually means**: the gating behavior in §3.1 is real and reproducible,
and the addon's cookie-based workaround genuinely lets it through *when a cookie in
the pool happens to still be valid* — which, empirically, is the common case right
now (2 of 3 hardcoded values, plus a separately-refreshed pastebin pool). The
proxy's role is unclear — it may be legacy/vestigial (kept from an earlier version
where it mattered, e.g. if a prior cookie was IP-bound, or simply copy-pasted from
another addon in the same family), since a direct, proxy-free request with a valid
cookie already succeeds in testing.

### 3.3 The real concern this raises: shared personal session cookies

`cookies2`'s response includes `"subscriptions":[{"packageId":6880960}]` — that is
**someone's real, currently-active Atresplayer account**, with its session token
hardcoded into a publicly-distributed Kodi addon that anyone can install and use to
play gated content as that account. Whether or not the proxy does anything useful,
this is the actual mechanism making series playback work: every install of this
addon is riding on a small number of shared, real people's login sessions. That's
worth knowing regardless of the iOS port, since:
- Those sessions will eventually rotate/expire (same as `cookies1` already has), at
  which point series playback silently breaks again until someone edits new values
  into the source (or the pastebin pool, for the movie path).
- It's the account owner's session being spent on everyone else's behalf — not
  something to replicate as a real product's auth strategy.

### 3.4 Recommendation for the iOS port

- **Don't port the HTTP proxy** — it doesn't appear to be necessary for the request
  to succeed (a valid cookie alone was sufficient in direct testing), and its
  presence/reachability couldn't be confirmed independently either way.
- **Don't port hardcoded shared session cookies** either, for the reason in §3.3 —
  fine for a hobby Kodi addon, not something to build an app's auth on.
- Call `player/v1/episode/{id}` **directly, unauthenticated, first** for every menu
  item. Most content (movies, live, news, and plenty of series episodes marked
  "free chapter") plays immediately with a `200`; some series episodes will come
  back `403 required_registered`.
- For the `403` case, you need a real per-user session the same way the official
  app gets one: implement Atresplayer's actual login (email/password → `A3PSID`
  cookie). This addon never captures or reverse-engineers that login flow itself —
  it only ever borrows other people's already-issued cookies — so the login
  handshake itself is **not covered by this document**; a fresh capture of
  `www.atresplayer.com`'s real login network traffic would be needed.
- Treat `A3PSID` purely as a cookie header on the player request, nothing more — no
  signing, no token exchange, unlike Mediaset's Gigya/Cerbero chain.

---

## 4. Browsing API (REST, not GraphQL)

### 4.1 Row listing — `GET /client/v1/row/{rowId}?size={n}&page={n}`

The single workhorse endpoint behind almost every menu item. Response shape
(captured live):

```json
{
  "type": "VERTICAL_FORMAT",
  "title": "Originales ViX",
  "href": "https://api.atresplayer.com/client/v1/row/{rowId}",
  "itemRows": [ { "...": "one card per item, shape depends on type — see below" } ],
  "pageInfo": {
    "totalElements": 74, "totalPages": 37, "pageNumber": 0,
    "hasNext": true, "hasPrevious": false, "first": true, "last": false
  },
  "rowSize": "M"
}
```

Pagination is **page-number based**, not cursor-based: `page` is a plain 0-based
integer, `pageInfo.hasNext` tells you whether to fetch `page+1`. This is simpler than
Mediaset's GraphQL cursor pagination — no opaque `endCursor` to carry around.

Card shape varies by the underlying entity but always includes `title`, `image`,
`link`, `type`, `contentId`. Two shapes matter for playback:

**FORMAT card** (a show — series/program):
```json
{
  "title": "Polen",
  "image": { "pathHorizontal": "https://imagenes.atresplayer.com/.../", "pathVertical": "..." },
  "link": { "url": "/vix/series/polen/", "href": "https://api.atresplayer.com/client/v1/page/format/{formatId}", "pageType": "FORMAT" },
  "type": "FORMAT",
  "contentId": "6a30011c98857800075b56c0",
  "formatId": "6a30011c98857800075b56c0",
  "ageRating": "PLUS_16", "category": "Series", "genre": "Drama",
  "description": "..."
}
```
`contentId` == `formatId` for FORMAT cards — tapping navigates into §4.2 using
`formatId`.

**RECORDING card** (a movie/special — "cine"):
```json
{
  "title": "Annabelle vuelve a casa",
  "image": { "pathHorizontal": "...", "pathVertical": "..." },
  "link": { "url": "/grabaciones/lasexta/{id}/", "href": "https://api.atresplayer.com/client/v1/page/recording/{id}", "pageType": "RECORDING" },
  "type": "RECORDING",
  "contentId": "6aa8983f5436990007e07649",
  "mainChannel": "...", "startTime": 1789427100000
}
```
`contentId` here is fed straight into `GET player/v1/recording/{contentId}` (§6) —
no intermediate detail page needed, this is a flat, directly-playable catalog.

**LIVE card** (from `GET /client/v1/row/live`):
```json
{
  "title": "Espejo Público",
  "link": { "url": "/directos/antena3/", "href": "https://api.atresplayer.com/client/v1/page/live/{channelId}", "pageType": "LIVE_CHANNEL" },
  "type": "LIVE",
  "contentId": "5a6a165a7ed1a834493ebf6a",
  "mainChannel": "5a6a165a7ed1a834493ebf6a",
  "startTime": 1789455300000, "endTime": 1789471200000,
  "nextProgram": "Cocina abierta de Karlos Arguiñano",
  "formatId": "5a78761d986b28066d9cde83",
  "logoURL": "https://imagenes.atresplayer.com/.../logo.png"
}
```
`contentId`/`mainChannel` (same value) is the **channel id** fed into
`GET player/v1/live/{channelId}?NODRM=true` (§7). `link.url`'s last path segment
(`antena3`) is the human-readable channel slug, used only for display.

⚠️ **Note on how the addon actually reads this**: several handlers (`sietedias`,
`tv_atresmedia`, `cine_peliculas`, `cine`, `buscador`) do **not** `json.loads()` the
response — they call `.decode('utf-8')` on the raw body and then run hand-written
regexes over the raw JSON text to pull out fields positionally (e.g.
`'{"title":".*?".*?pathHorizontal":".*?".*?url":".*?startTime'`). This still works
today only because the field *order* in the API's JSON serialization hasn't changed;
it is not a stable contract and should not be replicated in Swift. The **only**
handlers that parse this response as real JSON are `programas()` and `capitulos()`
(marked `# DONE #` in the source — the modern, actively-maintained implementations;
everything else, including large commented-out blocks of superseded regex code left
in place, predates that rewrite). **For iOS: always decode JSON properly** — treat
the regex-scraping style as legacy debt, not a pattern worth keeping.

### 4.2 Format (show) detail — `GET /client/v1/page/format/{formatId}`

```json
{
  "id": "6a30011c98857800075b56c0",
  "title": "Polen",
  "description": "...",
  "rows": [ /* sub-rows: Capítulos, Secciones, Clips, Extras, Contenido Relacionado, ... — each an href back into §4.1 */ ],
  "seasons": [
    {
      "title": "Temporada 1",
      "link": {
        "url": "/vix/series/polen/temporada-1/",
        "href": "https://api.atresplayer.com/client/v1/page/format/6a30011c98857800075b56c0?seasonId=6a30012798857800075b56c7",
        "pageType": "SEASON"
      }
    }
  ],
  "ageRating": "PLUS_16", "category": "Series", "genre": "Drama",
  "productionYear": "...", "claim": "Primer capítulo en abierto"
}
```
`seasons[]` has **no season id field of its own** — the id is embedded in
`link.href`'s `seasonId` query parameter. To get a season's own `id`/`title`/
`description` (needed for the episode-listing call in §4.3), **re-fetch that exact
`link.href` URL** — the response is the *same* format-page shape, but scoped:
`id` on the response now equals the season's id (confirmed:
`GET .../format/{formatId}?seasonId=X` → `{"id": "X", "title": "Temporada 1", ...}`),
and it carries its own nested `seasons` array (harmless to ignore at this point).

### 4.3 Episode listing for a season — `GET /client/v1/row/search?entityType=ATPEpisode&formatId={formatId}&progress=true&seasonId={seasonId}&size={n}&page={n}`

Same envelope as §4.1 (`itemRows`/`pageInfo`, page-number pagination). Episode item
shape:
```json
{
  "title": "Capítulo 1: Reina Muerta",
  "subTitle": "Polen",
  "image": { "pathHorizontal": "...", "pathVertical": "..." },
  "link": { "url": "/vix/series/polen/temporada-1/capitulo-1-reina-muerta_.../", "href": "https://api.atresplayer.com/client/v1/page/episode/{contentId}", "pageType": "EPISODE" },
  "type": "EPISODE",
  "contentId": "6a30014598857800075b56ce",
  "visibility": "FREE",
  "description": "...",
  "open": true,
  "claim": "Primer capítulo en abierto",
  "linkFormat": { "href": "https://api.atresplayer.com/client/v1/page/format/{formatId}", "pageType": "FORMAT" }
}
```
`contentId` is what gets passed to `GET player/v1/episode/{contentId}` (§6). Note
`visibility: "FREE"` does **not** guarantee unauthenticated playback — see §3.1.

### 4.4 Generic filtered listing / search — `GET /client/v1/row/search?entityType=ATPFormat&sectionCategory=true&mainChannelId={channelId}&categoryId={categoryId}&sortType={AZ|THE_MOST}&size={n}&page={n}`

This is the endpoint behind almost every top-level menu category (Programas,
Series, Telenovelas, Informativos, Infantil, Documentales, Cine, …) — they are the
**same call**, parameterized only by a hardcoded `categoryId` (and sometimes
`mainChannelId`/`sortType`). Free-text search (`buscador()`) is the same endpoint
family with `entityType=ATPFormat&text={query}` instead of a `categoryId`. Response
envelope and FORMAT card shape are identical to §4.1/§4.2's flow — every result
feeds into the same `temporadas`→`capitulos`→`capitulo2` pipeline (§8).

### 4.5 "Últimos 7 días" hub — `GET /client/v1/page/u7d/{channelGroupId}`

```json
{
  "title": "U7D",
  "rows": [
    { "id": "61a4ec856584a8b8ac996055", "type": "VERTICAL_U7D", "title": "Cine", "href": "https://api.atresplayer.com/client/v1/row/61a4ec856584a8b8ac996055" },
    { "id": "61c1a87f4beb28ef4fc9d816", "type": "U7D", "title": "Antena 3", "href": "https://api.atresplayer.com/client/v1/row/61c1a87f4beb28ef4fc9d816" }
  ]
}
```
Each `rows[].href` is a normal §4.1 row listing of **RECORDING cards** (last 7 days
of that channel's output) — same flat, directly-playable catalog shape as §4.1's
RECORDING example, feeding `player/v1/recording/{contentId}` (§6).

---

## 5. Live channel list

`GET /client/v1/row/live` returns a normal §4.1 row listing of LIVE cards — this is
a real, clean JSON endpoint (unlike Mediaset, which has to scrape HTML for this).
The addon still regex-scans the raw body instead of parsing JSON (§4.1's caveat
applies), but there's no technical reason for that on iOS — just parse `itemRows`
normally and map each LIVE card as in §4.1.

---

## 6. VOD episode/recording stream resolution

Both series episodes and movies/recordings converge on the same shape of response;
only the endpoint and the auth situation differ (§3.1).

```
GET player/v1/episode/{contentId}        (series)
 or
GET player/v1/recording/{contentId}      (movies/specials)
   │
   ▼
{
  "id": "...", "titulo": "...", "duration": 6845, "ageRating": "PLUS_16",
  "sources": [
    { "src": "https://.../hls.smil/playlist.m3u8?pulse=...", "type": "application/vnd.apple.mpegurl" },
    { "src": "https://.../dash.smil/manifest_mvtime.mpd",    "type": "application/dash+xml" },
    { "src": "https://.../smooth.smil/playlist.m3u8?pulse=...", "type": "application/hls+legacy" },
    { "src": "https://.../dash.smil/manifest_mvtime_vo.mpd", "type": "application/dashvo+xml" }
  ]
}
```

The addon's active picker (`capitulo2()`) selects the entry whose `type` contains
`"hls+legacy"`:
```python
url = [d for d in sources if "hls+legacy" in d.get("type")][0].get("src")
```
This is a slightly odd choice — `"application/vnd.apple.mpegurl"` (the first entry)
is the more standard/native HLS type for AVPlayer, and both point at equivalent
content (`hls.smil` vs `smooth.smil` variants of the same asset in testing). **For
iOS, prefer `"apple.mpegurl"` over `"hls+legacy"`** — AVPlayer natively understands
standard HLS; there's no reason to special-case the legacy-labeled variant, and using
the standard one avoids depending on an oddly-named type string that could be an
implementation detail of Atresmedia's older packager.

These URLs are already final and playable — **no signing/token exchange step**,
unlike Mediaset. They do carry an expiring `pulse=` query token embedded by the CDN,
so — same rule as always — resolve at play-time, don't cache long-term.

### 6.1 Getting there for a series episode

```
programas (row/search or row/{id})  →  format page (§4.2)  →  seasons[]
   →  re-fetch season link.href to get its own {id}  →  episode listing (§4.3)
   →  contentId  →  GET player/v1/episode/{contentId}
```

### 6.2 Getting there for a movie/recording ("cine")

```
any RECORDING-card listing (§4.1 / §4.5)  →  contentId  →  GET player/v1/recording/{contentId}
```
Flat — no season/episode hierarchy, directly playable from the catalog row, same
structural pattern as Mediaset's "Documentales" (a flat single-video catalog).

### 6.3 What the addon actually does differently (and why not to copy it)

Neither `capitulo2()` nor `cine_peliculas2()` calls the player endpoint directly with
a plain `requests.get()`. Both wrap the call in the proxy/cookie dance from §3.2, and
`cine_peliculas2()` additionally applies a blind regex
(`'src":"(.*?m3u8.*?)"'`, first match only, `.replace('drm','')`) instead of picking
a `sources[]` entry by type. Since (a) most of this content plays back fine
unauthenticated, and (b) even the gated case was confirmed to work with just a valid
cookie and no proxy, **the correct simplification for iOS is to skip §3.2's proxy
entirely** and call the player endpoints directly with a cookie header when needed,
falling back to a real login only on `403 required_registered` — see §3.3/§3.4 for
why the specific hardcoded cookies shouldn't be carried over as-is.

---

## 7. Live channel stream resolution

```
GET player/v1/live/{channelId}?NODRM=true
```
No cookies, no proxy — confirmed working unauthenticated. Response:
```json
{
  "id": "5a6a165a7ed1a834493ebf6a",
  "titulo": "Espejo Público",
  "live": true,
  "sources": [ { "src": "", "type": "application/vnd.apple.mpegurl" } ],
  "sourcesLive": [
    { "src": "https://atres-live.atresmedia.com/{token}/hlsts/live/antena3_usp/antena3_usp.isml/playlist.m3u8", "type": "application/vnd.apple.mpegurl" },
    { "src": "https://atres-live.atresmedia.com/{token}/hlslegacy/live/antena3_usp/antena3_usp.isml/playlist.m3u8", "type": "application/hls+legacy" },
    { "src": "https://atres-live.atresmedia.com/{token}/dasht/live/antena3_usp/antena3_usp.isml/manifest.mpd", "type": "application/dash+xml" },
    { "src": "https://atres-live-ssai.atresmedia.com/{token}/hlsts/live/antena3_usp/antena3_usp.isml/master.m3u8", "type": "application/hls+ssai" },
    { "src": "https://atres-live-ssai.atresmedia.com/{token}/dasht/live/antena3_usp/antena3_usp.isml/manifest.mpd", "type": "application/dash+ssai" }
  ],
  "sourcesStartOver": [ /* same shape, time-shifted "start over" variants */ ]
}
```
Note `sources[0].src` is **empty** for live — the real manifest is in
`sourcesLive[]`, not `sources[]` (this is why the addon's regex specifically targets
`"sourcesLive":.{"src":"(.*?)"` rather than reusing the VOD `sources` picker).
The addon takes `sourcesLive[0]` (the plain, non-SSAI HLS variant) — a reasonable
default for iOS too, since the `-ssai` variants are server-side-ad-insertion streams
that splice in ad breaks server-side (fine to use, just a product decision, not a
technical requirement).

`sourcesStartOver[]` (time-shifted / "start from the beginning of the current
program") exists in the response but is unused by this addon — worth considering for
the iOS app since it's already available for free from the same call.

Getting a `channelId`: from any LIVE card in §4.1/§5 (`contentId`/`mainChannel`).

---

## 8. Subtitle resolution

`get_subtitles()` in `default.py` is used only by the series-episode path
(`capitulo2()`). It manually parses the HLS master playlist rather than using any
API field (there is no `subtitles` field in the player JSON at all — everything
subtitle-related lives inside the HLS manifest's `EXT-X-MEDIA` tags):

```python
def get_subtitles(sources):
  s = [d for d in sources if "apple.mpegurl" in d.get("type")]
  link = s[0].get("src")                       # the master playlist
  r = requests.get(link)
  for l in r.text.split("\n"):
    if "type=subtitles" in l.lower():
      sublink = dict([tuple(v.split("=")) for v in l.split(",")]).get("URI")
      sublink = "/".join(link.split("/")[:-1]) + "/" + sublink.replace('"', "")
      r2 = requests.get(sublink)
      return ["/".join(sublink.split("/")[:-1]) + "/" +
              [l for l in r2.text.split("\n") if not l.startswith("#EXT")][0]]
```

Confirmed live shape of the relevant master-playlist line:
```
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subt",LANGUAGE="es",NAME="Spanish",DEFAULT=YES,URI="../es_subt.vtt"
```

**⚠️ Verified bug**: the `URI` is frequently a **relative path containing `..`**
(as above). The code resolves it with naive string concatenation
(`dirname(link) + "/" + uri`), which does **not** collapse `..` — sending that literal
URL to the CDN returns `404`. Properly resolving it as a relative URL (i.e.
`urljoin(link, uri)` in Python, or `URL(string:relativeTo:)` in Swift) correctly
collapses the path and returns `200` with a tiny sub-playlist:
```
#EXTM3U
#EXT-X-TARGETDURATION:6845
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:6845.00000,
es.vtt
```
whose last non-`#EXT` line (`es.vtt`), resolved the same way relative to *that*
playlist's own URL, is the final playable WebVTT file. **For iOS: use proper
relative-URL resolution (`URL(string:relativeTo:)`) at both steps** — do not port the
naive string-concatenation approach; it will silently produce dead subtitle URLs for
exactly the manifests that use `../`-relative subtitle URIs (which, empirically, is
the common case for VOD content here).

Live channels' subtitle track (§7) uses a same-directory URI
(`antena3_usp-textstream_spa=0.m3u8`, no `..`) in testing, so the bug wouldn't
manifest there — but implement the general case correctly regardless, since it costs
nothing extra.

---

## 9. DRM note (short, because there isn't one)

Every manifest fetched during this investigation — live and VOD, HLS and DASH — was
**plain, unencrypted**: no `#EXT-X-KEY` tag anywhere. Unlike Mediaset (which has a
real FairPlay-protected variant sitting alongside a clear one), Atresplayer appears
to serve everything clear at the transport level for this addon's use case. That
means: **no FairPlay, no `AVContentKeySession`, no license server integration needed**
for the iOS port — plain `AVURLAsset`/`AVPlayerItem` is sufficient. (This could
differ for 4K/premium tiers not exercised here — the addon and this investigation
only ever hit the default/free quality tier.)

---

## 10. Headers

Requests observed to work without any special headers beyond a normal desktop
`User-Agent` for **every** endpoint in §4–§7 (browsing, all three player endpoints,
manifests, and subtitle files) — no `Referer`/`Origin`/`Accept` requirements were
found necessary in direct testing, despite the addon sending various legacy ones out
of habit (`Accept-Language`, a fixed unrelated `Referer` for the auth-hack calls).
For the iOS port, a single modern UA is enough:

```swift
let headers = [
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/106.0.0.0 Safari/537.36"
]
let asset = AVURLAsset(url: manifestURL, options: [
    "AVURLAssetHTTPHeaderFieldsKey": headers
])
```
Kodi's `|user-agent=...` pipe-suffix convention (used throughout `default.py` via
`plugintools.play_resolved_url`) is Kodi-specific — don't send it to AVPlayer, set
the header via `AVURLAssetHTTPHeaderFieldsKey` as above (same caveat as the Mediaset
doc: this reliably covers the manifest request; if segment requests ever need it too,
verify or use a custom `AVAssetResourceLoaderDelegate`).

---

## 11. Full navigation menu map

Every entry in `main_list()` (`default.py`), what it routes to, and which underlying
mechanism backs it:

| Menu label | Handler | Backing mechanism | Notes |
|---|---|---|---|
| Buscador (search) | `buscador` | §4.4 search | Free-text `entityType=ATPFormat&text=...`; **uses raw regex parsing**, not JSON (§4.1 caveat) |
| Últimos 7 días | `sietedias` → `cine_peliculas` | §4.5 U7D hub → row listing | Per-channel recent recordings; **regex parsing** |
| TV de Atresmedia en directo | `tv_atresmedia` → `playdirect` | §5 live list → §7 live player | The only fully-working VOD/live playback path that avoids the broken auth hack entirely |
| Originales ViX / Estrenos ViX / Añadido recientemente / Preestrenos / Clásicos / Vix telenovelas | `programas` | §4.1 curated row listing, hardcoded row id | Same handler, different hardcoded `rowId` per menu entry |
| Programas / Series / Informativos / Telenovelas / Infantil / Documentales | `programas` | §4.4 category search, hardcoded `categoryId` | Same handler again, different hardcoded `categoryId`/`sortType` |
| Cine | `menu_cine` → `cine_peliculas`/`programas` | §4.1 row + §4.4 search | Sub-menu: "últimos 7 días" (flat recordings) vs "todas las películas" (FORMAT catalog through the season/episode pipeline — inconsistent with how movies are usually flat). Both route gated playback through the §3.2 cookie/proxy mechanism |
| Telenovelas Nova | `novelas_nova` → `programas` | §4.1 curated rows | Sub-menu of 4 more hardcoded row ids |
| Kidz | `kidz` → `programas` | §4.1 curated rows | Sub-menu of 5 more hardcoded row ids, same pattern |

**Important structural insight**: unlike Mediaset (which has ~5 structurally
distinct category pipelines), Atresplayer effectively has **two**: (1) the FORMAT
pipeline — `programas` → `temporadas` → `capitulos` → `capitulo2`, used by nearly
every menu entry including Cine's "todas las películas" — and (2) the flat RECORDING
pipeline — a row listing whose cards are directly playable via
`player/v1/recording/{id}`, used by "últimos 7 días" and U7D per-channel rows. Live
TV is a third, much shorter pipeline. Every single main-menu entry is one of these
three, parameterized only by a hardcoded id/query string — there is no case in this
addon (unlike Mediaset's Miniseries) with a genuinely different data shape to
support.

---

## 12. Category deep-dive: the shared FORMAT pipeline

This is the pipeline behind the large majority of the menu (§11), so it's worth
walking once in full, end to end, with real ids from this session:

1. **Catalog** (`programas()`): `GET row/{id}` or `GET row/search?...`, page-number
   paginated (§4.1/§4.4) → FORMAT cards, each with `formatId`.
2. **Seasons** (`temporadas()`): `GET page/format/{formatId}` → `seasons[]`, each
   with only a `link.href` containing `?seasonId=X`; re-fetch each `link.href` to get
   that season's own `id`/`title`/`description` (§4.2).
3. **Episodes** (`capitulos()`): `GET row/search?entityType=ATPEpisode&formatId={formatId}&seasonId={seasonId}&size=100&page={n}` → episode cards with `contentId` (§4.3), page-number paginated.
4. **Playback** (`capitulo2()`): `GET player/v1/episode/{contentId}` → pick a
   `sources[]` entry (§6), resolve subtitles (§8).

### 12.1 Verified bug: broken pagination past page 0

`capitulos()` builds its "next page" list item like this:
```python
def capitulos(params):
    page_number = params.get("extra")
    season_id = params.get("url")
    ...
    if pageInfo.get("hasNext"):
        nextPage = str(int(page_number) + 1)
        plugintools.add_item(
            action="capitulos",
            ...
            url=seasonId,     # <-- NameError: only `season_id` (snake_case) is defined
            extra=nextPage,
            folder=True
        )
```
`seasonId` is never assigned anywhere in this function — only `season_id` is. Since
episode pages are fetched at `size=100`, this only triggers for a season with more
than 100 episodes (rare, but e.g. long-running telenovelas/daily shows could hit it),
and when it does, tapping "next page" raises `NameError` in the addon. Not a
subtlety to preserve — just fix the variable name (or, for iOS, use cursor-free
page-number pagination correctly, which this bug has nothing to do with structurally).

---

## 13. Category deep-dive: flat RECORDING pipeline ("cine" / U7D)

Used by "Últimos 7 días" and the U7D per-channel rows (§4.5), and by Cine's
"últimos 7 días" sub-item. Flat, single-step:

```
row listing (§4.1, RECORDING cards)  →  contentId  →  player/v1/recording/{contentId}  →  sources[]
```

No season/episode hierarchy — every row item is immediately playable, same
structural shape as Mediaset's "Documentales" flat catalog. This is the pipeline
whose live implementation (`cine_peliculas`/`cine_peliculas2`) is currently broken
per §3.2/§6.3 — recommend implementing it as the clean two-step call above instead.

---

## 14. Cross-pipeline summary table

| Category | Catalog fetch | Detail chain | Terminal playable entity | Auth mechanism used by the addon |
|---|---|---|---|---|
| Programas / Series / Telenovelas / Infantil / Documentales / Informativos / Kidz / most of the root menu | §4.1 row or §4.4 search, hardcoded id | Seasons → episodes, all REST JSON (§12) | Episode `contentId` → `player/v1/episode` (§6) | Always routes through the §3.2 proxy + one of 3 hardcoded cookies, even for ungated episodes that don't need it at all |
| Cine → "todas las películas" | §4.4 search (FORMAT, categoryId = cine) | Same as above | Same as above | Same as above |
| Cine → "últimos 7 días" / Últimos 7 días hub | §4.1/§4.5 row (RECORDING cards) | None — flat | `contentId` → `player/v1/recording` (§6) | Same proxy, cookies pulled live from two Pastebin links instead of hardcoded |
| TV de Atresmedia en directo | §5 row listing (LIVE cards) | None | `channelId` → `player/v1/live` (§7) | None — no cookie/proxy involved, works fully unauthenticated |

The practical takeaway for the iOS port: **rebuild all VOD playback (episodes and
recordings) as a direct call to the respective player endpoint**, unauthenticated
first, with a cookie attached only when a `403 required_registered` comes back —
matching how live already works unauthenticated in this addon. Don't carry over
§3.2's proxy (unnecessary in testing) or its hardcoded shared cookies (§3.3, a real
account-sharing concern, not just a technical shortcut).

---

## 15. Fragility / things to watch when porting

- **The proxy/cookie auth hack (§3) works today, but rests on borrowed sessions** —
  2 of 3 hardcoded cookies and both pastebin-sourced ones tested valid live, and the
  proxy wasn't shown to be necessary for that success. Any port should replace it
  with direct unauthenticated calls plus a real, per-user login flow for the
  `403 required_registered` case — not because the current mechanism is broken, but
  because it depends on a handful of real people's shared account sessions (§3.3)
  that will keep rotating out from under the addon exactly like `cookies1` already
  has.
- **Per-content auth gating is inconsistent** — `visibility: "FREE"` in the browsing
  API does not predict whether `player/v1/episode/{id}` will demand a session.
  Always try unauthenticated first and branch on the response, don't pre-guess.
- **Live pastebin cookie pool (§3.2)** is an external, informally-maintained
  dependency (same pattern as Mediaset's GMID pastebins) — confirmed alive at time
  of writing, but depending on someone else's pastebin staying alive, honest, and
  legally shareable is not something to build a real app on.
- **Mixed regex-vs-JSON parsing** across handlers (§4.1) — only `programas()`/
  `capitulos()` are modern; several other still-active handlers (`sietedias`,
  `tv_atresmedia`, `cine_peliculas`, `cine`, `buscador`) regex-scan raw JSON text.
  Fragile, but happens to work today because field order hasn't changed. Parse JSON
  properly on iOS regardless.
- **Subtitle relative-URL bug (§8)** — naive string concatenation instead of proper
  relative-URL resolution breaks on any `../`-relative `URI` in the HLS master
  playlist, which is the common case for VOD subtitles here.
- **`capitulos()` pagination bug (§12.1)** — `NameError` on an undefined `seasonId`
  variable when a season has more than 100 episodes. Only reachable in edge cases,
  but confirms this code path isn't exercised/tested by its author beyond page 0.
- **No DRM anywhere observed (§9)** — good news for the port, but not guaranteed to
  hold for every quality tier/content class forever; verify DRM-free assumption
  periodically, especially if a "premium" tier is added to the app.
- The `type: "hls+legacy"` entry the addon prefers (§6) is an odd choice over the
  standard `"apple.mpegurl"` entry sitting right next to it — no evidence either is
  more reliable, but the standard type is the safer long-term bet for AVPlayer.

---

## 16. Known gaps worth a product decision before porting

- **Real Atresplayer login is not implemented anywhere in this addon.** If the iOS
  app needs to play gated series content reliably, this requires a fresh capture of
  `www.atresplayer.com`'s actual login flow (likely email/password → some identity
  provider → `A3PSID` cookie) — out of scope of what this addon's source reveals.
- **Live "start over" streams** (`sourcesStartOver[]`, §7) are already returned by
  the live player endpoint but unused by this addon — worth adding to the iOS app
  as a "restart this program" feature since it's free (no extra API call).
- **Premium/4K content** was not exercised in this investigation (no logged-in
  session was available) — the "no DRM" finding (§9) is based only on the
  default/free tier actually reachable here; don't assume it extends to a paid tier
  without checking.
- **Cine's "todas las películas" going through the season/episode FORMAT pipeline**
  instead of the flat RECORDING pipeline (§11) looks like a data-modeling
  inconsistency on Atresmedia's side (some "movies" are actually FORMAT/series-shaped
  entities with a single season/episode) rather than an addon bug — confirm this is
  intentional before assuming all "movie" content is flat.
- **Whose account is this, and are they okay with it being shared?** The hardcoded
  cookies (§3.3) belong to real people who are presumably unaware their session is
  embedded in a public Kodi addon. Before building any equivalent "borrow a session"
  shortcut into a real app, this is a product/ethics decision, not just a technical
  one — the sustainable answer is every user logging in with their own account.

---

## 17. Live channel reference (ready to hardcode)

Captured live from `GET client/v1/row/live` + `GET client/v1/page/live/{id}` per
channel (2026-09-15) — **18 channels total**. `contentId` is the value to hardcode
as `channelId` and feed straight into
`GET player/v1/live/{channelId}?NODRM=true` (§7). Unlike category ids (§18), these
are stable channel identities, not likely to change — safe to ship as a static list
in the app and still hit `client/v1/row/live` periodically to catch additions/removals
or "now playing" metadata.

| channelId (`contentId`) | slug | Display name | Kind | Start-over | Auth gate |
|---|---|---|---|---|---|
| `5a6a165a7ed1a834493ebf6a` | `antena3` | Antena 3 | Main linear channel | Yes | None |
| `5a6a172c7ed1a834493ebf6b` | `lasexta` | La Sexta | Main linear channel | Yes | None |
| `5a6a17da7ed1a834493ebf6d` | `neox` | Neox | Main linear channel | Yes | None |
| `5a6a180b7ed1a834493ebf6e` | `nova` | Nova | Main linear channel | Yes | None |
| `5a6a18357ed1a834493ebf6f` | `mega` | Mega | Main linear channel | Yes | None |
| `5a6a189a7ed1a834493ebf70` | `atreseries` | Atreseries | Main linear channel | Yes | None |
| `5c1285e47ed1a861f8125285` | `canal-flooxer` | Flooxer | FAST/thematic channel | No | None |
| `648ef12c2bfab0e4507e0d61` | `clasicos` | Clásicos | FAST/thematic channel | No | None |
| `648c271d2bfab0e4177a0d61` | `canal-kidz` | Kidz | FAST/thematic channel | No | None |
| `648ef3951756b0e425af83cc` | `aqui-no-hay-quien-viva` | Aquí no hay quien viva | FAST/single-show channel | No | None |
| `648ef5882bfab0e4627e0d61` | `el-hormiguero` | El Hormiguero | FAST/single-show channel | No | None |
| `648ef5551756b0e429af83cc` | `equipo-de-investigacion` | Equipo de Investigación | FAST/single-show channel | No | None |
| `648ef50a2bfab0e4607e0d61` | `foq` | Física o Química | FAST/single-show channel | No | None |
| `648f47f7a2ffb0e40aeff3ad` | `el-club-de-la-comedia` | El Club de la Comedia | FAST/single-show channel | No | None |
| `648ef18c1756b0e41daf83cc` | `multicine` | Multicine | FAST/thematic channel | No | None |
| `648ef23d2bfab0e4557e0d61` | `comedia` | Comedia | FAST/thematic channel | No | None |
| `648ef3162bfab0e4587e0d61` | `mentes-inquietas` | Mentes Inquietas | FAST/thematic channel | No | None |
| `6107d2846584a82b1f0eb800` | `atresplayer-premium` | Atresplayer Premium | Premium channel | Unknown (not tested — see below) | **Paid** — `403 required_paid` (§3.1), a plain login is not enough |

Notes:
- `title`/`logoURL` returned by `client/v1/row/live` describe the **current
  program**, not the channel itself (e.g. `antena3`'s row entry shows "Espejo
  Público", its live talk show at capture time) — for a stable channel name, use
  `GET client/v1/page/live/{channelId}` and read its `title` field (returns e.g.
  `"Antena 3 en directo"` — strip the `" en directo"` suffix for a clean display
  name), not the row listing's `title`.
- The six **main linear channels** (Antena 3, La Sexta, Neox, Nova, Mega,
  Atreseries) are the actual over-the-air TV channels and support start-over
  (`sourcesStartOver[]` in the player response, §7, plus `startOver: true` on the
  `page/live` response).
- The remaining channels are **FAST (Free Ad-supported Streaming TV) channels** —
  single-theme or single-show 24/7 loops (Flooxer, Clásicos, Kidz, Multicine,
  Comedia, Mentes Inquietas) or channels built around one specific show looping
  (Aquí no hay quien viva, El Hormiguero, Equipo de Investigación, FoQ, El Club de
  la Comedia). All confirmed playable unauthenticated in testing, same
  `player/v1/live/{id}?NODRM=true` call as the main channels — just no start-over.
- `atresplayer-premium` is the odd one out: it requires a **paid** subscription
  (`required_paid`, §3.1), not just a login. Its `page/live` metadata is also
  thinner (no distinct title, generic "en directo" placeholder) — treat it as an
  entitlement-gated tab the app can only unlock for subscribed users, and don't
  assume the same free-tier UX as the other 17.
- To refresh this list yourself later (channels do get added/renamed over time):
  `GET client/v1/row/live` → for each `itemRows[].contentId`, optionally
  `GET client/v1/page/live/{contentId}` for the clean name/start-over flag.

---

## 18. Category / row id reference (ready to hardcode)

Every id below is taken directly from `main_list()` and its three sub-menus
(`menu_cine`, `novelas_nova`, `kidz`) in `default.py` — the complete set of
hardcoded catalog entry points the addon ships today. All of them feed into the
shared FORMAT pipeline (§12) or the flat RECORDING pipeline (§13) depending on
which `entityType` the call uses; none of this needs rediscovery, it's already
fully enumerated in the source.

One id recurs throughout: `mainChannelId=5a6b32667ed1a834493ec03b` is
**Atresplayer's own global brand/channel id** (as opposed to an individual TV
channel id like Antena 3's `5a6a165a7ed1a834493ebf6a` from §17) — it means "content
published under the Atresplayer umbrella generally", and shows up on every
`categoryId`-based search below.

### 18.1 Root menu

| Menu label | Call | Item shape |
|---|---|---|
| Buscador (search) | `GET client/v1/row/search?entityType=ATPFormat&text={query}&size=100&page={n}` | FORMAT (§4.1) |
| Últimos 7 días | `GET client/v1/page/u7d/5a6b32667ed1a834493ec03b` → per-channel `row` hrefs (§4.5) | hub → RECORDING (§13) |
| TV de Atresmedia en directo | `GET client/v1/row/live` | LIVE (§17) |
| Originales ViX | `GET client/v1/row/678e611c73e8690007b9d824?size=100&page={n}` | FORMAT |
| Estrenos exclusivos en ViX | `GET client/v1/row/5c4095d67ed1a880faf098cd?size=100&page={n}` | FORMAT |
| Añadido recientemente | `GET client/v1/row/5b6ae2b97ed1a8bbd1275c22?size=100&page={n}` | FORMAT |
| Preestrenos | `GET client/v1/row/66e03e1463a63b0007d94c09?size=100&page={n}` | FORMAT |
| Clásicos Atresplayer | `GET client/v1/row/632245ec7141b0e419991186?size=100&page={n}` | FORMAT |
| Programas | `GET client/v1/row/search?entityType=ATPFormat&sectionCategory=true&mainChannelId=5a6b32667ed1a834493ec03b&categoryId=5a6a1ba0986b281d18a512b9&sortType=AZ&size=100&page={n}` | FORMAT |
| Series | same, `categoryId=5a6a1b22986b281d18a512b8` | FORMAT |
| Informativos | same, `categoryId=5a6a215e986b281d18a512bc&sortType=THE_MOST&size=8` | FORMAT |
| Vix Telenovelas | `GET client/v1/row/5b1676d17ed1a87acd06c2fa?size=100&page={n}` | FORMAT |
| Telenovelas Atresplayer | search, `categoryId=5a6a2313986b281d18a512be&sortType=AZ` | FORMAT |
| Infantil | search, `categoryId=5a6a24b1986b281d18a512c0&sortType=AZ` | FORMAT |
| Documentales | search, `categoryId=5b067bf3986b28b0a27c2f42&sortType=THE_MOST` | FORMAT |
| Cine | → §18.2 sub-menu | — |
| Telenovelas Nova | → §18.3 sub-menu | — |
| Kidz | → §18.4 sub-menu | — |

### 18.2 Cine sub-menu (`menu_cine`)

| Label | Call | Item shape |
|---|---|---|
| Cine — últimos 7 días | `GET client/v1/row/search?entityType=ATPRecording&categoryId=5b5f2f777ed1a86860102144&size=50&page={n}` | RECORDING, flat (§13) |
| Cine — todas las películas | `GET client/v1/row/search?entityType=ATPFormat&sectionCategory=true&mainChannelId=5a6b32667ed1a834493ec03b&categoryId=5b5f2f777ed1a86860102144&sortType=THE_MOST&size=50&page={n}` | FORMAT, goes through the season/episode pipeline (§12) even though it's movie content — a real data-modeling quirk on Atresmedia's side, not an addon bug (see §16) |

Same `categoryId` (`5b5f2f777ed1a86860102144` = "Cine") used both ways, filtered by
`entityType` — good pattern to reuse: one category id, two content-shape views.

### 18.3 Telenovelas Nova sub-menu (`novelas_nova`)

| Label | Call | Item shape |
|---|---|---|
| Portada | `GET client/v1/row/5b150ca67ed1a864fe8264ab?size=16&page={n}` | FORMAT |
| Destacadas | `GET client/v1/row/5db3f6437ed1a8f9e42fe980?size=50&page={n}` | FORMAT |
| Lo mejor de Turquía | `GET client/v1/row/5baa09227ed1a8d2fcc378d2?size=50&page={n}` | FORMAT |
| Añadidas recientemente | `GET client/v1/row/5b6ae2b97ed1a8bbd1275c22?size=50&page={n}` | FORMAT |

⚠️ **"Añadidas recientemente" here uses the exact same row id
(`5b6ae2b97ed1a8bbd1275c22`) as the root menu's global "Añadido recientemente"**
(§18.1) — it is not actually a Nova-specific "recently added telenovelas" feed, it's
the same site-wide recently-added row reused verbatim. Looks like a copy-paste in
the original addon rather than an intentional design — worth deciding whether the
iOS app should keep this duplication or find (or drop) a real Nova-specific
"recently added" id.

### 18.4 Kidz sub-menu (`kidz`)

| Label | Call | Item shape |
|---|---|---|
| Destacados | `GET client/v1/row/5bf67e2f7ed1a8c62d08a2d0?size=100&page={n}` | FORMAT |
| Universo Kidz | `GET client/v1/row/5bc73fa67ed1a82a8faf01af?size=100&page={n}` | FORMAT |
| Recomendados para ti | `GET client/v1/row/recommended?context=canal&contextValue=5f69bd317ed1a83f0b8eadf0&channelId=5f69bd317ed1a83f0b8eadf0&contentType=ATPFormat&size=100&page={n}` | FORMAT, personalization params (`visitorId`/`marketingId`/`os` in the addon's original URL) look like inert client-fingerprint noise copied from a captured request, not required for the call to succeed |
| Para ver en familia | `GET client/v1/row/5bcf05017ed1a8138977c1c1?size=100&page={n}` | FORMAT |
| Baby Kidz | `GET client/v1/row/5bc732d17ed1a82a8e1237ad?size=100&page={n}` | FORMAT |
| Canta con Baby Heidi | `GET client/v1/row/5bb23a447ed1a8defc7e77e8?size=100&page={n}` | **EPISODE** (confirmed by direct fetch) — but the addon wires this menu item to the `cine()` handler (a legacy regex parser expecting the old flat-recording HTML/JSON shape), not `programas()`. **This is a genuine, verified bug**: the handler's regexes don't match EPISODE-card JSON, so this specific menu item is expected to return empty/garbage in the current addon. For iOS, treat this row as an EPISODE listing like any other, ignore how the addon routes it. |

---

## 19. Quick-start id sheet

For dropping straight into the iOS app's initial category list without re-deriving
anything from §18:

```
GLOBAL_CHANNEL_ID   = "5a6b32667ed1a834493ec03b"   // Atresplayer brand-wide mainChannelId

CATEGORY_PROGRAMAS      = "5a6a1ba0986b281d18a512b9"
CATEGORY_SERIES         = "5a6a1b22986b281d18a512b8"
CATEGORY_INFORMATIVOS   = "5a6a215e986b281d18a512bc"
CATEGORY_TELENOVELAS    = "5a6a2313986b281d18a512be"
CATEGORY_INFANTIL       = "5a6a24b1986b281d18a512c0"
CATEGORY_DOCUMENTALES   = "5b067bf3986b28b0a27c2f42"
CATEGORY_CINE           = "5b5f2f777ed1a86860102144"

ROW_ORIGINALES_VIX      = "678e611c73e8690007b9d824"
ROW_ESTRENOS_VIX        = "5c4095d67ed1a880faf098cd"
ROW_ANADIDO_RECIENTE    = "5b6ae2b97ed1a8bbd1275c22"
ROW_PREESTRENOS         = "66e03e1463a63b0007d94c09"
ROW_CLASICOS            = "632245ec7141b0e419991186"
ROW_VIX_TELENOVELAS     = "5b1676d17ed1a87acd06c2fa"

U7D_HUB_ID              = "5a6b32667ed1a834493ec03b"   // same value as GLOBAL_CHANNEL_ID

LIVE_CHANNELS = [
    ("5a6a165a7ed1a834493ebf6a", "antena3",     "Antena 3"),
    ("5a6a172c7ed1a834493ebf6b", "lasexta",     "La Sexta"),
    ("5a6a17da7ed1a834493ebf6d", "neox",        "Neox"),
    ("5a6a180b7ed1a834493ebf6e", "nova",        "Nova"),
    ("5a6a18357ed1a834493ebf6f", "mega",        "Mega"),
    ("5a6a189a7ed1a834493ebf70", "atreseries",  "Atreseries"),
    ("5c1285e47ed1a861f8125285", "canal-flooxer", "Flooxer"),
    ("648ef12c2bfab0e4507e0d61", "clasicos",    "Clásicos"),
    ("648c271d2bfab0e4177a0d61", "canal-kidz",  "Kidz"),
    ("648ef3951756b0e425af83cc", "aqui-no-hay-quien-viva", "Aquí no hay quien viva"),
    ("648ef5882bfab0e4627e0d61", "el-hormiguero", "El Hormiguero"),
    ("648ef5551756b0e429af83cc", "equipo-de-investigacion", "Equipo de Investigación"),
    ("648ef50a2bfab0e4607e0d61", "foq",         "Física o Química"),
    ("648f47f7a2ffb0e40aeff3ad", "el-club-de-la-comedia", "El Club de la Comedia"),
    ("648ef18c1756b0e41daf83cc", "multicine",   "Multicine"),
    ("648ef23d2bfab0e4557e0d61", "comedia",     "Comedia"),
    ("648ef3162bfab0e4587e0d61", "mentes-inquietas", "Mentes Inquietas"),
    ("6107d2846584a82b1f0eb800", "atresplayer-premium", "Atresplayer Premium"),  # required_paid
]
```
All ids above were live-verified on 2026-09-15 against `api.atresplayer.com` — treat
them the same as everything else in this document: reverse-engineered, no stability
guarantee, re-verify if the app starts seeing unexpected empty categories.
