import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rally_map_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches and renders root scaffold', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.byType(Scaffold), findsWidgets);
  });
}
