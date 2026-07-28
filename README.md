# Jelly TV

Jelly TV is an iPhone and iPad client for personal [Jellyfin](https://jellyfin.org/) media servers. Browse and search your library, stream movies and episodes, download supported media for offline playback, and optionally use Seerr to discover and request titles.

Jelly TV does not provide media or a Jellyfin/Seerr server. You need an account on a server you can access.

## Features

- Browse movies, shows, seasons, and episodes.
- Search the Jellyfin library and resume playback.
- View media details, ratings, metadata, and artwork.
- Choose from available audio tracks.
- Download supported movies and episodes for offline playback.
- Keep local download progress and playback position in sync when possible.
- Use lock-screen and Control Center playback controls, including artwork and episode metadata.
- Continue video in Picture in Picture and background playback.
- Connect a compatible Seerr server to discover, request, and—where permitted—approve titles.

## Requirements

- Xcode 27 or later.
- An iPhone or iPad running iOS 26 or later.
- A Jellyfin server and valid account.
- A compatible Seerr server for optional request-management features.

## Run locally

1. Open [`jellytv/jellytv.xcodeproj`](jellytv/jellytv.xcodeproj) in Xcode.
2. Select the `jellytv` scheme and an iPhone, iPad, or simulator destination.
3. Configure a signing team and a unique bundle identifier if required by your Apple Developer account.
4. Build and run.
5. Enter your Jellyfin server URL and account credentials on the sign-in screen.

For a local server, HTTP may be used when the app permits it. Remote servers should use HTTPS.

## Project layout

```text
jellytv/
├── jellytv/                 # iOS app source
│   ├── App/                 # App entry point and root views
│   ├── Core/                # API clients, models, sessions, cache, offline downloads
│   ├── Features/            # Browse, search, details, player, auth, and Seerr UI
│   └── Shared/              # Reusable UI components
├── docs/                    # App Store and privacy documentation
└── jellytv.xcodeproj        # Xcode project
```

## Privacy and storage

Jellyfin credentials are stored in the device Keychain. Offline media, artwork, download metadata, and playback positions are stored locally. Media activity is sent to the Jellyfin and Seerr servers selected by the user.

See [the privacy policy](docs/PRIVACY_POLICY.md) and [App Store listing notes](docs/APP_STORE_LISTING.md) for more detail.

## License

No license has been specified for this repository.
