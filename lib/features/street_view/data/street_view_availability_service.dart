import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Checks Street View availability at a location.
/// Option (b): attempt to load panorama and listen for "no panorama" callback.
/// This service can be extended to call Google Street View Metadata API
/// (option a) for a more reliable check without loading the panorama.
class StreetViewAvailabilityService {
  /// Returns true if Street View is likely available at the given position.
  /// Default implementation always returns true; the actual availability
  /// is determined when loading the panorama (onError / no data).
  Future<bool> checkStreetViewAvailability(LatLng position) async {
    // Option (a): could call Metadata API here, e.g.:
    // https://maps.googleapis.com/maps/api/streetview/metadata?location=...
    // For now we rely on option (b): load and handle "unavailable" in UI.
    return true;
  }
}
