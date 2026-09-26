import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const HifzAIApp());

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
  static const surahs = [
    Surah(1, 'Al-Fatiha', 'الفاتحة', 7),
    Surah(2, 'Al-Ikhlas', 'الإخلاص', 4),
    Surah(3, 'Al-Falaq', 'الفلق', 5),
    Surah(4, 'An-Nas', 'الناس', 6),
    Surah(5, 'Al-Kawthar', 'الكوثر', 3),
    Surah(6, 'Al-Asr', 'العصر', 3),
    Surah(7, 'Ad-Duhaa', 'الضحى', 11),
    Surah(8, 'Al-Mulk', 'الملك', 30),
    Surah(9, 'Ya-Sin', 'يس', 83),
    Surah(10, 'Al-Kahf', 'الكهف', 110),
  ];

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
  final int number;
  final String text;

  const QuranAyah({required this.number, required this.text});
}

class QuranService {
  static Future<List<QuranAyah>> fetchSurah(int id) async {
    final response = await http.get(
      Uri.parse('https://api.alquran.cloud/v1/surah/$id/quran-uthmani'),
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw Exception('Quran service returned HTTP ${response.statusCode}.');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['code'] != 200) {
      throw Exception('Quran service returned an invalid response.');
    }

    final data = json['data'] as Map<String, dynamic>;
    final ayahs = data['ayahs'] as List<dynamic>;
    return ayahs.map((ayah) {
      final item = ayah as Map<String, dynamic>;
      return QuranAyah(
        number: item['numberInSurah'] as int,
        text: item['text'] as String,
      );
    }).toList(growable: false);
  }
}

class PaymentService {
  static const apiBaseUrl = String.fromEnvironment(
    'PAYMENTS_API_BASE_URL',
    defaultValue:
        'https://https-github-com-jayzu-creator-hifzai-1.onrender.com',
  );

  static Future<PaymentCheckout> createCheckout(String plan) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/create-checkout'),
      headers: const {'Content-Type': 'application/json'},
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

  static Future<PaymentStatus> getStatus(String checkoutId) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/checkout/${Uri.encodeComponent(checkoutId)}'),
      headers: const {'Accept': 'application/json'},
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
    );
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

  const PaymentStatus({
    required this.id,
    required this.status,
    required this.amount,
    required this.currency,
    required this.paymentId,
  });

  bool confirms(int expectedAmount) =>
      status == 'completed' && amount == expectedAmount && currency == 'ZAR';
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
      home: const PaymentReturnGate(),
    );
  }
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
    return const WifiGate(child: SplashScreen());
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
      if (checkoutId == null) {
        throw Exception('No pending checkout was found on this device.');
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
      if (latestStatus.status == 'completed') {
        await preferences.remove('pending_yoco_checkout_id');
        await preferences.remove('pending_yoco_amount');
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
                    'Yoco confirmed your payment. Paid plan features are not enabled in this release yet.',
                    'أكدت Yoco عملية الدفع. ميزات الخطة المدفوعة غير مفعّلة في هذا الإصدار بعد.',
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
                      MaterialPageRoute(
                          builder: (_) => const WifiGate(child: MainShell())),
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
          'Memorisation tests like a real examiner — “Continue from Ayah 12.” No mushaf, no hints.'
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
                            const Icon(Icons.cloud_off_rounded,
                                color: C.goldLight, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              'The Quran text could not be loaded. Check your internet connection and try again.',
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
                  return ListView.builder(
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
                                style: const TextStyle(fontSize: 25, height: 2),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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
                'The mushaf is hidden. Recite from memory — exactly like a real examination.',
                'المصحف مخفي. اقرأ من حفظك كما في الاختبار الحقيقي.',
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
                  'Open any Surah from Home and read the complete live Quran text.',
                  'افتح أي سورة من الرئيسية واقرأ نص القرآن كاملاً.')),
          _feature(
              Icons.mic_none_rounded,
              AppLanguage.t('Recitation checking', 'فحص التلاوة'),
              AppLanguage.t(
                  'Audio analysis is being built next. This version does not invent scores or feedback.',
                  'سيتم إضافة تحليل الصوت لاحقاً. هذا الإصدار لا يخترع درجات أو ملاحظات.')),
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

class MemorisationTestScreen extends StatefulWidget {
  const MemorisationTestScreen({super.key});

  @override
  State<MemorisationTestScreen> createState() => _MemorisationTestScreenState();
}

class _MemorisationTestScreenState extends State<MemorisationTestScreen> {
  Surah selectedSurah = D.surahs.first;
  Future<List<QuranAyah>>? ayahs;
  int ayahIndex = 0;
  bool answerVisible = false;
  int correct = 0;
  int needsRevision = 0;

  void startTest() {
    setState(() {
      ayahs = QuranService.fetchSurah(selectedSurah.id);
      ayahIndex = 0;
      answerVisible = false;
      correct = 0;
      needsRevision = 0;
    });
  }

  void mark(bool wasCorrect, List<QuranAyah> loadedAyahs) {
    setState(() {
      if (wasCorrect) {
        correct++;
      } else {
        needsRevision++;
      }
      answerVisible = false;
      if (ayahIndex < loadedAyahs.length - 1) {
        ayahIndex++;
      } else {
        ayahs = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ayahs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memorisation Test'),
        backgroundColor: C.emeraldDark,
        foregroundColor: C.cream,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Test yourself', style: serif(28, w: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Choose a Surah, recite from memory, then reveal the ayah to check yourself.',
            style: TextStyle(color: C.cream.withOpacity(0.75)),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<Surah>(
            value: selectedSurah,
            decoration: const InputDecoration(labelText: 'Surah'),
            items: D.surahs
                .map((surah) =>
                    DropdownMenuItem(value: surah, child: Text(surah.name)))
                .toList(),
            onChanged: (surah) {
              if (surah != null) setState(() => selectedSurah = surah);
            },
          ),
          const SizedBox(height: 14),
          GoldButton(
              label: 'Load Test',
              icon: Icons.download_rounded,
              onPressed: startTest),
          if (loaded != null) ...[
            const SizedBox(height: 24),
            FutureBuilder<List<QuranAyah>>(
              future: loaded,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: C.gold));
                }
                if (snapshot.hasError) {
                  return const Text(
                    'The test could not be loaded. Check your connection and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: C.cream),
                  );
                }
                final items = snapshot.data ?? const <QuranAyah>[];
                if (items.isEmpty || ayahIndex >= items.length) {
                  return _result();
                }
                final ayah = items[ayahIndex];
                return Column(
                  children: [
                    Text(
                      'Ayah ${ayah.number} of ${items.length}',
                      style: TextStyle(color: C.goldLight.withOpacity(0.9)),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: C.emerald.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: answerVisible
                          ? Text(
                              ayah.text,
                              textAlign: TextAlign.right,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(fontSize: 25, height: 2),
                            )
                          : const Text(
                              'Recite this ayah from memory, then reveal the answer.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: C.cream, height: 1.5),
                            ),
                    ),
                    const SizedBox(height: 14),
                    if (!answerVisible)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => answerVisible = true),
                        icon: const Icon(Icons.visibility_rounded),
                        label: const Text('Reveal Ayah'),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => mark(false, items),
                              child: const Text('Needs revision'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => mark(true, items),
                              child: const Text('I remembered it'),
                            ),
                          ),
                        ],
                      ),
                  ],
                );
              },
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
        Text('Test complete', style: serif(24, w: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('$correct remembered • $needsRevision to revise',
            style: const TextStyle(color: C.cream)),
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
  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(AppLanguage.t('Your Journey', 'رحلتك'),
                style: serif(28, w: FontWeight.bold)),
            const SizedBox(height: 20),
            const Icon(Icons.menu_book_rounded, size: 64, color: C.gold),
            const SizedBox(height: 12),
            Text(
              AppLanguage.t(
                'Your reading progress will appear here once bookmarks and revision tracking are enabled.',
                'سيظهر تقدم القراءة هنا عند تفعيل العلامات وتتبع المراجعة.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: C.cream),
            ),
            const SizedBox(height: 20),
            Text(AppLanguage.t('HifzAI Plans', 'خطط HifzAI'),
                style: serif(24, w: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              AppLanguage.t(
                'Core Quran reading is free. Paid features are being built and are not available to buy yet.',
                'قراءة القرآن الأساسية مجانية. الميزات المدفوعة قيد التطوير وغير متاحة للشراء حالياً.',
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
                AppLanguage.t('Live Quran text for the listed Surahs',
                    'نص القرآن المباشر للسور المدرجة'),
                AppLanguage.t('Self-guided ayah recall test',
                    'اختبار ذاتي لاسترجاع الآيات'),
                AppLanguage.t('Basic Tajweed learning guide',
                    'دليل أساسي لتعلّم التجويد'),
                AppLanguage.t('English and Arabic interface',
                    'واجهة بالإنجليزية والعربية'),
                AppLanguage.t('No ads in the current app',
                    'لا توجد إعلانات في التطبيق حالياً'),
                AppLanguage.t('Planned: up to 3 AI recitation checks per day',
                    'مخطط: حتى 3 فحوص للتلاوة بالذكاء الاصطناعي يومياً'),
                AppLanguage.t(
                    'Planned: basic Hifz tracking, limited history, and revision tools',
                    'مخطط: تتبع أساسي للحفظ وسجل محدود وأدوات للمراجعة'),
                AppLanguage.t('AI recitation checks are not available yet',
                    'فحص التلاوة بالذكاء الاصطناعي غير متاح بعد'),
              ],
            ),
            const SizedBox(height: 12),
            _planCard(
              title: AppLanguage.t('HifzAI Plus', 'HifzAI بلس'),
              price: 'R199',
              period: AppLanguage.t(
                'per month • R1,499 per year (about R125/month)',
                'شهرياً • 1,499 راند سنوياً (حوالي 125 راند شهرياً)',
              ),
              status: AppLanguage.t(
                'Coming soon — recommended for focused learners',
                'قريباً — موصى به للمتعلمين الجادين',
              ),
              badge: AppLanguage.t('Recommended', 'موصى به'),
              features: [
                AppLanguage.t(
                    'Planned: up to 50 AI recitation checks per month',
                    'مخطط: حتى 50 فحص تلاوة بالذكاء الاصطناعي شهرياً'),
                AppLanguage.t(
                    'Planned: advanced Tajweed feedback and missing/wrong-word detection',
                    'مخطط: ملاحظات متقدمة للتجويد واكتشاف الكلمات الناقصة أو الخاطئة'),
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
            ),
            const SizedBox(height: 20),
            _planCard(
              title: AppLanguage.t('HifzAI Pro', 'HifzAI برو'),
              price: 'R299',
              period: AppLanguage.t('per month', 'شهرياً'),
              status: AppLanguage.t('Coming soon', 'قريباً'),
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

  static Widget _planCard({
    required String title,
    required String price,
    required String period,
    required String status,
    required List<String> features,
    String? badge,
    bool highlighted = false,
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
  final VoidCallback onPressed;

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
