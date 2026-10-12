# Uma — Kolkata Durga Puja 2026 (SwiftUI iOS)

A native iOS port of the [Hopping Guide](https://github.com/Arnab-apk/Hopping_Guide) Flutter Android app. Uma is your companion for Kolkata's Durga Puja — discover 387 pandals, plan curated circuits, walk with your squad, and stay safe with emergency contacts.

## Status

Targets iOS 18. Map, pandal, route, and helpline features work without cloud credentials. Squad sync, chat, and video calls require the Firebase iOS app configuration described below; video calls also require the deployed video service and Stream server credentials.

## What's inside

| Area | Coverage |
|---|---|
| **Models** | 11 Swift structs (Pandal with all 15 fields, MetroStation + 5-line enum, FoodSpot, Toilet, SquadMember, ChatMessage, WalkingRoute + TrailLeg, KolkataZone, Helpline, HoppingRoute, ActiveCustomTrail) |
| **Repositories** | JSON loaders for pandals (387), food spots (66), helplines (5), toilets + 41 hardcoded metro stations |
| **Services** | LocationService (CLLocationManager), RoutingService (MKDirections + geodesic fallback), OmniSearchService (token-weighted phonetic), TrailOptimizer (Held-Karp + 2-opt), Firebase-backed SquadService and ChatService, UserStateService, ThemeService |
| **Utils** | Haversine (distance + bearing), PujaSchedule (12-day countdown), DouglasPeucker (polyline simplify), SpatialCorridor (10 km + 70 km fallback), PandalSpatialCluster |
| **Design System** | LiquidGlass (centralized modifier), Theme (PujaColors tokens), PujaIcons (14 PNGs × 3 variants loaded from asset catalog), Haptics |
| **Features** | WelcomeView (animated countdown), MapTabView (MKMapView + nearby filter, zone selector, zoom and locate controls), PandalsListView (nearest-first distance sorting), PandalDetailView, RoutesView (6 curated circuits), SquadHubView and SquadChatView (Firebase/Firestore sync), GroupVideoCallView (Stream Video SDK call UI using server-minted, membership-checked tokens), HelplinesView (one-tap dialer) |
| **Tests** | 9 test files: TrailOptimizer, OmniSearch, Haversine, DouglasPeucker, PandalSpatialCluster, LiquidGlassAvailability, LocationFixValidation, RoutingCoalescing, GroupVideoApi |

## v1.0.0 Enhancements

- **On-Demand Tab Mounting**: Inactive tabs mount strictly when selected, preserving state upon visit while eliminating background ticker and layout overhead.
- **Snappier Greeting / Splash**: Greeting splash minimum hold time reduced to <= 800 ms with redundant delays removed and persistent onboarding.
- **Pandal Directory Caching**: Directory listing rebuilds solely on genuine coordinate displacements (>20 m) rather than compass orientation ticks. Haversine distance calculations are cached per pass.
- **Directions Request Coalescing**: Concurrent identical route queries are coalesced within `RoutingService` to eliminate redundant network requests.
- **Squad calling integration**: real Stream Video calls; the video service checks the Firebase ID token and Firestore squad membership before issuing a short-lived call token. The app does not report a call as connected until the Stream SDK joins it.
- **Route & Transit Map Pins Refinement**:
  - Focused station pins: trail and itinerary maps display intermediate, boarding, and interchange stations strictly for active transit legs, suppressing unrelated clutter.
  - Layering priority: Numbered festival pins render atop station markers (`zPriority: 1000` vs `500`).
  - Strict GPS Fix Validation: Trail progress checks require GPS timestamps $\le$ 10 seconds fresh and accuracy $\le$ 30 meters, rejecting jitter and duplicate arrivals.

## White-pixel bug fix

The Flutter Android app uses OSM raster tiles with a throttled tile updater and a `_kDarkMatrix` ColorFilter. Cancelled in-flight tile requests leave partial rasters showing as bright white squares in dark mode (`hopping_guide_source/app/lib/screens/map_screen.dart:128-149`).

**iOS fix:** MapKit vector tiles (`MKMapView` via `UIViewRepresentable`) with `overrideUserInterfaceStyle = .dark`. No raster fetching, no `ColorFilter` matrix, no throttling cancellation artifacts. The bug class is eliminated.

## Generate, build, run

```bash
# Install xcodegen (already on this machine via Homebrew)
brew install xcodegen

# Generate Xcode project
cd ios
xcodegen generate

# Build for iOS device
xcodebuild -project Uma.xcodeproj -scheme Uma \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO

# Open in Xcode
open Uma.xcodeproj
```

### Firebase and video setup

1. Register an iOS app with bundle ID `app.uma.Uma` in the same Firebase project as Android, enable Anonymous Authentication, and use the existing Firestore database.
2. Add the downloaded `GoogleService-Info.plist` inside `ios/Uma/` so XcodeGen includes it in the app bundle. Keep this file untracked; do not commit Firebase config files.
3. Regenerate the Xcode project with `xcodegen generate`. The project spec resolves Firebase Auth, Firestore, and Stream Video through Swift Package Manager.
4. The video backend must have its Firebase Admin credentials and `STREAM_API_KEY` / `STREAM_API_SECRET` configured on the server. The Stream secret must never be placed in the iOS app.
5. Verify the iOS write contract with `cd ios/BackendCompatibilityTests && npm ci && npm test` (Node 22+ and Java 21+). The tests use an unchanged rules snapshot from Android v1.0.0. This PR does not modify or deploy Android's Firestore rules. Welcome/join notices are sent after membership commits to work with the existing rules.

Without Firebase configuration, squad create/join, cross-device chat, and video calls show a setup/sign-in error. If the backend or Stream credentials are unavailable, the call screen shows the actual failure; it does not create a demo room.

To run on your physical iPhone:
1. Open `Uma.xcodeproj` in Xcode
2. Select your iPhone in the device picker
3. Set a valid Team ID in Signing & Capabilities (currently `CODE_SIGNING_ALLOWED=NO`)
4. Press ⌘R

## Current limitations

- Magic Lane GemKit — replaced by MapKit
- Squad chat currently supports text messages only; image/video uploads are not wired to a storage service.
- Companion phone calling and group video calling are separate actions. Android's v1.0.0 release includes Stream group video calling; the iOS integration uses the same Firebase membership and video backend contract.
- Bengali script font (Samarkan unavailable) — Bodoni 72 system serif substitute
- WidgetKit countdown widget — marked v2
- iOS 26 Liquid Glass visual verification requires a current iOS simulator or device.

## File tree

```
Uma/
├── project.yml                       # xcodegen spec
├── README.md                         # this file
├── Uma.xcodeproj                     # generated by xcodegen
├── Uma/
│   ├── App/                          # @main entry, root shell, environment
│   ├── DesignSystem/                 # LiquidGlass, Theme, PujaIcons, Haptics
│   ├── Models/                       # 11 domain models
│   ├── Repositories/                 # 5 JSON loaders
│   ├── Services/                     # 8 services incl. algorithms
│   ├── Utils/                        # 5 math/spatial helpers
│   ├── Features/
│   │   ├── Welcome/                  # animated onboarding
│   │   ├── Map/                      # MKMapView + UI + callouts
│   │   ├── Pandals/                  # list, detail, card
│   │   ├── Routes/                   # 6 curated circuits
│   │   ├── Squad/                    # 4-card hub + chat
│   │   └── Helplines/                # emergency dialer
│   ├── Resources/                    # 6 JSON data files (verbatim from Flutter)
│   └── Assets.xcassets/              # AppIcon + AccentColor + 42 Puja icons
└── UmaTests/                         # 6 regression test files
```
