# Library Sync Strategy

Analysis of library synchronization patterns from OuterTune and Metrolist reference implementations.

## Overview

Library sync keeps the app's local data synchronized with the remote YouTube Music account. This includes:
- Liked songs collection
- User's playlists (created, saved, subscribed)
- Liked artists
- Liked albums
- Recently played history

## Sync Architecture (OuterTune/Metrolist Pattern)

### Core Timing Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| **Sync Interval (Primary)** | 30 minutes | Target refresh frequency for account data |
| **Auto-Scan Cooldown** | 11 hours | Minimum wait between successful local scans |
| **Auto-Scan Soft Cooldown** | 2 hours | Minimum wait between any scan attempts (even failed) |
| **Soft cooldown < Hard cooldown** | 2h < 11h | Ensures retry attempts without excessive hammering |

---

## Sync Triggers

### 1. App Launch (Mandatory)
**When**: App starts or comes to foreground
**Action**: Trigger full sync of all library data
**Reason**: Catch any account changes since last app close

**Pattern**:
- Load cached library data immediately (fast UI)
- Kick off background sync in parallel
- Update UI when fresh data arrives

---

### 2. Periodic Sync (Background)
**Frequency**: Every 30 minutes (if enabled in settings)
**Action**: Refresh liked songs, playlists, artists, albums
**Reason**: Keep data fresh during extended app usage

**Implementation considerations**:
- Only runs while app is active/in foreground
- Respects battery/network state (may skip on low battery or cellular)
- Non-blocking; doesn't interrupt user playback
- Can be disabled in settings if user prefers manual-only sync

---

### 3. Manual Refresh (User Initiated)
**When**: User taps refresh/sync button in UI
**Action**: Immediately sync all library sections
**Reason**: User wants latest data now (just added song to liked, want it visible)

**Behavior**:
- Takes priority over periodic sync
- Shows loading indicator
- May have rate-limit checks (prevent rapid-fire refreshes)

---

### 4. Event-Triggered Sync (Implicit)
**When**: User performs action that changes library state
**Examples**:
- Like/unlike a song
- Create/delete/modify playlist
- Follow/unfollow artist
- Save/unsave album

**Action**: Invalidate related cache; trigger local sync of that section

**Example timeline**:
```
11:00 - User likes a song
       ↓
       1. Update local cache immediately (optimistic update)
       2. Send like to YouTube Music API
       3. Invalidate "liked_songs" cache entry
       4. Next sync (in ≤30 min) will refresh from server
       5. By 11:30, liked_songs cache is fresh from server
```

---

## Sync Architecture Details

### Library Sections Synced
1. **Liked Songs** (FEmusic_liked_playlists)
   - User's "Liked" playlist
   - Typically hundreds to thousands of songs
   - Sync frequency: 30 minutes

2. **User Playlists**
   - Playlists user created
   - Playlists user added songs to
   - Sync frequency: 30 minutes

3. **Liked Artists**
   - Following list
   - Used for recommendations ("your liked artists")
   - Sync frequency: 30 minutes

4. **Liked Albums**
   - Saved albums
   - Less frequently synced
   - Sync frequency: Could be less frequent (30 min - 1 day)

5. **Recent Activity**
   - Playback history
   - Used for "forgotten favorites" & "keep listening" recommendations
   - Sync frequency: 30 minutes

### Sync Concurrency Limits
- **Max concurrent sync jobs**: 3 (prevent API overload)
- **Max concurrent content fetches**: 16 (image resolutions, metadata)
- **Prevents**: Rate limiting (429 errors) from YouTube Music API

---

## Sync Behavior Under Conditions

### Successful Sync
```
Auto-Scan Cooldown = 11 hours applies
├─ Last successful sync: 9:00 AM
├─ Retry clock resets
└─ Next auto-sync not before: 8:00 PM
```

### Failed Sync
```
Auto-Scan Soft Cooldown = 2 hours applies
├─ Last attempt (failed): 9:00 AM
├─ Retry clock resets
├─ Soft cooldown: 2 hours
└─ Next auto-sync not before: 11:00 AM (can retry sooner than hard cooldown)
```

### Network Status Impact
- **WiFi**: Sync proceeds normally
- **Cellular**: May defer sync or use lighter payload (skip images)
- **Offline**: Cache used; sync queued for when online
- **Airplane mode**: Skip sync; use cached data

### Battery Status Impact
- **Low power mode**: Defer sync until plugged in or normal mode
- **Battery < 15%**: May reduce sync frequency
- **Charging**: Prioritize syncs (good time to fetch fresh data)

---

## Data Consistency Strategy

### Optimistic Updates
When user performs action (like song):
1. Update local cache immediately (instant feedback)
2. Send to server in background
3. If server fails, rollback cache to previous state
4. Show error toast to user
5. Offer retry option

### Event Ordering
Multiple rapid actions handled carefully:
```
11:00:00 - User likes song A
11:00:01 - User likes song B
11:00:02 - Sync starts for both

OuterTune/Metrolist queues changes and syncs atomically
to avoid race conditions where song A succeeds but B fails
```

### Conflict Resolution
If user's action conflicts with server state:
- Server state wins (YouTube Music is source of truth)
- Merge strategy: refresh from server, keep local additions
- User gets notification if their recent change conflicts

---

## Sync Frequency Recommendations by Data Type

| Data Type | Recommended Sync | Reason |
|-----------|-----------------|--------|
| **Liked Songs** | 30 minutes | User adds songs frequently; visibility matters |
| **Playlists** | 30 minutes | User modifies playlists; want instant sync |
| **Liked Artists** | 30 minutes | Used for recommendations; moderate priority |
| **Liked Albums** | 1-2 hours | Less frequently modified; lower priority |
| **Play History** | 1-2 hours | Used for "forgotten favorites"; less critical |
| **Library Metadata** | On-demand | Only when user explicitly browses |

---

## Failure Handling

### Network Error
- Cache data for offline fallback
- Show "Last synced: X minutes ago" indicator
- Retry automatically next time network available
- Manual retry button if user wants to force sync

### Rate Limiting (429 Response)
- Respect Retry-After header if provided
- Back off exponentially: 2 sec → 4 sec → 8 sec → 16 sec
- Stop retrying after X attempts; show error message
- Resume normal sync frequency after cooldown passes

### Server Error (5xx)
- Treat like network error
- Cache still valid; use it
- Retry on next scheduled sync (30 min window)
- Don't panic; user can still play cached content

### Timeout
- If sync takes > 60 seconds, abort and retry later
- Don't hang UI waiting for sync
- Use timeout exceptions to trigger cooldown

---

## Settings & User Control

### Sync Preferences
- **Auto-sync enabled/disabled**: Default enabled
- **Sync frequency**: Adjustable (15 min, 30 min, 60 min, on-demand only)
- **Sync on cellular**: Toggle (default off to save data)
- **Background sync**: Enable/disable while app backgrounded

### Sync Status UI
- Last synced timestamp: "Synced 5 minutes ago"
- Sync in progress: Spinning indicator
- Sync failed: Error message + "Retry" button
- Pending changes: Badge count (e.g., "3 changes pending")

---

## Transition Events

### Login
- Clear all old cache
- Trigger full library sync immediately
- Start background sync timer

### Logout
- Wipe all user-specific cache (liked songs, playlists, etc.)
- Stop background sync timer
- Revert to guest mode (no sync)

### Switch Accounts
- Clear previous account's cache
- Load new account's cached data (if available)
- Trigger fresh sync of new account

---

## Sync & Cache Relationship

### How They Work Together

| Operation | Cache | Sync |
|-----------|-------|------|
| App launch | Load immediately (fast) | Kick off in background |
| 5 min later | Use cache if valid | Sync still running? No impact, use cache |
| 30 min later | Cache expired | Sync refreshed; use new data |
| User pull-refresh | Bypass cache | Force immediate sync |
| 11 hours no success | Very stale cache | Hard cooldown kicks in; retry |

### Example: Liked Songs Flow
```
10:00 AM - App launches
  ├─ Liked songs cache: ✓ Valid (from 9:30 AM)
  └─ Display cached (instant)
     ↓
  Background sync starts
  ├─ Fetches fresh liked songs from YouTube Music
  └─ Takes 5 seconds
     ↓
10:05 AM - Sync completes
  ├─ Updates cache: ✓ Fresh (now from 10:05)
  └─ User sees updated UI if still viewing liked songs

10:30 AM - Next periodic sync triggers
  └─ Repeats process
```

---

## Performance Impact

### Disk I/O
- Syncing writes fresh JSON to disk cache
- Uses background queue to avoid blocking main thread
- Typical sync payload: 1-5 MB (liked songs, playlists metadata)

### Network Usage
- 30-minute sync on WiFi: ~2-5 MB per sync
- Aggressive polling (15 min) vs. relaxed (1 hour): affects data usage
- Cellular users benefit from longer sync intervals (save data)

### Battery Impact
- Background sync minimal (~1-2% battery per sync)
- Avoid syncing while screen off unless explicitly enabled
- Higher frequency = more battery drain

### CPU Impact
- Parsing JSON, sorting, deduplicating: negligible (< 100ms)
- Sorting large playlists (10k+ songs): may take 1-2 seconds
- Offload to background thread to prevent UI jank

---

## Known Limitations in OuterTune/Metrolist

1. **No real-time sync**: Changes take up to 30 minutes to propagate
   - Solution: Show optimistic updates immediately, sync async

2. **Coarse-grained sync**: Syncs entire "liked songs" instead of delta
   - Limitation: More data transfer than delta-based approach
   - Acceptable because YouTube Music doesn't provide delta API

3. **No conflict merging**: Server state always wins
   - Can be jarring if user's local change differs from server
   - Mitigated by showing last synced time

4. **Single-user assumption**: No multi-account local sync
   - Each account has separate cache
   - Switching accounts clears cache

---

## Decision Points for Mixtape Implementation

When implementing library sync, decide:

1. **Sync frequency**: Match reference (30 min)? Or different based on use case?
2. **Auto-sync on launch**: Always? Optional?
3. **Cellular sync**: Always? Only on WiFi? User preference?
4. **Sync indication**: Show last synced time? Indicate pending changes?
5. **Conflict handling**: Server wins? Show merge UI? User chooses?
6. **Cache invalidation on change**: Immediate or wait for sync confirmation?
7. **Retry strategy**: Exponential backoff? Max retries?
8. **Rate limiting handling**: Silent retry? Show error? How many retries?

Reference: OuterTune/Metrolist make these choices; document rationale for Mixtape's choices.
