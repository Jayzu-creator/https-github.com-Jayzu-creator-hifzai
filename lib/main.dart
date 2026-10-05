import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const paidCheckoutEnabled = bool.fromEnvironment('ENABLE_PAID_CHECKOUT');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await QuranService.load();
  } catch (error) {
    runApp(QuranDataErrorApp(error: error));
    return;
  }
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }
  runApp(const HifzAIApp());
}

class QuranDataErrorApp extends StatelessWidget {
  final Object error;

  const QuranDataErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'The bundled Quran text could not be loaded. Please reinstall or update HifzAI.\n\n$error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}

class C {
  static const emerald = Color(0xFF0C3B2E);
  static const emeraldDark = Color(0xFF071F18);
  static const gold = Color(0xFFC9A227);
  static const goldLight = Color(0xFFE3C566);
  static const cream = Color(0xFFF5EFE0);
}

class AppInfo {
  static const supportEmail = 'hifzalbusinesss@gmail.com';
  static const appName = 'HifzAI';
  static const packageId = 'com.hifzai.quran';
}

class AppLanguage {
  static final arabic = ValueNotifier<bool>(false);

  static String t(String english, String arabicText) {
    return arabic.value ? arabicText : english;
  }
}

TextStyle serif(double size,
    {FontWeight w = FontWeight.w500, Color? color, double? spacing}) {
  return GoogleFonts.cormorant(
    fontSize: size,
    fontWeight: w,
    color: color,
    letterSpacing: spacing,
  );
}

class Surah {
  final int id;
  final String name;
  final String arabic;
  final int ayahs;

  const Surah(this.id, this.name, this.arabic, this.ayahs);
}

class D {
  static List<Surah> surahs = [];

  static String ayahOfDay() {
    const values = [
      'أَلَا بِذِكْرِ اللَّهِ تَطْمَئِنُّ الْقُلُوبُ',
      'فَاذْكُرُونِي أَذْكُرْكُمْ وَاشْكُرُوا لِي وَلَا تَكْفُرُونِ',
      'وَرَتِّلِ الْقُرْآنَ تَرْتِيلًا',
      'إِنَّ مَعَ الْعُسْرِ يُسْرًا',
      'وَقُل رَّبِّ زِدْنِي عِلْمًا',
    ];
    return values[DateTime.now().day % values.length];
  }
}

class QuranAyah {
  final int surahId;
  final int number;
  final String text;

  const QuranAyah({
    required this.surahId,
    required this.number,
    required this.text,
  });
}

class QuranQuizQuestion {
  final QuranAyah prompt;
  final QuranAyah answer;
  final List<QuranAyah> choices;

  const QuranQuizQuestion({
    required this.prompt,
    required this.answer,
    required this.choices,
  });
}

class QuranService {
  static Map<int, List<QuranAyah>> _ayahsBySurah = const {};
  static List<QuranAyah> _allAyahs = const [];

  static Future<void> load() async {
    final source =
        await rootBundle.loadString('assets/quran/quran-uthmani.json');
    final json = jsonDecode(source) as Map<String, dynamic>;
    final rawSurahs = json['surahs'];
    if (rawSurahs is! List || rawSurahs.length != 114) {
      throw const FormatException('The Quran asset must contain 114 Surahs.');
    }

    final surahs = <Surah>[];
    final ayahsBySurah = <int, List<QuranAyah>>{};
    final allAyahs = <QuranAyah>[];
    for (final rawSurah in rawSurahs) {
      final item = rawSurah as Map<String, dynamic>;
      final id = item['number'] as int;
      final arabicName = item['arabicName'] as String;
      final englishName = item['englishName'] as String;
      final rawAyahs = item['ayahs'] as List<dynamic>;
      final ayahs = rawAyahs.map((rawAyah) {
        final ayah = rawAyah as Map<String, dynamic>;
        final text = ayah['text'] as String;
        if (text.trim().isEmpty) {
          throw FormatException('Surah $id contains an empty ayah.');
        }
        return QuranAyah(
          surahId: id,
          number: ayah['number'] as int,
          text: text,
        );
      }).toList(growable: false);
      if (ayahs.isEmpty) throw FormatException('Surah $id has no ayahs.');
      surahs.add(Surah(id, englishName, arabicName, ayahs.length));
      ayahsBySurah[id] = ayahs;
      allAyahs.addAll(ayahs);
    }
    if (allAyahs.length != 6236) {
      throw FormatException(
          'The Quran asset must contain 6236 ayahs, found ${allAyahs.length}.');
    }
    D.surahs = List.unmodifiable(surahs);
    _ayahsBySurah = Map.unmodifiable(ayahsBySurah);
    _allAyahs = List.unmodifiable(allAyahs);
  }

  static List<QuranAyah> get allAyahs => _allAyahs;

  static bool isCorrectAnswer(QuranQuizQuestion question, int choiceIndex) {
    if (choiceIndex < 0 || choiceIndex >= question.choices.length) {
      throw RangeError.index(choiceIndex, question.choices);
    }
    final choice = question.choices[choiceIndex];
    return choice.surahId == question.answer.surahId &&
        choice.number == question.answer.number;
  }

  static Future<List<QuranAyah>> fetchSurah(int id) {
    final ayahs = _ayahsBySurah[id];
    if (ayahs == null) throw ArgumentError.value(id, 'id', 'Unknown Surah');
    return Future.value(ayahs);
  }

  static QuranQuizQuestion createNextAyahQuestion(
    int? surahId, {
    Random? random,
  }) {
    if (_allAyahs.length != 6236) {
      throw StateError(
          'The bundled Quran must be loaded before making a quiz.');
    }
    final generator = random ?? Random();
    final questionPool = surahId == null
        ? _allAyahs
        : _ayahsBySurah[surahId] ?? const <QuranAyah>[];
    if (questionPool.length < 2) {
      throw ArgumentError.value(
          surahId, 'surahId', 'Not enough ayahs to quiz.');
    }
    final promptIndex = generator.nextInt(questionPool.length - 1);
    final prompt = questionPool[promptIndex];
    final answer = questionPool[promptIndex + 1];
    final excluded = {
      '${prompt.surahId}:${prompt.number}',
      '${answer.surahId}:${answer.number}',
    };
    bool isExcluded(QuranAyah ayah) =>
        excluded.contains('${ayah.surahId}:${ayah.number}') ||
        ayah.text == prompt.text ||
        ayah.text == answer.text;
    final localDistractors = questionPool
        .where((ayah) => !isExcluded(ayah))
        .toList()
      ..shuffle(generator);
    final localKeys = localDistractors
        .map((ayah) => '${ayah.surahId}:${ayah.number}')
        .toSet();
    final remainingDistractors = _allAyahs
        .where((ayah) => !isExcluded(ayah))
        .where((ayah) => !localKeys.contains('${ayah.surahId}:${ayah.number}'))
        .toList()
      ..shuffle(generator);
    final choices = <QuranAyah>[
      answer,
      ...localDistractors.take(3),
      ...remainingDistractors.take(3 - min(3, localDistractors.length)),
    ]..shuffle(generator);
    if (choices.length != 4) {
      throw StateError('Could not create four unique Quran answer choices.');
    }
    return QuranQuizQuestion(
      prompt: prompt,
      answer: answer,
      choices: List.unmodifiable(choices),
    );
  }
}

Uint8List pcm16ToWav(
  Uint8List samples, {
  int sampleRate = 16000,
  int channels = 1,
}) {
  if (sampleRate <= 0 || channels <= 0 || samples.length.isOdd) {
    throw ArgumentError(
        'PCM audio must use valid WAV parameters and 16-bit samples.');
  }
  final byteRate = sampleRate * channels * 2;
  final blockAlign = channels * 2;
  final header = ByteData(44);
  void writeText(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      header.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  writeText(0, 'RIFF');
  header.setUint32(4, samples.length + 36, Endian.little);
  writeText(8, 'WAVE');
  writeText(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, 16, Endian.little);
  writeText(36, 'data');
  header.setUint32(40, samples.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(samples))
      .takeBytes();
}

class PaymentService {
  static const apiBaseUrl = String.fromEnvironment(
    'PAYMENTS_API_BASE_URL',
    defaultValue:
        'https://https-github-com-jayzu-creator-hifzai-1.onrender.com',
  );

  static String? get accessToken =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  static Future<PaymentCheckout> createCheckout(String plan) async {
    final token = accessToken;
    if (token == null) throw Exception('Sign in before choosing a plan.');
    final response = await http.post(
      Uri.parse('$apiBaseUrl/create-checkout'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'plan': plan}),
    );
    if (response.statusCode != 200) {
      throw Exception('Payment service returned HTTP ${response.statusCode}.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final redirectUrl = data['redirectUrl'] as String?;
    if (redirectUrl == null)
      throw Exception('Payment service returned no checkout URL.');
    return PaymentCheckout(
      id: data['checkoutId'] as String,
      amount: data['amount'] as int,
      currency: data['currency'] as String,
      redirectUrl: Uri.parse(redirectUrl),
    );
  }

  static Future<void> launchCheckout(String plan) async {
    final checkout = await createCheckout(plan);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) throw Exception('Sign in again before paying.');
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('pending_yoco_checkout_id', checkout.id);
    await preferences.setInt('pending_yoco_amount', checkout.amount);
    await preferences.setString('pending_yoco_user_id', userId);
    final opened = await launchUrl(
      checkout.redirectUrl,
      mode: LaunchMode.platformDefault,
    );
    if (!opened) {
      await preferences.remove('pending_yoco_checkout_id');
      await preferences.remove('pending_yoco_amount');
      await preferences.remove('pending_yoco_user_id');
      throw Exception('The Yoco checkout could not be opened.');
    }
  }

  static Future<PaymentStatus> getStatus(String checkoutId) async {
    final token = accessToken;
    if (token == null) throw Exception('Sign in again to verify your payment.');
    final response = await http.get(
      Uri.parse('$apiBaseUrl/checkout/${Uri.encodeComponent(checkoutId)}'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
          'Payment status check returned HTTP ${response.statusCode}.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return PaymentStatus(
      id: data['checkoutId'] as String,
      status: data['status'] as String,
      amount: data['amount'] as int,
      currency: data['currency'] as String,
      paymentId: data['paymentId'] as String?,
      entitlement: data['entitlement'] as Map<String, dynamic>?,
    );
  }

  static Future<Map<String, dynamic>> getEntitlement() async {
    final token = accessToken;
    if (token == null) throw Exception('Sign in to load your plan.');
    final response = await http.get(
      Uri.parse('$apiBaseUrl/me/entitlement'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw Exception('Plan status returned HTTP ${response.statusCode}.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<bool> isRecitationAvailable() async {
    final response = await http.get(Uri.parse('$apiBaseUrl/features'));
    if (response.statusCode != 200) {
      throw Exception('Feature status returned HTTP ${response.statusCode}.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['recitationEnabled'] == true;
  }

  static Future<void> saveAyahProgress({
    required int surahId,
    required int ayahNumber,
    required bool remembered,
  }) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw Exception('Sign in again to save your progress.');
    await client.from('ayah_progress').upsert(
      {
        'user_id': userId,
        'surah_id': surahId,
        'ayah_number': ayahNumber,
        'status': remembered ? 'remembered' : 'needs_revision',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id,surah_id,ayah_number',
    );
  }

  static Future<List<Map<String, dynamic>>> getAyahProgress() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw Exception('Sign in again to load your progress.');
    final rows = await client
        .from('ayah_progress')
        .select('surah_id, ayah_number, status, updated_at')
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<Map<String, dynamic>> checkRecitation({
    required int surahId,
    required int ayahNumber,
    required Uint8List wavAudio,
  }) async {
    final token = accessToken;
    if (token == null) throw Exception('Sign in before checking recitation.');
    final response = await http.post(
      Uri.parse(
          '$apiBaseUrl/recitation/check?surahId=$surahId&ayahNumber=$ayahNumber'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'audio/wav',
      },
      body: wavAudio,
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Recitation check failed.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

class PaymentCheckout {
  final String id;
  final int amount;
  final String currency;
  final Uri redirectUrl;

  const PaymentCheckout({
    required this.id,
    required this.amount,
    required this.currency,
    required this.redirectUrl,
  });
}

class PaymentStatus {
  final String id;
  final String status;
  final int amount;
  final String currency;
  final String? paymentId;
  final Map<String, dynamic>? entitlement;

  const PaymentStatus({
    required this.id,
    required this.status,
    required this.amount,
    required this.currency,
    required this.paymentId,
    this.entitlement,
  });

  bool confirms(int expectedAmount) =>
      status == 'completed' &&
      amount == expectedAmount &&
      currency == 'ZAR' &&
      paymentId != null &&
      entitlement != null;
}

class HifzAIApp extends StatelessWidget {
  const HifzAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HifzAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: C.emeraldDark,
        colorScheme: const ColorScheme.dark(
          primary: C.gold,
          surface: C.emerald,
          onSurface: C.cream,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      return const SetupRequiredScreen();
    }
    final client = Supabase.instance.client;
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        client.auth.currentSession,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Scaffold(
            backgroundColor: C.emeraldDark,
            body: Center(child: CircularProgressIndicator(color: C.gold)),
          );
        }
        if (snapshot.data?.session == null) return const SignInScreen();
        return const PaymentReturnGate();
      },
    );
  }
}

class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.emeraldDark,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'HifzAI account services are not configured yet. Add the Supabase project URL and public anon key to the web build settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.cream.withOpacity(0.85), height: 1.5),
            ),
          ),
        ),
      );
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool createAccount = false;
  bool loading = false;
  String? message;

  Future<void> submit() async {
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (createAccount) {
        final response = await auth.signUp(
          email: emailController.text.trim(),
          password: passwordController.text,
          emailRedirectTo: Uri.base.origin + Uri.base.path,
        );
        if (response.session == null && mounted) {
          setState(() => message = AppLanguage.t(
                'Check your email to confirm your account, then sign in.',
                'تحقق من بريدك الإلكتروني لتأكيد الحساب ثم سجّل الدخول.',
              ));
        }
      } else {
        await auth.signInWithPassword(
          email: emailController.text.trim(),
          password: passwordController.text,
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => message = error.message);
    } catch (error) {
      if (mounted)
        setState(() => message = 'Could not complete sign-in: $error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.emeraldDark,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListView(
                padding: const EdgeInsets.all(24),
                shrinkWrap: true,
                children: [
                  const Icon(Icons.menu_book_rounded, size: 68, color: C.gold),
                  const SizedBox(height: 16),
                  Text(
                    AppLanguage.t(
                      createAccount
                          ? 'Create your HifzAI account'
                          : 'Sign in to HifzAI',
                      createAccount
                          ? 'أنشئ حساب HifzAI'
                          : 'سجّل الدخول إلى HifzAI',
                    ),
                    textAlign: TextAlign.center,
                    style: serif(28, w: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLanguage.t(
                      'Your account keeps your plan and learning progress with you.',
                      'يحفظ حسابك خطتك وتقدمك في التعلم.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: C.cream.withOpacity(0.75)),
                  ),
                  const SizedBox(height: 26),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 12),
                    Text(message!, style: const TextStyle(color: C.goldLight)),
                  ],
                  const SizedBox(height: 20),
                  GoldButton(
                    label: loading
                        ? AppLanguage.t('Please wait…', 'يرجى الانتظار…')
                        : AppLanguage.t(
                            createAccount ? 'Create account' : 'Sign in',
                            createAccount ? 'إنشاء حساب' : 'تسجيل الدخول',
                          ),
                    icon: createAccount ? Icons.person_add_alt_1 : Icons.login,
                    onPressed: loading ? () {} : submit,
                  ),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => setState(() {
                              createAccount = !createAccount;
                              message = null;
                            }),
                    child: Text(AppLanguage.t(
                      createAccount
                          ? 'Already have an account? Sign in'
                          : 'New here? Create an account',
                      createAccount
                          ? 'لديك حساب؟ سجّل الدخول'
                          : 'جديد هنا؟ أنشئ حساباً',
                    )),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class PaymentReturnGate extends StatelessWidget {
  const PaymentReturnGate({super.key});

  @override
  Widget build(BuildContext context) {
    final paymentResult = Uri.base.queryParameters['payment'];
    if (paymentResult == 'success' ||
        paymentResult == 'cancelled' ||
        paymentResult == 'failed') {
      return PaymentReturnScreen(result: paymentResult!);
    }
    return const SplashScreen();
  }
}

class PaymentReturnScreen extends StatefulWidget {
  final String result;

  const PaymentReturnScreen({super.key, required this.result});

  @override
  State<PaymentReturnScreen> createState() => _PaymentReturnScreenState();
}

class _PaymentReturnScreenState extends State<PaymentReturnScreen> {
  PaymentStatus? paymentStatus;
  Object? error;
  bool checking = true;

  @override
  void initState() {
    super.initState();
    if (widget.result == 'success') {
      verifyPayment();
    } else {
      checking = false;
    }
  }

  Future<void> verifyPayment() async {
    setState(() {
      checking = true;
      error = null;
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      final checkoutId = preferences.getString('pending_yoco_checkout_id');
      final checkoutUserId = preferences.getString('pending_yoco_user_id');
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (checkoutId == null) {
        throw Exception('No pending checkout was found on this device.');
      }
      if (checkoutUserId == null || checkoutUserId != currentUserId) {
        throw Exception('Sign in to the account that started this checkout.');
      }

      PaymentStatus? latestStatus;
      for (var attempt = 0; attempt < 5; attempt++) {
        latestStatus = await PaymentService.getStatus(checkoutId);
        if (latestStatus.status == 'completed' ||
            latestStatus.status == 'failed') break;
        if (attempt < 4) await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (latestStatus == null)
        throw Exception('Payment status is not available.');

      final expectedAmount = preferences.getInt('pending_yoco_amount');
      if (expectedAmount == null || latestStatus.amount != expectedAmount) {
        throw Exception('The payment amount did not match the selected plan.');
      }
      if (latestStatus.confirms(expectedAmount)) {
        await preferences.remove('pending_yoco_checkout_id');
        await preferences.remove('pending_yoco_amount');
        await preferences.remove('pending_yoco_user_id');
      }
      if (mounted) setState(() => paymentStatus = latestStatus);
    } catch (verificationError) {
      if (mounted) setState(() => error = verificationError);
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final success = paymentStatus?.confirms(
          paymentStatus?.amount ?? -1,
        ) ??
        false;
    final title = widget.result == 'cancelled'
        ? AppLanguage.t('Checkout cancelled', 'تم إلغاء الدفع')
        : widget.result == 'failed'
            ? AppLanguage.t('Payment was not completed', 'لم تكتمل عملية الدفع')
            : checking
                ? AppLanguage.t('Verifying payment…', 'جارٍ التحقق من الدفع…')
                : success
                    ? AppLanguage.t('Payment confirmed', 'تم تأكيد الدفع')
                    : AppLanguage.t(
                        'Payment needs checking', 'يحتاج الدفع إلى التحقق');
    final message = widget.result != 'success'
        ? AppLanguage.t(
            'No payment was confirmed. You can return to HifzAI and try again.',
            'لم يتم تأكيد أي دفعة. يمكنك العودة إلى HifzAI والمحاولة مرة أخرى.',
          )
        : checking
            ? AppLanguage.t(
                'Please wait while HifzAI securely checks the Yoco transaction.',
                'يرجى الانتظار بينما يتحقق HifzAI بأمان من معاملة Yoco.',
              )
            : success
                ? AppLanguage.t(
                    paymentStatus?.entitlement == null
                        ? 'Yoco confirmed the payment. Access is still being saved; check your plan status shortly.'
                        : 'Yoco confirmed your payment and your access period was saved to your account.',
                    paymentStatus?.entitlement == null
                        ? 'أكدت Yoco الدفع. ما زال حفظ الوصول جارياً؛ تحقق من حالة خطتك بعد قليل.'
                        : 'أكدت Yoco الدفع وتم حفظ فترة الوصول في حسابك.',
                  )
                : AppLanguage.t(
                    error?.toString() ??
                        'Yoco has not confirmed this payment yet. Do not pay again; retry the check shortly.',
                    error?.toString() ??
                        'لم تؤكد Yoco الدفع بعد. لا تدفع مرة أخرى؛ أعد التحقق بعد قليل.',
                  );

    return Scaffold(
      backgroundColor: C.emeraldDark,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  checking
                      ? Icons.hourglass_top_rounded
                      : success
                          ? Icons.verified_rounded
                          : Icons.info_outline_rounded,
                  color: C.goldLight,
                  size: 72,
                ),
                const SizedBox(height: 20),
                Text(title,
                    textAlign: TextAlign.center,
                    style: serif(30, w: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: C.cream.withOpacity(0.8), height: 1.5),
                ),
                const SizedBox(height: 24),
                if (checking)
                  const CircularProgressIndicator(color: C.gold)
                else ...[
                  if (widget.result == 'success' && !success)
                    GoldButton(
                      label: AppLanguage.t('Check again', 'تحقق مرة أخرى'),
                      icon: Icons.refresh_rounded,
                      onPressed: verifyPayment,
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const MainShell()),
                      (_) => false,
                    ),
                    child: Text(
                        AppLanguage.t('Return to HifzAI', 'العودة إلى HifzAI')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WifiGate extends StatefulWidget {
  final Widget child;

  const WifiGate({super.key, required this.child});

  @override
  State<WifiGate> createState() => _WifiGateState();
}

class _WifiGateState extends State<WifiGate> {
  final connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? subscription;
  bool? wifiAvailable;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    subscription = connectivity.onConnectivityChanged.listen((results) {
      if (mounted) {
        setState(
            () => wifiAvailable = results.contains(ConnectivityResult.wifi));
      }
    });
  }

  Future<void> _checkConnection() async {
    final results = await connectivity.checkConnectivity();
    if (mounted) {
      setState(() => wifiAvailable = results.contains(ConnectivityResult.wifi));
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (wifiAvailable == true) return widget.child;

    final checking = wifiAvailable == null;
    return Scaffold(
      backgroundColor: C.emeraldDark,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                checking ? Icons.wifi_find_rounded : Icons.wifi_off_rounded,
                size: 72,
                color: C.goldLight,
              ),
              const SizedBox(height: 20),
              Text('Support', style: serif(20, w: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                'Questions or feedback? Email ${AppInfo.supportEmail}.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.cream.withOpacity(0.75)),
              ),
              const SizedBox(height: 24),
              Text(
                checking ? 'Checking your connection…' : 'Wi-Fi is required',
                textAlign: TextAlign.center,
                style: serif(28, w: FontWeight.bold, color: C.cream),
              ),
              const SizedBox(height: 12),
              Text(
                checking
                    ? 'Please wait while HifzAI checks your network.'
                    : 'HifzAI is free to use, but it only loads Quran text over Wi-Fi. Connect to Wi-Fi and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.cream.withOpacity(.75), height: 1.5),
              ),
              if (!checking) ...[
                const SizedBox(height: 24),
                GoldButton(
                  label: 'Check Again',
                  icon: Icons.refresh_rounded,
                  onPressed: _checkConnection,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  Timer? navigationTimer;

  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  late final Animation<double> fade = CurvedAnimation(
    parent: controller,
    curve: Curves.easeIn,
  );

  @override
  void initState() {
    super.initState();
    controller.forward();
    navigationTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 800),
            pageBuilder: (_, __, ___) => const OnboardingScreen(),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    navigationTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [C.emerald, C.emeraldDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: FadeTransition(
          opacity: fade,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: C.gold, width: 3),
                    color: C.emeraldDark,
                  ),
                  child: const Icon(Icons.menu_book_rounded,
                      size: 74, color: C.goldLight),
                ),
                const SizedBox(height: 26),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Hifz',
                        style: serif(52, w: FontWeight.bold, color: C.cream),
                      ),
                      TextSpan(
                        text: 'AI',
                        style: serif(52, w: FontWeight.bold, color: C.gold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'MEMORISE • RECITE • MASTER',
                  style: serif(13, color: C.goldLight, spacing: 4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final controller = PageController();
  int pageIndex = 0;

  final slides = const [
    (
      icon: Icons.mic_rounded,
      title: 'Recite & Be Heard',
      desc:
          'Read the complete Quran and build a daily memorisation habit. Recitation checking will be added in a later release.'
    ),
    (
      icon: Icons.fact_check_rounded,
      title: 'Hifz Examination',
      desc:
          'Practice what comes next with four ayah choices from any Surah or the whole Quran.'
    ),
    (
      icon: Icons.workspace_premium_rounded,
      title: 'Never Forget the Word',
      desc:
          'Daily ayahs, streaks and revision reminders keep the Quran alive in your heart.'
    ),
  ];

  void next() {
    if (pageIndex == slides.length - 1) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
      return;
    }
    controller.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const MainShell()),
                ),
                child: const Text('Skip', style: TextStyle(color: C.goldLight)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: controller,
                onPageChanged: (index) => setState(() => pageIndex = index),
                itemCount: slides.length,
                itemBuilder: (_, index) {
                  final slide = slides[index];
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 202),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: C.gold.withOpacity(0.5), width: 2),
                                color: C.emerald.withOpacity(0.5),
                              ),
                              child: Icon(slide.icon,
                                  size: 64, color: C.goldLight),
                            ),
                            const SizedBox(height: 36),
                            Text(
                              slide.title,
                              textAlign: TextAlign.center,
                              style: serif(28, w: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              slide.desc,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: C.cream.withOpacity(0.75),
                                fontSize: 16,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(slides.length, (index) {
                final selected = pageIndex == index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: selected ? 26 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: selected ? C.gold : C.gold.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.all(28),
              child: GoldButton(
                label: pageIndex == slides.length - 1
                    ? 'Begin Your Journey'
                    : 'Next',
                icon: Icons.arrow_forward,
                onPressed: next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeScreen(),
      const ExaminerScreen(),
      const MoulanaScreen(),
      const ProgressScreen(),
    ];

    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.arabic,
      builder: (context, isArabic, _) => Scaffold(
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: screens[tab],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (index) => setState(() => tab = index),
          backgroundColor: C.emerald,
          indicatorColor: C.gold.withOpacity(0.25),
          destinations: [
            NavigationDestination(
                icon: const Icon(Icons.home_rounded),
                label: AppLanguage.t('Home', 'الرئيسية')),
            NavigationDestination(
                icon: const Icon(Icons.fact_check_rounded),
                label: AppLanguage.t('Examiner', 'الاختبار')),
            NavigationDestination(
                icon: const Icon(Icons.record_voice_over_rounded),
                label: AppLanguage.t('Moulana', 'المعلّم')),
            NavigationDestination(
                icon: const Icon(Icons.insights_rounded),
                label: AppLanguage.t('Progress', 'التقدم')),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text(
                              AppLanguage.t(
                                  'Assalamu ʿAlaykum', 'السلام عليكم'),
                              style: serif(30, w: FontWeight.bold))),
                      IconButton(
                        tooltip: AppLanguage.t('العربية', 'English'),
                        onPressed: () => AppLanguage.arabic.value =
                            !AppLanguage.arabic.value,
                        icon: const Icon(Icons.translate_rounded,
                            color: C.goldLight),
                      ),
                      IconButton(
                        tooltip: AppLanguage.t('Sign out', 'تسجيل الخروج'),
                        onPressed: () =>
                            Supabase.instance.client.auth.signOut(),
                        icon: const Icon(Icons.logout_rounded,
                            color: C.goldLight),
                      ),
                    ],
                  ),
                  Text(
                      AppLanguage.t(
                          'Read, learn and memorise — free for everyone.',
                          'اقرأ وتعلّم واحفظ — مجاناً للجميع.'),
                      style: TextStyle(color: C.goldLight.withOpacity(0.9))),
                  const SizedBox(height: 18),
                  const AyahCard(),
                  const SizedBox(height: 18),
                  const FreeServiceBanner(),
                  const SizedBox(height: 22),
                  Text(AppLanguage.t('Choose a Surah', 'اختر سورة'),
                      style: serif(21, w: FontWeight.w600)),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 210,
                childAspectRatio: 1.05,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => SurahTile(
                  surah: D.surahs[index],
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => SurahScreen(surah: D.surahs[index])),
                  ),
                ),
                childCount: D.surahs.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AyahCard extends StatefulWidget {
  const AyahCard({super.key});

  @override
  State<AyahCard> createState() => _AyahCardState();
}

class _AyahCardState extends State<AyahCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [C.goldLight, C.gold],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: C.gold.withOpacity(0.3),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wb_sunny_rounded, color: C.emeraldDark),
                const SizedBox(width: 8),
                Text('Ayah of the Day',
                    style: serif(17, w: FontWeight.bold, color: C.emeraldDark)),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              D.ayahOfDay(),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 26, color: C.emeraldDark, height: 1.9),
            ),
            const SizedBox(height: 8),
            Text(
              '“Verily, in the remembrance of Allah do hearts find rest.”',
              style: TextStyle(
                fontSize: 12,
                color: C.emeraldDark.withOpacity(0.8),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
      builder: (_, child) => Transform.translate(
        offset: Offset(0, 4 * controller.value),
        child: child,
      ),
    );
  }
}

class FreeServiceBanner extends StatelessWidget {
  const FreeServiceBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.emerald.withOpacity(0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.gold.withOpacity(0.6), width: 1.4),
      ),
      child: const Row(
        children: [
          Icon(Icons.public_rounded, color: C.gold, size: 34),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Live Quran text • No account • Core reading free',
              style: TextStyle(color: C.cream),
            ),
          ),
        ],
      ),
    );
  }
}

class SurahTile extends StatelessWidget {
  final Surah surah;
  final VoidCallback onTap;

  const SurahTile({super.key, required this.surah, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: C.emerald.withOpacity(0.5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: C.gold.withOpacity(0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(surah.arabic,
                style: const TextStyle(
                    fontSize: 30, color: C.goldLight, height: 1.6)),
            Text(surah.name, style: serif(17, w: FontWeight.w600)),
            Text('${surah.ayahs} ayahs',
                style:
                    TextStyle(fontSize: 12, color: C.cream.withOpacity(0.65))),
          ],
        ),
      ),
    );
  }
}

class SurahScreen extends StatefulWidget {
  final Surah surah;

  const SurahScreen({super.key, required this.surah});

  @override
  State<SurahScreen> createState() => _SurahScreenState();
}

class _SurahScreenState extends State<SurahScreen> {
  late Future<List<QuranAyah>> ayahs;

  @override
  void initState() {
    super.initState();
    ayahs = QuranService.fetchSurah(widget.surah.id);
  }

  void retry() {
    setState(() => ayahs = QuranService.fetchSurah(widget.surah.id));
  }

  Future<void> openQuranSource() async {
    try {
      final opened = await launchUrl(Uri.parse('https://quran.com'));
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Quran.com.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open Quran.com: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.surah.name),
        backgroundColor: C.emeraldDark,
        foregroundColor: C.cream,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [C.emerald, C.emeraldDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Text(widget.surah.arabic,
                style: const TextStyle(
                    fontSize: 40, color: C.goldLight, height: 1.6)),
            Text('${widget.surah.ayahs} Ayahs',
                style: TextStyle(color: C.cream.withOpacity(0.7))),
            const SizedBox(height: 14),
            Expanded(
              child: FutureBuilder<List<QuranAyah>>(
                future: ayahs,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: C.gold));
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.menu_book_rounded,
                                color: C.goldLight, size: 48),
                            const SizedBox(height: 12),
                            const Text(
                              'The bundled Quran text could not be loaded. Please update or reinstall HifzAI.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: C.cream),
                            ),
                            const SizedBox(height: 16),
                            GoldButton(
                                label: 'Try Again',
                                icon: Icons.refresh_rounded,
                                onPressed: retry),
                          ],
                        ),
                      ),
                    );
                  }

                  final loadedAyahs = snapshot.data ?? const <QuranAyah>[];
                  return Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: loadedAyahs.length,
                          itemBuilder: (_, index) {
                            final ayah = loadedAyahs[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: C.emerald.withOpacity(0.45),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: C.goldLight,
                                    child: Text('${ayah.number}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: C.emeraldDark)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      ayah.text,
                                      textAlign: TextAlign.right,
                                      textDirection: TextDirection.rtl,
                                      style: const TextStyle(
                                          fontSize: 25, height: 2),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      TextButton.icon(
                        onPressed: openQuranSource,
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Uthmani Arabic text: Quran.com'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExaminerScreen extends StatelessWidget {
  const ExaminerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.verified_user_rounded, size: 68, color: C.gold),
          const SizedBox(height: 12),
          Center(
              child: Text(AppLanguage.t('Hifz Examiner', 'اختبار الحفظ'),
                  style: serif(30, w: FontWeight.bold))),
          const SizedBox(height: 10),
          Center(
            child: Text(
              AppLanguage.t(
                'Recall the next ayah by choosing from four Quran verses. Test any Surah or the whole Quran.',
                'استرجع الآية التالية باختيارها من أربعة خيارات. اختبر أي سورة أو القرآن كاملاً.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: C.cream.withOpacity(0.8)),
            ),
          ),
          const SizedBox(height: 26),
          _feature(
              Icons.menu_book_rounded,
              AppLanguage.t('Read every Surah', 'اقرأ كل السور'),
              AppLanguage.t(
                  'Open any of the 114 Surahs from Home. The complete Uthmani Quran is stored on your device.',
                  'افتح أي سورة من السور الـ114 من الرئيسية. القرآن العثماني كاملاً مخزن على جهازك.')),
          _feature(
              Icons.mic_none_rounded,
              AppLanguage.t('Recitation checking', 'فحص التلاوة'),
              AppLanguage.t(
                  'Record one ayah and receive an automated transcript comparison. It is an estimate, not Tajweed grading.',
                  'سجّل آية واحدة واحصل على مقارنة آلية للنص. إنها نتيجة تقديرية وليست تقييماً للتجويد.')),
          _feature(
              Icons.public_rounded,
              AppLanguage.t('Core reading is free', 'القراءة الأساسية مجانية'),
              AppLanguage.t(
                  'Read the Quran without an account. Optional plans will be connected to payments separately.',
                  'اقرأ القرآن بدون حساب. سيتم ربط الخطط الاختيارية بالدفع بشكل منفصل.')),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            icon: const Icon(Icons.home_rounded),
            label: Text(AppLanguage.t(
                'Choose a Surah from Home', 'اختر سورة من الرئيسية')),
            onPressed: () => Navigator.of(context).maybePop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: C.goldLight,
              minimumSize: const Size.fromHeight(54),
              side: const BorderSide(color: C.gold),
            ),
          ),
          const SizedBox(height: 12),
          GoldButton(
            label: AppLanguage.t('Check a Recitation', 'تحقق من التلاوة'),
            icon: Icons.mic_rounded,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RecitationCheckScreen()),
            ),
          ),
          const SizedBox(height: 12),
          GoldButton(
            label:
                AppLanguage.t('Start a Memorisation Test', 'ابدأ اختبار الحفظ'),
            icon: Icons.play_arrow_rounded,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MemorisationTestScreen()),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _feature(IconData icon, String title, String detail) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.emerald.withOpacity(0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: C.goldLight),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: C.cream)),
                Text(detail,
                    style: TextStyle(
                        fontSize: 13, color: C.cream.withOpacity(0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RecitationCheckScreen extends StatefulWidget {
  const RecitationCheckScreen({super.key});

  @override
  State<RecitationCheckScreen> createState() => _RecitationCheckScreenState();
}

class _RecitationCheckScreenState extends State<RecitationCheckScreen> {
  static const maxAudioBytes = 8 * 1024 * 1024;
  static const maxRecordingDuration = Duration(seconds: 30);

  final recorder = AudioRecorder();
  final audioChunks = <Uint8List>[];
  Surah selectedSurah = D.surahs.first;
  int selectedAyah = 1;
  bool consented = false;
  bool recording = false;
  bool checking = false;
  bool stopping = false;
  int recordingSampleRate = 16000;
  int recordedBytes = 0;
  Object? error;
  bool? recitationAvailable;
  Map<String, dynamic>? result;
  Uint8List? audio;
  StreamSubscription<Uint8List>? recordingSubscription;
  Completer<void>? recordingDone;
  Timer? recordingTimer;
  Object? streamError;

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    try {
      final available = await PaymentService.isRecitationAvailable();
      if (mounted) setState(() => recitationAvailable = available);
    } catch (availabilityError) {
      if (mounted) {
        setState(() {
          recitationAvailable = false;
          error = availabilityError;
        });
      }
    }
  }

  Future<void> startRecording() async {
    if (!consented || recitationAvailable != true) return;
    setState(() {
      error = null;
      result = null;
      audio = null;
      audioChunks.clear();
      recordedBytes = 0;
      streamError = null;
    });
    try {
      if (!await recorder.hasPermission()) {
        throw Exception('Microphone permission was not granted.');
      }
      recordingDone = Completer<void>();
      recordingSampleRate = 16000;
      await recorder.setOnConfigChanged((config) {
        recordingSampleRate = config.sampleRate;
      });
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      recordingSubscription = stream.listen(
        (chunk) {
          if (recordedBytes + chunk.length > maxAudioBytes - 44) {
            error =
                Exception('Recording is too large. Please try a shorter ayah.');
            unawaited(stopRecording());
          } else {
            audioChunks.add(chunk);
            recordedBytes += chunk.length;
          }
        },
        onError: (Object value) {
          streamError = value;
          if (recordingDone?.isCompleted == false) recordingDone!.complete();
        },
        onDone: () {
          if (recordingDone?.isCompleted == false) recordingDone!.complete();
        },
        cancelOnError: false,
      );
      recordingTimer = Timer(maxRecordingDuration, () {
        if (mounted && recording) unawaited(stopRecording());
      });
      if (mounted) setState(() => recording = true);
    } catch (recordError) {
      if (mounted) setState(() => error = recordError);
      await recorder.cancel();
    }
  }

  Future<void> stopRecording() async {
    if (!recording || stopping) return;
    setState(() {
      stopping = true;
      recording = false;
    });
    recordingTimer?.cancel();
    try {
      await recorder.stop();
      await recordingDone?.future.timeout(const Duration(seconds: 3));
      if (error != null) throw error!;
      if (streamError != null)
        throw Exception('Audio recording failed: $streamError');
      final builder = BytesBuilder(copy: false);
      for (final chunk in audioChunks) {
        builder.add(chunk);
      }
      final recorded = builder.takeBytes();
      if (recorded.isEmpty) {
        throw Exception('No usable audio was recorded. Please try again.');
      }
      final wav = pcm16ToWav(recorded, sampleRate: recordingSampleRate);
      if (mounted) setState(() => audio = wav);
    } catch (recordError) {
      await recorder.cancel();
      if (mounted) setState(() => error = recordError);
    } finally {
      recordingSubscription = null;
      recordingDone = null;
      if (mounted) setState(() => stopping = false);
    }
  }

  Future<void> submitRecording() async {
    final recorded = audio;
    if (recorded == null || checking) return;
    setState(() {
      checking = true;
      error = null;
      result = null;
    });
    try {
      final response = await PaymentService.checkRecitation(
        surahId: selectedSurah.id,
        ayahNumber: selectedAyah,
        wavAudio: recorded,
      );
      if (mounted) setState(() => result = response);
    } catch (checkError) {
      if (mounted) setState(() => error = checkError);
    } finally {
      audioChunks.clear();
      if (mounted) {
        setState(() {
          checking = false;
          audio = null;
        });
      }
    }
  }

  @override
  void dispose() {
    recordingTimer?.cancel();
    unawaited(recordingSubscription?.cancel());
    unawaited(recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ayahCount = selectedSurah.ayahs;
    final comparison = result?['comparison'] as Map<String, dynamic>?;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recitation check'),
        backgroundColor: C.emeraldDark,
        foregroundColor: C.cream,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Check one ayah', style: serif(28, w: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'After you submit, HifzAI sends your short WAV recording to its server and OpenAI for transcription. HifzAI does not save the audio. Transcription may be inaccurate and does not assess Tajweed.',
            style: TextStyle(color: C.cream.withOpacity(0.78), height: 1.5),
          ),
          if (recitationAvailable != true) ...[
            const SizedBox(height: 12),
            Text(
              recitationAvailable == null
                  ? 'Checking recitation service availability…'
                  : 'Recitation checking is currently unavailable. Your microphone will not be activated.',
              style: const TextStyle(color: C.goldLight),
            ),
            if (error != null)
              TextButton.icon(
                onPressed: _loadAvailability,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Check again'),
              ),
          ],
          const SizedBox(height: 18),
          DropdownButtonFormField<Surah>(
            value: selectedSurah,
            decoration: const InputDecoration(labelText: 'Surah'),
            items: D.surahs
                .map((surah) =>
                    DropdownMenuItem(value: surah, child: Text(surah.name)))
                .toList(),
            onChanged: recording || checking
                ? null
                : (surah) {
                    if (surah != null) {
                      setState(() {
                        selectedSurah = surah;
                        selectedAyah = 1;
                        audio = null;
                        result = null;
                      });
                    }
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: selectedAyah,
            decoration: const InputDecoration(labelText: 'Ayah'),
            items: List.generate(
              ayahCount,
              (index) => DropdownMenuItem(
                value: index + 1,
                child: Text('${index + 1}'),
              ),
            ),
            onChanged: recording || checking
                ? null
                : (ayah) {
                    if (ayah != null) {
                      setState(() {
                        selectedAyah = ayah;
                        audio = null;
                        result = null;
                      });
                    }
                  },
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: consented,
            onChanged: recording || checking
                ? null
                : (value) => setState(() => consented = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I agree to record and send this recitation to OpenAI for automated transcription.',
              style: TextStyle(color: C.cream),
            ),
          ),
          const SizedBox(height: 8),
          if (recording)
            OutlinedButton.icon(
              onPressed: stopping ? null : stopRecording,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(stopping ? 'Finishing recording…' : 'Stop recording'),
            )
          else
            GoldButton(
              label: stopping
                  ? 'Finishing recording…'
                  : audio == null
                      ? 'Record (up to 30 seconds)'
                      : 'Record again',
              icon: Icons.mic_rounded,
              onPressed: stopping ||
                      !consented ||
                      checking ||
                      recitationAvailable != true
                  ? null
                  : startRecording,
            ),
          if (audio != null && !recording) ...[
            const SizedBox(height: 10),
            GoldButton(
              label: checking ? 'Checking…' : 'Send for transcription',
              icon: Icons.cloud_upload_outlined,
              onPressed: checking ? null : submitRecording,
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 14),
            Text('$error', style: const TextStyle(color: C.goldLight)),
          ],
          if (checking) ...[
            const SizedBox(height: 18),
            const Center(child: CircularProgressIndicator(color: C.gold)),
          ],
          if (result != null) ...[
            const SizedBox(height: 20),
            _resultCard(
                'Transcription', result!['transcript'] as String? ?? ''),
            _resultCard(
                'Quran reference', result!['reference'] as String? ?? '',
                rtl: true),
            if (comparison != null)
              _resultCard(
                'Estimated word similarity',
                '${comparison['estimatedSimilarityPercent']}% '
                    '(${result!['checksUsed']} of ${result!['checksLimit']} checks used)',
              ),
            Text(
              result!['disclaimer'] as String? ?? '',
              style: TextStyle(color: C.cream.withOpacity(0.7), height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultCard(String title, String content, {bool rtl = false}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.emerald.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: C.goldLight)),
          const SizedBox(height: 8),
          Text(
            content,
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            style: const TextStyle(color: C.cream, height: 1.7),
          ),
        ],
      ),
    );
  }
}

class MemorisationTestScreen extends StatefulWidget {
  const MemorisationTestScreen({super.key});

  @override
  State<MemorisationTestScreen> createState() => _MemorisationTestScreenState();
}

class _MemorisationTestScreenState extends State<MemorisationTestScreen> {
  static const questionCount = 10;

  int selectedSurahId = 0;
  QuranQuizQuestion? question;
  int questionNumber = 0;
  int? selectedChoice;
  int correct = 0;
  bool answered = false;
  bool complete = false;

  void startTest() {
    setState(() {
      question = _newQuestion();
      questionNumber = 1;
      selectedChoice = null;
      correct = 0;
      answered = false;
      complete = false;
    });
  }

  QuranQuizQuestion _newQuestion() => QuranService.createNextAyahQuestion(
      selectedSurahId == 0 ? null : selectedSurahId);

  void checkAnswer() {
    final current = question;
    final choice = selectedChoice;
    if (current == null || choice == null || answered) return;
    final isCorrect = QuranService.isCorrectAnswer(current, choice);
    setState(() {
      answered = true;
      if (isCorrect) correct++;
    });
    if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
      PaymentService.saveAyahProgress(
        surahId: current.answer.surahId,
        ayahNumber: current.answer.number,
        remembered: isCorrect,
      ).catchError((Object saveError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Progress could not be saved: $saveError')),
          );
        }
      });
    }
  }

  void continueTest() {
    if (questionNumber == questionCount) {
      setState(() => complete = true);
      return;
    }
    setState(() {
      question = _newQuestion();
      questionNumber++;
      selectedChoice = null;
      answered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = question;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quran Memory Quiz'),
        backgroundColor: C.emeraldDark,
        foregroundColor: C.cream,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('What comes next?', style: serif(28, w: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Read the ayah, recall what follows, and choose the next ayah from four options. Questions use the complete bundled Quran.',
            style: TextStyle(color: C.cream.withOpacity(0.75)),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<int>(
            value: selectedSurahId,
            decoration: const InputDecoration(labelText: 'Surah'),
            items: [
              const DropdownMenuItem(
                  value: 0, child: Text('Whole Quran (random)')),
              ...D.surahs.map(
                (surah) => DropdownMenuItem(
                  value: surah.id,
                  child: Text('${surah.id}. ${surah.name}'),
                ),
              ),
            ],
            onChanged: question != null
                ? null
                : (surahId) {
                    if (surahId != null) {
                      setState(() => selectedSurahId = surahId);
                    }
                  },
          ),
          const SizedBox(height: 14),
          if (current == null)
            GoldButton(
              label: 'Start 10-question quiz',
              icon: Icons.play_arrow_rounded,
              onPressed: startTest,
            )
          else if (complete)
            _result()
          else ...[
            Text(
              'Question $questionNumber of $questionCount • $correct correct',
              style: const TextStyle(color: C.goldLight),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: C.emerald.withOpacity(0.55),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${D.surahs[current.prompt.surahId - 1].name} • '
                    'Ayah ${current.prompt.number}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: C.goldLight),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    current.prompt.text,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(fontSize: 25, height: 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Which ayah comes immediately after this one?',
              style: TextStyle(color: C.cream, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...current.choices.indexed.map((entry) {
              final index = entry.$1;
              final ayah = entry.$2;
              final isCorrect = ayah.surahId == current.answer.surahId &&
                  ayah.number == current.answer.number;
              final selected = selectedChoice == index;
              final color = answered && isCorrect
                  ? Colors.green
                  : answered && selected
                      ? Colors.redAccent
                      : C.goldLight;
              return Card(
                color: answered && isCorrect
                    ? Colors.green.withValues(alpha: 0.22)
                    : answered && selected
                        ? Colors.red.withValues(alpha: 0.22)
                        : C.emerald.withOpacity(0.55),
                child: RadioListTile<int>(
                  value: index,
                  groupValue: selectedChoice,
                  activeColor: color,
                  onChanged: answered
                      ? null
                      : (value) => setState(() => selectedChoice = value),
                  title: Text(
                    ayah.text,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(fontSize: 19, height: 1.8),
                  ),
                  subtitle: Text(
                    '${D.surahs[ayah.surahId - 1].name} • Ayah ${ayah.number}',
                    style: TextStyle(color: C.cream.withOpacity(0.65)),
                  ),
                ),
              );
            }),
            if (answered)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  selectedChoice != null &&
                          current.choices[selectedChoice!].surahId ==
                              current.answer.surahId &&
                          current.choices[selectedChoice!].number ==
                              current.answer.number
                      ? 'Correct — this is the next ayah.'
                      : 'Not quite. The highlighted ayah is the next one.',
                  style: TextStyle(
                    color: selectedChoice != null &&
                            current.choices[selectedChoice!].surahId ==
                                current.answer.surahId &&
                            current.choices[selectedChoice!].number ==
                                current.answer.number
                        ? Colors.greenAccent
                        : C.goldLight,
                  ),
                ),
              ),
            GoldButton(
              label: answered
                  ? questionNumber == questionCount
                      ? 'See your result'
                      : 'Next question'
                  : 'Check answer',
              icon:
                  answered ? Icons.arrow_forward_rounded : Icons.check_rounded,
              onPressed: answered
                  ? continueTest
                  : selectedChoice == null
                      ? null
                      : checkAnswer,
            ),
          ],
        ],
      ),
    );
  }

  Widget _result() {
    return Column(
      children: [
        const Icon(Icons.celebration_rounded, color: C.gold, size: 56),
        const SizedBox(height: 10),
        Text('Quiz complete', style: serif(24, w: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'You got $correct out of $questionCount correct.',
          style: const TextStyle(color: C.cream),
        ),
        const SizedBox(height: 14),
        GoldButton(
          label: 'Try another quiz',
          icon: Icons.refresh_rounded,
          onPressed: startTest,
        ),
      ],
    );
  }
}

class MoulanaScreen extends StatefulWidget {
  const MoulanaScreen({super.key});

  @override
  State<MoulanaScreen> createState() => _MoulanaScreenState();
}

class _MoulanaScreenState extends State<MoulanaScreen> {
  final messages = <MapEntry<bool, String>>[
    const MapEntry(false,
        'Assalamu ʿAlaykum. This Tajweed guide explains foundational concepts such as madd and ghunnah.'),
  ];
  final controller = TextEditingController();

  void send() {
    final text = controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      messages.add(MapEntry(true, text));
      controller.clear();
    });

    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => messages.add(MapEntry(false, _reply(text))));
    });
  }

  String _reply(String raw) {
    final text = raw.toLowerCase();
    if (text.contains('test')) {
      return 'Bismillah. Open the Examiner tab and begin — I will listen to every ayah.';
    }
    if (text.contains('ghunnah')) {
      return 'Ghunnah is the nasalisation held for two counts on ن and م with shaddah. Say with me: إِنَّ.';
    }
    if (text.contains('madd')) {
      return 'Madd is elongation. A natural madd is two counts — e.g. the alif in قَالَ. Recite it and I will check your timing.';
    }
    return 'I can currently explain madd and ghunnah. Recitation analysis will be added after the Quran reader is complete.';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.record_voice_over_rounded, color: C.gold),
                const SizedBox(width: 8),
                Text('Tajweed Guide', style: serif(26, w: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: messages.length,
              itemBuilder: (_, index) => _bubble(messages[index]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    onSubmitted: (_) => send(),
                    style: const TextStyle(color: C.cream),
                    decoration: InputDecoration(
                      hintText: 'Ask your Moulana…',
                      hintStyle: TextStyle(color: C.cream.withOpacity(0.4)),
                      filled: true,
                      fillColor: C.emerald.withOpacity(0.55),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: send,
                  icon: const Icon(Icons.send_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: C.gold,
                    foregroundColor: C.emeraldDark,
                    minimumSize: const Size(52, 52),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(MapEntry<bool, String> message) {
    final isUser = message.key;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? C.gold : C.emerald.withOpacity(0.65),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.value,
          style: TextStyle(color: isUser ? C.emeraldDark : C.cream),
        ),
      ),
    );
  }
}

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  Future<Map<String, dynamic>>? entitlementFuture;
  Future<List<Map<String, dynamic>>>? progressFuture;
  bool startingCheckout = false;

  @override
  void initState() {
    super.initState();
    if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
      entitlementFuture = PaymentService.getEntitlement();
      progressFuture = PaymentService.getAyahProgress();
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(AppLanguage.t('Your Journey', 'رحلتك'),
                style: serif(28, w: FontWeight.bold)),
            if (entitlementFuture != null) ...[
              const SizedBox(height: 14),
              _accountPlanCard(entitlementFuture!),
            ],
            const SizedBox(height: 20),
            const Icon(Icons.menu_book_rounded, size: 64, color: C.gold),
            const SizedBox(height: 12),
            if (progressFuture == null)
              Text(
                'Account services are not configured for this build.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.cream.withOpacity(0.75)),
              )
            else
              _progressList(progressFuture!),
            const SizedBox(height: 20),
            Text(AppLanguage.t('HifzAI Plans', 'خطط HifzAI'),
                style: serif(24, w: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              AppLanguage.t(
                'Core Quran reading is free. Paid checkout is disabled while the service is being tested. One-time access periods will not renew automatically.',
                'قراءة القرآن الأساسية مجانية. الدفع معطل أثناء اختبار الخدمة. فترات الوصول المدفوعة لا تتجدد تلقائياً.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: C.cream.withOpacity(0.7)),
            ),
            const SizedBox(height: 14),
            _planCard(
              title: AppLanguage.t('HifzAI Free', 'HifzAI مجاني'),
              price: 'R0',
              period: AppLanguage.t('Free forever', 'مجاني دائماً'),
              status: AppLanguage.t('Available now', 'متاح الآن'),
              features: [
                AppLanguage.t(
                    'The complete Uthmani Quran: all 114 Surahs, available offline',
                    'القرآن العثماني كاملاً: 114 سورة، متاح دون اتصال'),
                AppLanguage.t('Self-guided ayah recall test',
                    'اختبار ذاتي لاسترجاع الآيات'),
                AppLanguage.t('Basic Tajweed learning guide',
                    'دليل أساسي لتعلّم التجويد'),
                AppLanguage.t('English and Arabic interface',
                    'واجهة بالإنجليزية والعربية'),
                AppLanguage.t('No ads in the current app',
                    'لا توجد إعلانات في التطبيق حالياً'),
                AppLanguage.t(
                    'Up to 3 estimated transcript comparisons per UTC day when recitation service is available',
                    'حتى 3 مقارنات تقديرية للنص يومياً بالتوقيت العالمي عند توفر خدمة التلاوة'),
                AppLanguage.t(
                    'Saved self-guided ayah recall and revision status',
                    'حفظ نتيجة استرجاع الآية ذاتياً وحالة المراجعة'),
                AppLanguage.t('Recitation service is not currently enabled',
                    'خدمة التلاوة غير مفعّلة حالياً'),
              ],
            ),
            const SizedBox(height: 12),
            _planCard(
              title: AppLanguage.t('HifzAI Plus', 'HifzAI بلس'),
              price: 'R199',
              period: AppLanguage.t(
                'one-time one-month access • R1,499 one-time for 12 months',
                'دفع لمرة واحدة لشهر • 1,499 راند لمرة واحدة لمدة 12 شهراً',
              ),
              status: AppLanguage.t(
                paidCheckoutEnabled
                    ? 'Available • one-time access, no auto-renewal'
                    : 'Coming soon',
                paidCheckoutEnabled
                    ? 'متاح • وصول بدفع لمرة واحدة دون تجديد تلقائي'
                    : 'قريباً',
              ),
              badge: AppLanguage.t('Recommended', 'موصى به'),
              features: [
                AppLanguage.t(
                    'Up to 50 estimated transcript comparisons per UTC month',
                    'مخطط: حتى 50 فحص تلاوة بالذكاء الاصطناعي شهرياً'),
                AppLanguage.t(
                    'Word-level transcript comparison is approximate, not advanced Tajweed grading',
                    'مقارنة الكلمات تقديرية وليست تقييماً متقدماً للتجويد'),
                AppLanguage.t(
                    'Planned: madd timing, ghunnah, qalqalah, ikhfa, and idgham feedback',
                    'مخطط: ملاحظات للمد والغنة والقلقلة والإخفاء والإدغام'),
                AppLanguage.t(
                    'Planned: makharij feedback where technically supported',
                    'مخطط: ملاحظات للمخارج حيثما أمكن تقنياً'),
                AppLanguage.t(
                    'Planned: Hifz tracking, revision sessions, and practice recommendations',
                    'مخطط: تتبع الحفظ وجلسات المراجعة وتوصيات التدريب'),
                AppLanguage.t(
                    'Planned: progress history, core AI tutor, and no ads',
                    'مخطط: سجل التقدم والمعلّم الذكي الأساسي وبدون إعلانات'),
              ],
              highlighted: true,
              choices: paidCheckoutEnabled
                  ? const [
                      MapEntry('R199 • one month', 'plus_monthly'),
                      MapEntry('R1,499 • 12 months', 'plus_yearly'),
                    ]
                  : const [],
              onChoose: _startCheckout,
              checkoutInProgress: startingCheckout,
            ),
            const SizedBox(height: 20),
            _planCard(
              title: AppLanguage.t('HifzAI Pro', 'HifzAI برو'),
              price: 'R299',
              period: AppLanguage.t(
                  'one-time one-month access, no automatic renewal',
                  'دفع لمرة واحدة لشهر دون تجديد تلقائي'),
              status: AppLanguage.t(
                paidCheckoutEnabled
                    ? 'Available • one-time access, no auto-renewal'
                    : 'Coming soon',
                paidCheckoutEnabled
                    ? 'متاح • وصول بدفع لمرة واحدة دون تجديد تلقائي'
                    : 'قريباً',
              ),
              features: [
                AppLanguage.t(
                    'Planned: up to 150 AI recitation checks per month',
                    'مخطط: حتى 150 فحص تلاوة بالذكاء الاصطناعي شهرياً'),
                AppLanguage.t('Planned: everything proposed for Plus',
                    'مخطط: جميع ميزات بلس المقترحة'),
                AppLanguage.t(
                    'Planned: more detailed pronunciation analysis and longer practice sessions',
                    'مخطط: تحليل أدق للنطق وجلسات تدريب أطول'),
                AppLanguage.t(
                    'Planned: advanced memorisation analytics and custom revision plans',
                    'مخطط: تحليلات متقدمة للحفظ وخطط مراجعة مخصصة'),
                AppLanguage.t(
                    'Planned: difficult-ayah tracking and weak-area identification',
                    'مخطط: تتبع الآيات الصعبة وتحديد مواطن الضعف'),
                AppLanguage.t(
                    'Planned: detailed performance reports, priority new features, and no ads',
                    'مخطط: تقارير أداء مفصلة وأولوية الميزات الجديدة وبدون إعلانات'),
              ],
              choices: paidCheckoutEnabled
                  ? const [MapEntry('R299 • one month', 'pro_monthly')]
                  : const [],
              onChoose: _startCheckout,
              checkoutInProgress: startingCheckout,
            ),
            const SizedBox(height: 20),
            Text(
              AppLanguage.t(
                'HifzAI supports your learning — it does not replace a qualified Quran teacher.',
                'يساعدك HifzAI في التعلم ولا يحل محل معلّم قرآن مؤهل.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: C.cream.withOpacity(0.5)),
            ),
          ],
        ),
      );

  Future<void> _startCheckout(String plan) async {
    if (startingCheckout) return;
    setState(() => startingCheckout = true);
    try {
      await PaymentService.launchCheckout(plan);
    } catch (checkoutError) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Checkout could not start: $checkoutError')),
        );
      }
    } finally {
      if (mounted) setState(() => startingCheckout = false);
    }
  }

  Widget _progressList(Future<List<Map<String, dynamic>>> future) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text('Could not load saved progress: ${snapshot.error}',
                style: const TextStyle(color: C.goldLight));
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(color: C.gold));
          }
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) {
            return Text(
              'Complete a self-guided ayah test to begin saving your progress.',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.cream.withOpacity(0.75)),
            );
          }
          final remembered =
              rows.where((row) => row['status'] == 'remembered').length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$remembered remembered • ${rows.length - remembered} to revise',
                style: const TextStyle(color: C.goldLight),
              ),
              const SizedBox(height: 8),
              ...rows.map((row) {
                final surahId = row['surah_id'] as int;
                final ayahNumber = row['ayah_number'] as int;
                final surah = D.surahs.where((item) => item.id == surahId);
                final surahName =
                    surah.isEmpty ? 'Surah $surahId' : surah.first.name;
                final needsRevision = row['status'] == 'needs_revision';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    needsRevision
                        ? Icons.replay_rounded
                        : Icons.check_circle_outline_rounded,
                    color: C.goldLight,
                  ),
                  title: Text('$surahName • Ayah $ayahNumber'),
                  subtitle: Text(
                    needsRevision ? 'Needs revision' : 'Remembered',
                    style: TextStyle(color: C.cream.withOpacity(0.7)),
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () => setState(
                    () => progressFuture = PaymentService.getAyahProgress()),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh progress'),
              ),
            ],
          );
        },
      );

  Widget _accountPlanCard(Future<Map<String, dynamic>> future) =>
      FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final expiresAt = data?['expiresAt'] as String?;
          final expiry =
              expiresAt == null ? null : DateTime.tryParse(expiresAt);
          final plan = data?['plan'] as String?;
          final message = snapshot.hasError
              ? 'Could not load saved plan: ${snapshot.error}'
              : snapshot.connectionState != ConnectionState.done
                  ? 'Loading your saved access…'
                  : plan == 'free'
                      ? 'Your account is on the Free plan.'
                      : 'Your ${plan?.toUpperCase()} access is saved until '
                          '${expiry?.toLocal().toString().split(' ').first ?? 'the expiry date'}.';
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: C.emerald.withOpacity(0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.gold.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined, color: C.goldLight),
                const SizedBox(width: 12),
                Expanded(
                    child:
                        Text(message, style: const TextStyle(color: C.cream))),
                IconButton(
                  tooltip: 'Refresh plan status',
                  onPressed: () => setState(() =>
                      entitlementFuture = PaymentService.getEntitlement()),
                  icon: const Icon(Icons.refresh_rounded, color: C.goldLight),
                ),
              ],
            ),
          );
        },
      );

  static Widget _planCard({
    required String title,
    required String price,
    required String period,
    required String status,
    required List<String> features,
    String? badge,
    bool highlighted = false,
    List<MapEntry<String, String>> choices = const [],
    void Function(String plan)? onChoose,
    bool checkoutInProgress = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.emerald.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? C.gold : C.gold.withOpacity(0.35),
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(title, style: serif(21, w: FontWeight.bold)),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: C.gold.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                              color: C.goldLight,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$price ${AppLanguage.t('•', '•')} $period',
                  style: const TextStyle(
                      color: C.goldLight, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(status,
                    style: TextStyle(
                        color: C.cream.withOpacity(0.65), fontSize: 13)),
                const SizedBox(height: 8),
                ...features.map((feature) => Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_outline,
                              color: C.goldLight, size: 17),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(feature,
                                  style: TextStyle(
                                      color: C.cream.withOpacity(0.85),
                                      height: 1.35))),
                        ],
                      ),
                    )),
                if (choices.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: choices
                          .map(
                            (choice) => OutlinedButton(
                              onPressed: checkoutInProgress || onChoose == null
                                  ? null
                                  : () => onChoose(choice.value),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: C.goldLight,
                                side: const BorderSide(color: C.gold),
                              ),
                              child: Text(
                                checkoutInProgress ? 'Opening…' : choice.key,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GoldButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const GoldButton(
      {super.key,
      required this.label,
      required this.icon,
      required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      style: FilledButton.styleFrom(
        backgroundColor: C.gold,
        foregroundColor: C.emeraldDark,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }
}
