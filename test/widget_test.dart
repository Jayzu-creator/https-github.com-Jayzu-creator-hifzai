import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hifzai/main.dart';

void main() {
  test('wraps PCM samples in a valid WAV header', () {
    final wav = pcm16ToWav(Uint8List.fromList([1, 2, 3, 4]));
    final header = ByteData.sublistView(wav);

    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint32(40, Endian.little), 4);
    expect(wav.length, 48);
    expect(
      () => pcm16ToWav(Uint8List.fromList([1])),
      throwsArgumentError,
    );
  });

  test('payment confirmation requires a saved entitlement and matching charge',
      () {
    const completed = PaymentStatus(
      id: 'ch_valid',
      status: 'completed',
      amount: 19900,
      currency: 'ZAR',
      paymentId: 'pay_valid',
      entitlement: {'plan': 'plus', 'expires_at': '2026-10-26T00:00:00Z'},
    );
    const pending = PaymentStatus(
      id: 'ch_pending',
      status: 'created',
      amount: 19900,
      currency: 'ZAR',
      paymentId: null,
    );
    const wrongAmount = PaymentStatus(
      id: 'ch_wrong_amount',
      status: 'completed',
      amount: 150000,
      currency: 'ZAR',
      paymentId: 'pay_wrong_amount',
      entitlement: {'plan': 'plus', 'expires_at': '2026-10-26T00:00:00Z'},
    );
    const wrongCurrency = PaymentStatus(
      id: 'ch_wrong_currency',
      status: 'completed',
      amount: 19900,
      currency: 'USD',
      paymentId: 'pay_wrong_currency',
      entitlement: {'plan': 'plus', 'expires_at': '2026-10-26T00:00:00Z'},
    );
    const notYetSaved = PaymentStatus(
      id: 'ch_unsaved',
      status: 'completed',
      amount: 19900,
      currency: 'ZAR',
      paymentId: 'pay_unsaved',
    );

    expect(completed.confirms(19900), isTrue);
    expect(pending.confirms(19900), isFalse);
    expect(wrongAmount.confirms(19900), isFalse);
    expect(wrongCurrency.confirms(19900), isFalse);
    expect(notYetSaved.confirms(19900), isFalse);
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
          'R199 • one-time one-month access • R1,499 one-time for 12 months'),
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
    expect(
      find.text('R299 • one-time one-month access, no automatic renewal'),
      findsOneWidget,
    );
    expect(find.textContaining('Coming soon'), findsWidgets);
    expect(find.text('Choose'), findsNothing);
  });
}
