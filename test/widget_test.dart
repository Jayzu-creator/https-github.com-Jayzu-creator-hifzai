import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hifzai/main.dart';

void main() {
  test('payment confirmation requires a completed matching ZAR payment', () {
    const completed = PaymentStatus(
      id: 'ch_valid',
      status: 'completed',
      amount: 20000,
      currency: 'ZAR',
      paymentId: 'pay_valid',
    );
    const pending = PaymentStatus(
      id: 'ch_pending',
      status: 'created',
      amount: 20000,
      currency: 'ZAR',
      paymentId: null,
    );
    const wrongAmount = PaymentStatus(
      id: 'ch_wrong_amount',
      status: 'completed',
      amount: 150000,
      currency: 'ZAR',
      paymentId: 'pay_wrong_amount',
    );
    const wrongCurrency = PaymentStatus(
      id: 'ch_wrong_currency',
      status: 'completed',
      amount: 20000,
      currency: 'USD',
      paymentId: 'pay_wrong_currency',
    );

    expect(completed.confirms(20000), isTrue);
    expect(pending.confirms(20000), isFalse);
    expect(wrongAmount.confirms(20000), isFalse);
    expect(wrongCurrency.confirms(20000), isFalse);
  });

  testWidgets('renders the HifzAI app', (tester) async {
    await tester.pumpWidget(const HifzAIApp());
    expect(find.byType(HifzAIApp), findsOneWidget);
  });

  testWidgets('shows honest plan availability and proposed prices',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProgressScreen()),
      ),
    );

    expect(find.text('HifzAI Free'), findsOneWidget);
    expect(find.text('R0 • Free forever'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('HifzAI Plus'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('HifzAI Plus'), findsOneWidget);
    expect(
      find.text(
        'R199 • per month • R1,499 per year (about R125/month)',
      ),
      findsOneWidget,
    );
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.textContaining('Coming soon'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('HifzAI Pro'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('HifzAI Pro'), findsOneWidget);
    expect(find.text('R299 • per month'), findsOneWidget);
    expect(find.textContaining('Coming soon'), findsWidgets);
    expect(find.text('Choose'), findsNothing);
  });
}
