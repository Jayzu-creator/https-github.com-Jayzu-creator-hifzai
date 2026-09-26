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
}
