# Spotify OAuth configuration

DynamicIsland uses Spotify Authorization Code with PKCE. Release users do not create a Spotify developer application or enter a Client ID.

For a packaged build, create the DynamicIsland Spotify application once in Spotify's developer dashboard and register this redirect URI exactly:

`dynamicisland://spotify-callback`

Inject that application's public Client ID at package time without committing it:

```bash
DYNAMICISLAND_SPOTIFY_CLIENT_ID="<client-id>" Scripts/package_app.sh
```

The package script writes the value to the generated app `Info.plist` as `DynamicIslandSpotifyClientID` and registers the `dynamicisland` URL scheme. No Client Secret is used.

Debug builds retain a developer-only Client-ID override in Settings so local contributors can test OAuth without changing tracked source. Release Settings never expose the Client ID.

Spotify access, expiry, and refresh credentials are stored in Keychain. Disconnect removes all stored Spotify credentials.
