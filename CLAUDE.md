<!-- GSD:project-start source:PROJECT.md -->
## Project

**No Ponto**

No Ponto is a mobile urban mobility app focused on public bus transportation. It helps riders inspect nearby and citywide bus stops, see which lines serve each stop, check predicted arrivals, inspect full line itineraries, and plan trips between origin and destination using public transit.

The current product is already a functioning brownfield Flutter app with route planning, maps, notifications, and geolocation flows implemented. The immediate mission is not feature expansion, but making the existing app stable and trustworthy end to end for a first usable release.

**Core Value:** A rider can reliably understand where to board, when the bus should arrive, and how to complete a trip without the app hanging, misleading them, or failing silently.

### Constraints

- **Tech stack**: Flutter and Dart must remain the current implementation path — changing stack is out of scope for this milestone
- **Integrations**: The app depends on the current ETUFOR API and Nominatim-style geocoding — stability must improve without replacing these services wholesale
- **Architecture debt**: Existing flows already work partially in production-like code paths — changes should prioritize safe incremental hardening over large rewrites
- **Release focus**: The goal is a first stable usable version, not a broad v2 feature push — roadmap should bias toward reliability and validation
- **Platform behavior**: Location, background activity, and notifications are sensitive to device and Android runtime behavior — fixes must respect plugin and OS constraints
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Runtime
- Primary app target is Flutter with Dart SDK `^3.10.0` from `pubspec.yaml`.
- The repository includes generated platform shells for Android, iOS, macOS, Linux, Windows, and web under `android/`, `ios/`, `macos/`, `linux/`, `windows/`, and `web/`.
- Main app bootstrap lives in `lib/main.dart` and starts services before `runApp`.
## State And UI
- UI is built with Flutter Material widgets across `lib/screens/`.
- Global state is minimal and centered on `provider`, with `ChangeNotifierProvider` wiring `BusProvider` in `lib/main.dart`.
- Theme configuration is defined in `lib/utils/app_theme.dart`.
## Core Dependencies
- Networking: `http` in `lib/services/api_service.dart` and `lib/services/nominatim_service.dart`.
- State management: `provider` in `lib/providers/bus_provider.dart`.
- Maps and geo: `webview_flutter`, `flutter_map`, `google_maps_flutter`, `geolocator`, `latlong2`.
- Notifications and device capabilities: `flutter_local_notifications`, `vibration`, `timezone`, `url_launcher`.
- Persistence and files: `shared_preferences`, `path_provider`, `path`, `dart:io`.
- Data parsing: `xml` for KML parsing in `lib/services/kml_service.dart`.
- Utility packages present but not obviously central in the current code include `uuid`, `json_rpc_2`, `pointer_interceptor`, `collection`, and `stack_trace`.
## Data Sources
- Remote ETUFOR-style API base URL is hardcoded in `lib/services/api_service.dart`.
- OpenStreetMap Nominatim geocoding is called from `lib/services/nominatim_service.dart`.
- Offline/semi-static route data is bundled in `assets/rotas_horarios.kml`, `assets/paradas_onibus.kml`, `assets/logradouros_normalizados.json`, and `assets/logradouro_lookup.json`.
## Platform Integration
- Android-specific foreground tracking support exists in `android/app/src/main/kotlin/com/example/mybus/MainActivity.kt` and `android/app/src/main/kotlin/com/example/mybus/LocationForegroundService.kt`.
- Android permissions and receivers are declared in `android/app/src/main/AndroidManifest.xml`.
- WebView-hosted OpenLayers maps are embedded directly inside Dart screen files such as `lib/screens/home_map_screen.dart`, `lib/screens/route_map_screen.dart`, and `lib/screens/line_detail_screen.dart`.
## Tooling
- Static analysis uses `package:flutter_lints/flutter.yaml` via `analysis_options.yaml`.
- The repo contains a helper script `tools/generate_logradouro_lookup.py` for generating lookup data.
- Test tooling is only `flutter_test`; there is no CI config visible in the repository root.
## Notable Mismatches
- `pubspec.yaml` still uses the default description, while the app itself is branded as "No Ponto".
- Some dependency/docs references appear stale compared with the live code, for example `documentation.md` mentions `flutter_background_service`, but the repo currently uses a custom Android foreground service plus `geofence_service`.
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Language And Style
- Dart code mostly follows common Flutter conventions: `PascalCase` types, `camelCase` members, `const` where convenient, and `StatefulWidget`/`StatelessWidget` composition.
- The repo enables `flutter_lints` through `analysis_options.yaml`, but there is little evidence of stricter custom linting.
- Naming is mixed Portuguese/English, especially in models and UI copy, reflecting the product domain and API language.
## Common Patterns
- Singleton services are used frequently:
- `NotificationService`
- `FavoritesService`
- `PersistenceService`
- `GeofenceManager`
- Provider + `ChangeNotifier` is the dominant app-state mechanism through `BusProvider`.
- Caching is ad hoc and local:
- in-memory endpoint cache in `lib/services/api_service.dart`
- itinerary cache in `lib/providers/bus_provider.dart`
- local persisted state in `SharedPreferences` and JSON files
## Error Handling
- Many service/provider methods wrap logic in `try/catch` and suppress failures silently.
- Common patterns include:
- catching `Exception` or dynamic errors without logging
- returning empty lists or `null`
- setting a generic UI-facing error string only in some cases
- This favors resilience in the UI, but it also reduces debuggability.
## UI Construction Style
- Screens are often large monolithic state classes rather than decomposed widget trees.
- Inline HTML, CSS, and JavaScript are embedded directly in Dart strings for map rendering.
- Navigation is handled with direct `Navigator.push` calls rather than a centralized router.
- Theme access uses `Theme.of(context).colorScheme` consistently in several newer screens.
## Data And Domain Conventions
- API DTO parsing typically happens with handwritten `fromJson` constructors.
- There is no generated serialization layer.
- Date strings for schedule APIs are manually formatted as `YYYYMMDD` in several places instead of using a shared formatter utility.
- Route and stop logic commonly use string normalization and heuristic matching for street/control-point names.
## Testing/Debug Conventions
- `print` and `debugPrint` are both present in production code.
- Some files include comment markers indicating quick fixes or copied logic, for example `lib/services/haversine_calculator.dart` and `test/reproduce_issue.dart`.
- The project contains several code comments in Portuguese describing intent and troubleshooting context.
## Naming And Consistency Concerns
- Duplicate domain names across languages (`Linha` vs `Line`, `Itinerario` vs `Itinerary`) increase cognitive load.
- Some files still carry prototype or migration signals rather than settled production conventions.
- Documentation and dependency references are not consistently updated when implementation choices change.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## High-Level Shape
- The app is a Flutter client for bus information and trip assistance in Fortaleza, branded in UI as "No Ponto".
- Architecture is best described as screen-driven Flutter UI plus service helpers, with a single shared `BusProvider` coordinating the most important transit data workflows.
- There is no strong domain/application/infrastructure layering; concerns are organized mostly by folders and practical responsibilities.
## Entry And Boot Flow
- `lib/main.dart` performs startup initialization for favorites, local notifications, permission requests, and geofence setup before calling `runApp`.
- `MaterialApp` starts on `lib/screens/splash_screen.dart`.
- `SplashScreen` is the effective runtime gate for onboarding/launch transitions before the user reaches the main navigation surface.
## State Flow
- `BusProvider` in `lib/providers/bus_provider.dart` is the central in-memory state holder for:
- fetched lines and filtered lines
- street/logradouro data
- itinerary caching
- graph-building status
- route search logic and arrival prediction helpers
- Screens generally use `Provider.of<BusProvider>` or `Consumer<BusProvider>` directly rather than isolated view models per screen.
## Data Flow
- Remote API JSON is fetched in `lib/services/api_service.dart`.
- JSON is converted into model classes from `lib/models/`.
- `BusProvider` orchestrates loading and caches itineraries in memory.
- Route planning converts transit itineraries into a transport graph via `lib/utils/graph_utils.dart`.
- UI screens such as `lib/screens/route_planner_screen.dart`, `lib/screens/stop_detail_screen.dart`, and `lib/screens/line_detail_screen.dart` request provider/service data and render results.
## Mapping Flow
- Mapping is implemented in multiple styles:
- WebView + inline HTML/JS + OpenLayers in `lib/screens/home_map_screen.dart`, `lib/screens/route_map_screen.dart`, and `lib/screens/line_detail_screen.dart`
- Flutter-native map widgets in `lib/screens/real_time_selection_screen.dart`
- Google Maps types in `lib/services/nominatim_service.dart` and related older flows
- This suggests the mapping layer evolved over time instead of being unified behind one map abstraction.
## Real-Time Trip Flow
- `lib/screens/real_time_selection_screen.dart` prepares the trip context and route choice.
- `lib/screens/real_time_travel_screen.dart` manages active trip tracking, ETA updates, stop progress, and map updates.
- `lib/services/geofence_manager.dart` maintains a rolling geofence window for upcoming stops.
- `lib/services/foreground_service_channel.dart` bridges to Android native code that starts/stops `LocationForegroundService`.
- `lib/services/persistence_service.dart` stores the active trip so it can be resumed from `lib/screens/home_map_screen.dart`.
## Persistence Model
- State is mostly ephemeral in memory.
- User-specific durable state is stored locally through `SharedPreferences` and JSON files.
- No database layer, repository package, or backend-auth layer is present.
## Architectural Risks
- Large stateful screens mix UI, permission handling, HTML generation, and business logic in single files.
- `BusProvider` carries both state management and algorithmic route-planning responsibilities, making it a de facto application service and cache layer.
- Duplicate model concepts like `Line`/`Linha`, `Itinerary`/`Itinerario`, and extra algorithm files like `lib/models/route_bus_find.dart` indicate parallel implementations that are not fully consolidated.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
