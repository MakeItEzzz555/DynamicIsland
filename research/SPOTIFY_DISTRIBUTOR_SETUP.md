# Spotify distributor setup

DynamicIsland follows the same end-user OAuth model as Droppy: the **app distributor owns one Spotify Developer application** and packages its public Client ID. Normal users never create a Spotify developer app and never enter a Client ID.

## End-user flow

1. Open DynamicIsland Settings.
2. Press **Connect Spotify**.
3. Authorize DynamicIsland in Spotify's browser flow.
4. Return to DynamicIsland through `dynamicisland://spotify-callback`.
5. DynamicIsland stores the user's access/refresh credentials in Keychain.

No Client Secret is embedded or requested. Authorization Code with PKCE is used because DynamicIsland is a public desktop client.

## One-time distributor setup

The Spotify developer-app owner must satisfy Spotify's current Development Mode requirements. As of September 2026, Development Mode requires the app owner to maintain Spotify Premium and permits a small allowlist of test users.

Create one Spotify app for DynamicIsland and register this redirect URI exactly:

`dynamicisland://spotify-callback`

Enable the Web API and add the intended test accounts under the app's Users/Access management.

Package the public Client ID without committing it:

```bash
DYNAMICISLAND_SPOTIFY_CLIENT_ID="<client-id>" Scripts/package_app.sh
```

The generated app stores that value in `Info.plist` as `DynamicIslandSpotifyClientID`. Release Settings never expose a Client-ID editor. Debug builds retain an explicit developer override for local contributors.

## Token lifecycle

Spotify user refresh tokens expire six months after the user's original authorization. Refreshing an access token does not extend that lifetime.

DynamicIsland records the original authorization date alongside the Keychain credentials. When the known six-month deadline is reached, or Spotify returns `invalid_grant` while refreshing, DynamicIsland clears the stale credentials and shows **Reconnect Spotify**. It does not loop token refreshes or launch OAuth without an explicit user action.

Older credentials created before authorization-date tracking are not invalidated speculatively; Spotify's `invalid_grant` remains authoritative for them.

## Quota and rate limits

HTTP 429 responses are not retried automatically.

- Ordinary 429 responses are reported as rate limiting and preserve `Retry-After` when present.
- Development Mode quota exhaustion is detected from Spotify's structured `reason: QUOTA_EXCEEDED` response and reported separately.

## Provider split

Local Spotify.app support remains independent from the Web API and continues to provide supported local media controls even when no Web API Client ID is packaged.

Web API authorization is only for account-backed features such as queue data, playlists, liked songs, add-to-queue, and library mutation.

## Current external blocker

No legitimate DynamicIsland distributor Client ID is available in the current development environment, so live Spotify OAuth/Web API acceptance remains **IMPLEMENTED BUT REAL VALIDATION BLOCKED**. Deterministic PKCE, callback, token, pagination, mutation, refresh-expiry, and quota tests do not substitute for live provider validation.

Do not reuse another application's Client ID, scrape Spotify desktop/web session credentials, embed a Client Secret, or depend on undocumented private Spotify endpoints.
