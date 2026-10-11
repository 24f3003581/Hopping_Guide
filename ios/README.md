# Uma — Kolkata Durga Puja 2026 (SwiftUI iOS)

A native iOS port of the [Hopping Guide](https://github.com/Arnab-apk/Hopping_Guide) Flutter Android app. Uma is your companion for Kolkata's Durga Puja — discover 387 pandals, plan curated circuits, walk with your squad, and stay safe with emergency contacts.

## Status

✅ **Builds successfully** with Xcode 27.0 / iOS 27.0 SDK (deployment target iOS 18). Liquid Glass on iOS 26+ via `glassEffect(_:in:)` with iOS 18–25 fallback to SwiftUI materials.

## What's inside

| Area | Coverage |
|---|---|
| **Models** | 11 Swift structs (Pandal with all 15 fields, MetroStation + 5-line enum, FoodSpot, Toilet, SquadMember, ChatMessage, WalkingRoute + TrailLeg, KolkataZone, Helpline, HoppingRoute, ActiveCustomTrail) |
| **Repositories** | JSON loaders for pandals (387), food spots (66), helplines (5), toilets + 41 hardcoded metro stations |
| **Services** | LocationService (CLLocationManager), RoutingService (MKDirections + geodesic fallback), OmniSearchService (token-weighted phonetic), TrailOptimizer (Held-Karp + 2-opt), SquadService, ChatService, UserStateService, ThemeService |
| **Utils** | Haversine (distance + bearing), PujaSchedule (12-day countdown), DouglasPeucker (polyline simplify), SpatialCorridor (10 km + 70 km fallback), PandalSpatialCluster |
| **Design System** | LiquidGlass (centralized modifier), Theme (PujaColors tokens), PujaIcons (14 PNGs × 3 variants loaded from asset catalog), Haptics |
| **Features** | WelcomeView (animated countdown with <=800ms splash), MapTabView (MKMapView + Liquid Glass HUD + focused transit pins + numbered stops), PandalsListView (cached single-pass distance matrix), PandalDetailView, RoutesView (6 curated circuits), SquadHubView (4-card hub + Group Video Call entry), SquadChatView (text chat + direct video call), GroupVideoCallView (squad video room with fixed End Call button & hosted backend fallback), HelplinesView (one-tap dialer) |
| **Tests** | 9 test files: TrailOptimizer, OmniSearch, Haversine, DouglasPeucker, PandalSpatialCluster, LiquidGlassAvailability, LocationFixValidation, RoutingCoalescing, GroupVideoApi |

## v1.0.0 Enhancements

- **On-Demand Tab Mounting**: Inactive tabs mount strictly when selected, preserving state upon visit while eliminating background ticker and layout overhead.
- **Snappier Greeting / Splash**: Greeting splash minimum hold time reduced to <= 800 ms with redundant delays removed and persistent onboarding.
- **Pandal Directory Caching**: Directory listing rebuilds solely on genuine coordinate displacements (>20 m) rather than compass orientation ticks. Haversine distance calculations are cached per pass.
- **Directions Request Coalescing**: Concurrent identical route queries are coalesced within `RoutingService` to eliminate redundant network requests.
- **Squad Group Video Calling**:
  - Full squad room interface (`GroupVideoCallView`) with participant video/avatar grid and active speaker detection.
  - Prominent, accessible red **"End call"** button cleanly anchored below media controls and elevated above gesture navigation.
  - Automatic resilient fallback to hosted squad calling backend (`https://uma-group-calling.onrender.com`).
  - Seamless entry from both Squad Hub and Squad Chat.
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

To run on your physical iPhone:
1. Open `Uma.xcodeproj` in Xcode
2. Select your iPhone in the device picker
3. Set a valid Team ID in Signing & Capabilities (currently `CODE_SIGNING_ALLOWED=NO`)
4. Press ⌘R

## Out of scope for v1

- Firebase auth / Firestore / Cloudinary — dropped (on-device only)
- Magic Lane GemKit — replaced by MapKit
- Chat media (base64 images) — text-only chat for v1
- Bengali script font (Samarkan unavailable) — Bodoni 72 system serif substitute
- WidgetKit countdown widget — marked v2
- iOS 26 Liquid Glass visual verification (only iOS 18.6 sim runtime installed locally) — runs locally via the iOS 18 fallback path

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
