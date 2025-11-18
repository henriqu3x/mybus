# TODO: Fix Compilation Errors in Flutter Project

## Information Gathered
- **PriorityQueue**: Used in `api_provider.dart` but import is incorrect. Should import from `package:collection/collection.dart` instead of `dart:collection`.
- **Line Model**: Has `name` field, not `nome`. Constructor uses `name`, but some usages in `api_provider.dart` incorrectly use `nome`.
- **HaversineCalculator**: Used in `route_suggestion.dart` but import is missing.
- **RouteSuggestion Getters**: Missing `steps` (alias for `segments`), `connections` (alias for `transferCount`), and `description` (new getter needed).
- **fetchItinerary Method**: Missing in `ApiProvider`, but called in screens.
- **Other**: Constructor calls for `Line` need to use `name` instead of `nome`.

## Plan
1. Update imports in `lib/providers/api_provider.dart`:
   - Change `import 'dart:collection';` to `import 'package:collection/collection.dart';`
2. Add missing import in `lib/models/route_suggestion.dart`:
   - Add `import '../services/haversine_calculator.dart';`
3. Add getters to `RouteSuggestion` class in `lib/models/route_suggestion.dart`:
   - `List<RouteSegment> get steps => segments;`
   - `int get connections => transferCount;`
   - `String get description => 'Rota com ${transferCount} conexão${transferCount != 1 ? 'ões' : ''}';`
4. Add `fetchItinerary` method to `ApiProvider` in `lib/providers/api_provider.dart`:
   - `Future<Map<String, Itinerary>> fetchItinerary(int id) async => await _fetchItineraryCached(id);`
5. Fix `Line` constructor calls in `api_provider.dart`:
   - Change `nome:` to `name:` in `Line` instantiations.
6. Fix field access in `api_provider.dart`:
   - Change `newLine?.nome` to `newLine?.name`.

## Dependent Files to Edit
- `lib/providers/api_provider.dart`
- `lib/models/route_suggestion.dart`

## Followup Steps
- Run `flutter analyze` to check for remaining errors.
- Run `flutter build` to ensure the project compiles.
- Test the app to verify functionality.
