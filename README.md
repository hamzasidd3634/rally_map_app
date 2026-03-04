# Rally Map App

Flutter app with Google Maps: stage route, closed roads (GPX), Street View, and optional routing with “crosses stage” detection.

## Release Notes

- **What this app does**: Displays rally stages on Google Maps with stage polylines, Start/Finish markers, closed-road overlays from GPX, and Street View entry from map tap.
- **Street View package compatibility**: Custom update applied to `flutter_google_street_view_v2: ^1.0.1` to keep Street View behavior compatible with newer platform/runtime changes.
- **Closed roads styling**: Road closures are rendered as **red polylines** (`closed_1`, `closed_2`, `closed_3`) on top of the rally map.
- **Route export**: User-selected routes (origin/destination pins, including reroute waypoints) can be exported as a Google Maps directions URL and opened in the Google Maps app/browser.
- **Rally logo zoom logic**:
  - Logo is visible only when zoom is between `0` and `5` (inclusive).
  - Logo is hidden when zoom is greater than `5`.
  - Logo is anchored to the rally location (Stage 1 start), so it stays geographically fixed while panning/zooming.

## Setup

### Prerequisites

- Flutter SDK (latest stable), null-safety
- A [Google Maps API key](https://developers.google.com/maps/documentation/android-sdk/get-api-key) with:
  - **Maps SDK for Android** and **Maps SDK for iOS**
  - **Street View Static API** (or equivalent) if using Street View
  - For Part D routing: **Directions API** (and optionally **Routes API**)

### API key configuration

1. **Android**  
   In `android/app/src/main/AndroidManifest.xml`, set your key in the `com.google.android.geo.API_KEY` meta-data.

   **Map opens but stays gray/blank?** That’s an **authorization failure**: the key can’t load tiles. Fix it in [Google Cloud Console](https://console.cloud.google.com) (same project as the key):

   | Step | What to do |
   |------|------------|
   | 1 | **APIs & Services → Library** → search **“Maps SDK for Android”** → open it → click **Enable**. |
   | 2 | **APIs & Services → Credentials** → open your API key. If **Application restrictions** is “Android apps”, add an entry: **Package name** `com.rally.rally_map_app`, **SHA-1** your debug fingerprint (e.g. `81:22:A4:FE:40:E2:19:3F:A6:04:C7:D8:84:AA:ED:FB:77:F0:AF:42`). Get SHA-1: `cd android && ./gradlew signingReport` or `keytool -list -v -keystore ~/.android/debug.keystore` (password: `android`). |
   | 3 | Ensure **Billing** is enabled for the project (required for Maps even for free quota). |
   | 4 | Save, wait 1–2 minutes, then **fully restart the app** (kill and run again). |

2. **iOS**  
   In `ios/Runner/AppDelegate.swift`, replace `YOUR_GOOGLE_MAPS_API_KEY` in `GMSServices.provideAPIKey(...)` with your key.

3. **Routing (Part D)**  
   The Directions client in `lib/features/routing/data/directions_client.dart` expects an API key (e.g. via env or config). Pass it when constructing `DirectionsClient(apiKey: '...')` if you implement the full routing UI.

### Stage polyline data

Stage routes are read from `assets/data/stage.json` (one stage; app default is **Stage 1**). The repo also has:

- **`assets/data/stage_polylines_source.txt`** – source with Stage 1–3 (start/finish + coordinate arrays).
- **`stage1.json`**, **`stage2.json`**, **`stage3.json`** – generated per-stage files (497, 309, 424 points).

To regenerate from the source file:

```bash
python3 scripts/generate_stage_json.py
```

This updates `stage.json` and `stage1..3.json` from `assets/data/stage_polylines_source.txt`.

### Run

```bash
flutter pub get
flutter run
```

### Known log messages (usually harmless)

- **`Failed to ensure .../Android/data/.../files: ServiceSpecificException (code -30)`**  
  The Maps SDK tries to ensure the app’s external files directory; on some devices (e.g. TECNO, or when default storage is an SD volume) the system may log this. The SDK falls back to other storage and the map should still work.

- **`ClientParamsBlocking` / `Flogger ... Dropping old logs`**  
  From Google Play Services / Maps SDK; safe to ignore.

---

## Architecture

- **State management**: Cubit (BLoC-style) via `flutter_bloc`. Single `MapCubit` holds map data, camera, and routing state; it is provided at app level so the map and overlays persist when navigating to Street View and back.

- **Feature layout**:
  - **`features/map`**: Map screen, stage + closed-road polylines, Start/Finish markers, rally logo overlay, tap → Street View. Data: `StageRepository` (JSON), `GpxCache` + `GpxService` (GPX parse + simplify).
  - **`features/street_view`**: Street View screen and availability handling; uses `flutter_google_street_view`.
  - **`features/routing`**: Domain: geometry (projection, segment intersection, distance-to-polyline, polyline intersection), export Google Maps URL. Data: `DirectionsClient` for Directions API. Map state includes route origin/destination, route polyline, and “crosses stage” flag/message; cubit exposes `routeCrossesStage(routePoints)` and route setters/clear.

- **Shared / domain**:
  - **`shared/models`**: e.g. `LatLngModel` for non-UI use.
  - **`shared/utils`**: Douglas–Peucker polyline simplification (pure Dart).
  - **`features/routing/domain/geometry`**: Pure Dart, testable: equirectangular projection, segment intersection (with tolerance), distance to segment/polyline, polyline-vs-polyline intersection. Used by map (snap-to-stage, Part D) and by tests.

- **Closed roads near rallies**: The 3 GPX closed-road polylines (`assets/gpx/closed_road_1.gpx`, `closed_road_2.gpx`, `closed_road_3.gpx`) are placed **near the rally stages** (Ireland, same region as Stage 1/2/3). They render as red polylines on the map alongside the stage routes.

- **Performance / no jank**:
  - **Parse and simplify once**: Stage loaded from asset once; GPX files parsed and Douglas–Peucker simplified in a **compute()** isolate, then cached in `GpxCache`. Map rebuilds do not re-parse or re-simplify.
  - **Stable IDs**: PolylineIds (`stage_1`, `stage_2`, `stage_3`, `closed_1`, `closed_2`, `closed_3`, `user_route`) and MarkerIds (`start_stage_1`, `finish_stage_1`, etc., `rally_logo`, `route_origin`, `route_destination`) are fixed. Sets of polylines/markers are replaced only when underlying data changes, not on camera move.
  - **Camera vs overlays**: Polylines and markers are **not** updated on every camera move. **onCameraIdle** is used to update only zoom-derived state (e.g. rally logo visibility at zoom ≤ 5). Camera position is tracked in state for initial position and for optional restoration after Street View.
  - **Rally logo**: Shown only when zoom ≤ 5; visibility toggled only when zoom crosses that threshold to avoid repeated state updates. Logo bitmap is loaded once and cached in the map screen.

---

## Performance considerations (what prevents jank/flicker)

1. **No overlay updates on camera move**  
   Only `onCameraIdle` triggers state that affects overlays (rally logo visibility). Polylines and markers are driven by data (stage, closed roads, route), not by camera.

2. **Stable sets and IDs**  
   Same PolylineIds and MarkerIds every time; the map widget receives new sets only when stage/closed roads/route data change.

3. **Heavy work off UI thread**  
   GPX parsing and Douglas–Peucker simplification run in **compute()** so the UI thread stays responsive.

4. **In-memory cache**  
   Parsed and simplified GPX polylines are cached in `GpxCache`; no repeated file read or simplification on rebuild.

5. **Rally logo**  
   Bitmap loaded once; visibility toggled only when zoom crosses the threshold (e.g. 5), not on every frame.

---

## Features implemented

- **Part A**: MapScreen with Google Map; stage polyline from `assets/data/stage.json`; Start/Finish markers; three closed-road GPX files parsed via `compute()` and simplified; stable polyline/marker IDs; smooth pan/zoom without overlay jank.
- **Part B**: Rally logo overlay (marker with bitmap) at stage start; visible when zoom ≤ 5, hidden when zoom > 5; anchored correctly; logo cached.
- **Part C**: Tap on map opens Street View at tapped point; if tap is near stage polyline (~25 m), snap to closest point on stage; Street View screen shows “Street View unavailable here” when no panorama; back returns to map with state preserved (camera/overlays) via app-level MapCubit.
- **Part D (bonus)**: Routing domain: polyline intersection and distance helpers (pure Dart), `DirectionsClient` for Directions API, and Google Maps route export URL generation. UI supports long-press origin/destination pins, fastest route calculation, stage-crossing detection, automatic alternate reroute with user message, and an **Export** action that opens Google Maps with the selected route/waypoints.

---

## Tests

```bash
flutter test test/geometry test/routing
```

(Run the geometry and routing tests as above. A full `flutter test` may hit compatibility issues in the `street_view_platform_interface` dependency.)

- **`test/geometry/`**: Segment intersection, distance to segment, distance to polyline, polyline-vs-polyline intersection.
- **`test/routing/`**: Export Google Maps directions URL.
