import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally_map_app/features/map/presentation/widgets/route_actions_panel.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('Get Route disabled until origin and destination set', (tester) async {
    await tester.pumpWidget(wrap(RouteActionsPanel(
      hasOrigin: true,
      hasDestination: false,
      isRouting: false,
      onGetRoute: () {},
      onClear: () {},
      onExport: () {},
    )));

    final btn = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton).first,
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('Get Route shows routing state', (tester) async {
    await tester.pumpWidget(wrap(RouteActionsPanel(
      hasOrigin: true,
      hasDestination: true,
      isRouting: true,
      onGetRoute: () {},
      onClear: () {},
      onExport: () {},
    )));
    expect(find.text('Routing...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Export enabled when both pins exist', (tester) async {
    await tester.pumpWidget(wrap(RouteActionsPanel(
      hasOrigin: true,
      hasDestination: true,
      isRouting: false,
      onGetRoute: () {},
      onClear: () {},
      onExport: () {},
    )));
    final fabList = tester.widgetList<FloatingActionButton>(find.byType(FloatingActionButton)).toList();
    final exportButton = fabList.last;
    expect(exportButton.onPressed, isNotNull);
  });
}
