# TODO List for MyBus Flutter App

## 1. Update Dependencies
- [x] Add http, google_maps_flutter, flutter_local_notifications, shared_preferences, provider to pubspec.yaml
- [x] Run flutter pub get

## 2. Create Data Models
- [x] Create lib/models/line.dart
- [x] Create lib/models/itinerary.dart
- [x] Create lib/models/schedule.dart
- [x] Create lib/models/logradouro.dart

## 3. Create API Service
- [x] Create lib/services/api_service.dart for fetching data from APIs (linhas, itinerario, horarios, logradouros, LinhasDologradouro)

## 4. Set Up App Structure
- [x] Update lib/main.dart to set up app with Provider and navigation
- [x] Create lib/screens/home_screen.dart
- [x] Create lib/screens/lines_list_screen.dart
- [x] Create lib/screens/itinerary_details_screen.dart
- [x] Create lib/screens/schedule_screen.dart
- [x] Create lib/screens/route_planner_screen.dart
- [x] Create lib/screens/favorites_screen.dart
- [x] Create lib/screens/map_view_screen.dart

## 5. Implement State Management
- [x] Create lib/providers/app_provider.dart for managing app state

## 6. Implement UI and Features
- [x] Implement Home screen with navigation to other screens
- [x] Implement Lines List screen with API integration
- [x] Implement Itinerary Details screen
- [x] Implement Schedule screen with date selection
- [x] Implement Route Planner screen with origin/destination selection
- [x] Implement Favorites screen with local storage
- [x] Implement Map View screen with Google Maps integration
- [x] Update models to match XML API response structure
- [x] Update API service to parse XML responses
- [x] Update screens to use new model fields
- [ ] Add notifications for alerts

## 7. Testing and Refinement
- [x] Test API integrations
- [x] Test navigation and UI
- [x] Test map functionality
- [x] Test notifications
- [x] Refine UI/UX based on testing
- [x] Fix linting issues (removed unused imports, fixed deprecated XML API, reordered widget parameters, added mounted checks)
- [x] Fix route planner location loading issue

## 8. Fix Route Finding Logic
- [ ] Modify _findDirectRoutes in api_provider.dart to use itinerary-based matching instead of logradouro IDs
- [ ] Modify _findRoutesWithConnection to use itinerary-based matching for connections
- [ ] Test the fix with the example route (Germano Frank to Vinte quatro de maio)
- [ ] Ensure performance is acceptable (consider caching or optimization)
