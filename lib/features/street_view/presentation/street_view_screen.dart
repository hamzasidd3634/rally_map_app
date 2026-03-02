import 'package:flutter/material.dart';
import 'package:flutter_google_street_view_v2/flutter_google_street_view_v2.dart' as street_view;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class StreetViewScreen extends StatefulWidget {
  const StreetViewScreen({
    super.key,
    required this.initialPosition,
    this.onPopCameraPosition,
  });

  final LatLng initialPosition;
  final void Function(CameraPosition?)? onPopCameraPosition;

  @override
  State<StreetViewScreen> createState() => _StreetViewScreenState();
}

class _StreetViewScreenState extends State<StreetViewScreen> {
  street_view.StreetViewController? _streetViewController;
  bool _isLoading = true;
  bool _unavailable = false;

  void _onStreetViewCreated(street_view.StreetViewController controller) {
    _streetViewController = controller;
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    final location = await _streetViewController?.getLocation();
    setState(() {
      _isLoading = false;
      _unavailable = location == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final initLatLng = street_view.LatLng(
      widget.initialPosition.latitude,
      widget.initialPosition.longitude,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Street View'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _onBack,
        ),
      ),
      body: Stack(
        children: [
          street_view.FlutterGoogleStreetView(
            initPos: initLatLng,
            initRadius: 50,
            initFov: 90,
            initBearing: 0,
            initTilt: 0,
            onStreetViewCreated: _onStreetViewCreated,
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
          if (!_isLoading && _unavailable)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Street View unavailable here.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
                    SizedBox(height: 16),
                    TextButton(
                      onPressed: _onBack,
                      child: Text('Go back'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onBack() {
    Navigator.of(context).pop();
  }
}
