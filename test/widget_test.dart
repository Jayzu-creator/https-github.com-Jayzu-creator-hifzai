import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hifzai/main.dart';

void main() {
  setUpAll(QuranService.load);

  test('bundles every Quran Surah and ayah locally', () async {
    expect(D.surahs, hasLength(114));
    expect(QuranService.allAyahs, hasLength(6236));
    expect(D.surahs.first.name, 'Al-Fatihah');
    expect(D.surahs.last.id, 114);
    expect(
      RegExp(r'[\u0600-\u06FF]').hasMatch(QuranService.allAyahs.first.text),
      isTrue,
    );
    expect((await QuranService.fetchSurah(2)).first.surahId, 2);
  });

  test('next-ayah quiz creates four distinct Quran-valid options', () {
    final question = QuranService.createNextAyahQuestion(1);
    final correctChoices = question.choices
        .where((ayah) =>
            ayah.surahId == question.answer.surahId &&
            ayah.number == question.answer.number)
        .toList();

    expect(question.prompt.surahId, 1);
    expect(question.answer.surahId, 1);
    expect(question.answer.number, question.prompt.number + 1);
    expect(question.choices, hasLength(4));
    expect(correctChoices, hasLength(1));
    expect(
      question.choices.map((ayah) => '${ayah.surahId}:${ayah.number}').toSet(),
      hasLength(4),
    );
    expect(
      QuranService.createNextAyahQuestion(null).choices,
      hasLength(4),
    );
  });

  test('creates a focused question for a saved revision target', () {
    final target = QuranService.ayahsForSurah(2)[2];
    final question = QuranService.createQuestionForAnswer(target);

    expect(question.answer.number, target.number);
    expect(question.prompt.number, target.number - 1);
    expect(question.prompt.surahId, target.surahId);
    expect(question.choices, hasLength(4));
    expect(question.choices.map((ayah) => ayah.text).toSet(), hasLength(4));
    expect(
      question.choices
          .where((ayah) =>
              ayah.surahId == target.surahId && ayah.number == target.number)
          .length,
      1,
    );
  });

  test('builds plan analytics from saved quiz outcomes', () {
    final insights = QuranProgressInsights.fromRows([
      {'surah_id': 2, 'ayah_number': 3, 'status': 'needs_revision'},
      {'surah_id': 2, 'ayah_number': 4, 'status': 'needs_revision'},
      {'surah_id': 1, 'ayah_number': 2, 'status': 'remembered'},
    ]);

    expect(insights.rememberedCount, 1);
    expect(insights.needsRevisionCount, 2);
    expect(insights.needsRevision.map((ayah) => ayah.number), [3, 4]);
    expect(insights.reviewedCount, 3);
    expect(insights.accuracyPercent, 33);
    expect(insights.weakestSurahs.first.surahId, 2);
    expect(insights.weakestSurahs.first.missedCount, 2);
    expect(insights.weakestSurahs.first.accuracyPercent, 0);
  });

  testWidgets('starts a focused revision quiz from saved ayahs',
      (tester) async {
    final target = QuranService.ayahsForSurah(2)[2];
    await tester.pumpWidget(
      MaterialApp(
        home: MemorisationTestScreen(revisionTargets: [target]),
      ),
    );

    await tester.tap(find.text('Start focused revision'));
    await tester.pump();

    expect(find.text('Focused Revision'), findsOneWidget);
    expect(find.text('Question 1 of 1 • 0 correct'), findsOneWidget);
  });

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

  testWidgets('shows implemented paid features and honest availability',
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
    expect(
      find.text('Study tools ready • live services disabled'),
      findsWidgets,
    );
    expect(
      find.textContaining(
          'Personalised recommendations from your saved missed ayahs'),
      findsOneWidget,
    );
    expect(find.textContaining('Planned:'), findsNothing);

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
    expect(
      find.textContaining(
          'Per-Surah quiz accuracy report and a custom 10-ayah revision session'),
      findsOneWidget,
    );
    expect(find.textContaining('Planned:'), findsNothing);
    expect(find.text('Choose'), findsNothing);
  });
}
