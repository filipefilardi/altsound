import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/features/auth/login_screen.dart';

void main() {
  testWidgets('Login screen renders server step', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.pump();

    expect(find.text('AltSound'), findsOneWidget);
    expect(find.text('SERVER URL'), findsOneWidget);
    expect(find.text('CONTINUE'), findsOneWidget);
    expect(find.text('Username'), findsNothing);
    expect(find.text('Password'), findsNothing);
  });

  testWidgets('Login screen renders account step with initial server', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: LoginScreen(initialServerUrl: 'https://media.example.org'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('AltSound'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('SIGN IN'), findsOneWidget);
  });
}
