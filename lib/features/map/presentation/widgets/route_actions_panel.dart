import 'package:flutter/material.dart';

class RouteActionsPanel extends StatelessWidget {
  const RouteActionsPanel({
    super.key,
    required this.hasOrigin,
    required this.hasDestination,
    required this.isRouting,
    required this.onGetRoute,
    required this.onClear,
    required this.onExport,
  });

  final bool hasOrigin;
  final bool hasDestination;
  final bool isRouting;
  final VoidCallback onGetRoute;
  final VoidCallback onClear;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          heroTag: 'route_btn',
          onPressed: (hasOrigin && hasDestination && !isRouting) ? onGetRoute : null,
          icon: isRouting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.route),
          label: Text(isRouting ? 'Routing...' : 'Get Route'),
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'clear_route_btn',
          onPressed: onClear,
          icon: const Icon(Icons.clear),
          label: const Text('Clear'),
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'export_route_btn',
          onPressed: (hasOrigin && hasDestination) ? onExport : null,
          icon: const Icon(Icons.open_in_new),
          label: const Text('Export'),
        ),
      ],
    );
  }
}
