import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/splash_page.dart';
import 'services/library.dart';
import 'services/reader_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait(<Future<void>>[
    Library.instance.init(),
    ReaderSettings.instance.load(),
  ]);
  runApp(const ReaderApp());
}

class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '夜曲',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8D6E63)),
      ),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      // 非中英文环境统一回退中文，保证阅读器菜单为中文。
      localeResolutionCallback: (Locale? locale, Iterable<Locale> supported) {
        if (locale?.languageCode == 'en') return const Locale('en');
        return const Locale('zh');
      },
      home: const SplashPage(),
    );
  }
}
