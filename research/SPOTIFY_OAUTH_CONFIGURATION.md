# Spotify OAuth configuration

DynamicIsland uses Spotify Authorization Code with PKCE. Release users do **not** create a Spotify developer application or enter a Client ID.

The distributor setup and current provider constraints are documented in `research/SPOTIFY_DISTRIBUTOR_SETUP.md`.

For a packaged build, the DynamicIsland distributor creates the Spotify developer application once and registers this redirect URI exactly:

`dynamicisland://spotify-callback`

Inject that application's public Client ID at package time without committing it:

```bash
DYNAMICISLAND_SPOTIFY_CLIENT_ID="<client-id>" Scripts/package_app.sh
```

The package script writes the value to the generated app `Info.plist` as `DynamicIslandSpotifyClientID` and registers the `dynamicisland` URL scheme. No Client Secret is used.

Debug builds retain a developer-only Client-ID override in Settings so local contributors can test OAuth without changing tracked source. Release Settings never expose the Client ID.

Spotify access, expiry, refresh credentials, and the original authorization timestamp are stored in Keychain. Disconnect removes them all.

Spotify user refresh tokens expire six months after the original authorization. DynamicIsland preserves that original timestamp across access-token refreshes. A known six-month expiry or token-endpoint `invalid_grant` clears stale credentials and requires an explicit **Reconnect Spotify** action.

HTTP 429 responses are not automatically retried. A structured Spotify `QUOTA_EXCEEDED` response is surfaced separately from ordinary rate limiting.

Local Spotify.app media detection and playback controls are independent from Web API configuration and remain available when no Client ID is packaged.
