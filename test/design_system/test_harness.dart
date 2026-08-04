import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';

/// Envuelve [child] en un `MaterialApp` con el tema real de RISEG ONE —
/// los componentes Riseg leen `AppColorScheme` vía `context.colors`, así
/// que no pueden probarse sin un `Theme` que lo provea.
Future<void> pumpRiseg(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}
