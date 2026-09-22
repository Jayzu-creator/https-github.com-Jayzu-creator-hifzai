import 'package:flutter_test/flutter_test.dart';

import 'package:hifzai/main.dart';

void main() {
  testWidgets('renders the HifzAI app', (tester) async {
    await tester.pumpWidget(const HifzAIApp());
    expect(find.byType(HifzAIApp), findsOneWidget);
  });
}
