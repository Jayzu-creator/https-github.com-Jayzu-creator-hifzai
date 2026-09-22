import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

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

TextStyle serif(double size, {FontWeight w = FontWeight.w500, Color? color, double? spacing}) {
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
      home: const WifiGate(child: SplashScreen()),
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
        setState(() => wifiAvailable = results.contains(ConnectivityResult.wifi));
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

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
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
                  child: const Icon(Icons.menu_book_rounded, size: 74, color: C.goldLight),
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
                  'MEMORISE â€¢ RECITE â€¢ MASTER',
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
      desc: 'Read the complete Quran and build a daily memorisation habit. Recitation checking will be added in a later release.'
    ),
    (
      icon: Icons.fact_check_rounded,
      title: 'Hifz Examination',
      desc: 'Memorisation tests like a real examiner â€” â€œContinue from Ayah 12.â€ No mushaf, no hints.'
    ),
    (
      icon: Icons.workspace_premium_rounded,
      title: 'Never Forget the Word',
      desc: 'Daily ayahs, streaks and revision reminders keep the Quran alive in your heart.'
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: C.gold.withOpacity(0.5), width: 2),
                            color: C.emerald.withOpacity(0.5),
                          ),
                          child: Icon(slide.icon, size: 64, color: C.goldLight),
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
                label: pageIndex == slides.length - 1 ? 'Begin Your Journey' : 'Next',
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

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: screens[tab],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) => setState(() => tab = index),
        backgroundColor: C.emerald,
        indicatorColor: C.gold.withOpacity(0.25),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.fact_check_rounded), label: 'Examiner'),
          NavigationDestination(icon: Icon(Icons.record_voice_over_rounded), label: 'Moulana'),
          NavigationDestination(icon: Icon(Icons.insights_rounded), label: 'Progress'),
        ],
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
                  Text('AssalÄmu Ê¿Alaykum', style: serif(30, w: FontWeight.bold)),
                  Text('Read, learn and memorise â€” free for everyone.', style: TextStyle(color: C.goldLight.withOpacity(0.9))),
                  const SizedBox(height: 18),
                  const AyahCard(),
                  const SizedBox(height: 18),
                  const FreeServiceBanner(),
                  const SizedBox(height: 22),
                  Text('Choose a Surah', style: serif(21, w: FontWeight.w600)),
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
                    MaterialPageRoute(builder: (_) => SurahScreen(surah: D.surahs[index])),
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

class _AyahCardState extends State<AyahCard> with SingleTickerProviderStateMixin {
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
                Text('Ayah of the Day', style: serif(17, w: FontWeight.bold, color: C.emeraldDark)),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              D.ayahOfDay(),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 26, color: C.emeraldDark, height: 1.9),
            ),
            const SizedBox(height: 8),
            Text(
              'â€œVerily, in the remembrance of Allah do hearts find rest.â€',
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
              'Live Quran text â€¢ No account â€¢ No subscription',
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
            Text(surah.arabic, style: const TextStyle(fontSize: 30, color: C.goldLight, height: 1.6)),
            Text(surah.name, style: serif(17, w: FontWeight.w600)),
            Text('${surah.ayahs} ayahs', style: TextStyle(fontSize: 12, color: C.cream.withOpacity(0.65))),
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
            Text(widget.surah.arabic, style: const TextStyle(fontSize: 40, color: C.goldLight, height: 1.6)),
            Text('${widget.surah.ayahs} Ayahs', style: TextStyle(color: C.cream.withOpacity(0.7))),
            const SizedBox(height: 14),
            Expanded(
              child: FutureBuilder<List<QuranAyah>>(
                future: ayahs,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: C.gold));
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off_rounded, color: C.goldLight, size: 48),
                            const SizedBox(height: 12),
                            const Text(
                              'The Quran text could not be loaded. Check your internet connection and try again.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: C.cream),
                            ),
                            const SizedBox(height: 16),
                            GoldButton(label: 'Try Again', icon: Icons.refresh_rounded, onPressed: retry),
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
                              child: Text('${ayah.number}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: C.emeraldDark)),
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
          Center(child: Text('Hifz Examiner', style: serif(30, w: FontWeight.bold))),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'The mushaf is hidden. Recite from memory â€” exactly like a real examination.',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.cream.withOpacity(0.8)),
            ),
          ),
          const SizedBox(height: 26),
          _feature(Icons.menu_book_rounded, 'Read every Surah', 'Open any Surah from Home and read the complete live Quran text.'),
          _feature(Icons.mic_none_rounded, 'Recitation checking', 'Audio analysis is being built next. This version does not invent scores or feedback.'),
          _feature(Icons.public_rounded, 'Free for everyone', 'No account, subscription or payment is required to read and learn.'),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            icon: const Icon(Icons.home_rounded),
            label: const Text('Choose a Surah from Home'),
            onPressed: () => Navigator.of(context).maybePop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: C.goldLight,
              minimumSize: const Size.fromHeight(54),
              side: const BorderSide(color: C.gold),
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
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: C.cream)),
                Text(detail, style: TextStyle(fontSize: 13, color: C.cream.withOpacity(0.7))),
              ],
            ),
          ),
        ],
      ),
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
    const MapEntry(false, 'AssalÄmu Ê¿Alaykum. This free Tajweed guide explains foundational concepts such as madd and ghunnah.'),
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
      return 'BismillÄh. Open the Examiner tab and begin â€” I will listen to every ayah.';
    }
    if (text.contains('ghunnah')) {
      return 'Ghunnah is the nasalisation held for two counts on Ù† and Ù… with shaddah. Say with me: Ø¥Ù†ÙŽÙ‘.';
    }
    if (text.contains('madd')) {
      return 'Madd is elongation. A natural madd is two counts â€” e.g. the alif in Ù‚ÙŽØ§Ù„ÙŽ. Recite it and I will check your timing.';
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
                      hintText: 'Ask your Moulanaâ€¦',
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
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
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

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Your Journey', style: serif(28, w: FontWeight.bold)),
            const SizedBox(height: 20),
            const Icon(Icons.menu_book_rounded, size: 64, color: C.gold),
            const SizedBox(height: 12),
            const Text(
              'Your reading progress will appear here once bookmarks and revision tracking are enabled.',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.cream),
            ),
            const SizedBox(height: 20),
            Text(
              'HifzAI supports your learning — it does not replace a qualified Quran teacher.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: C.cream.withOpacity(0.5)),
            ),
          ],
        ),
      );
}

class GoldButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const GoldButton({super.key, required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      style: FilledButton.styleFrom(
        backgroundColor: C.gold,
        foregroundColor: C.emeraldDark,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }
}
