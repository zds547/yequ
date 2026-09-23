import 'dart:async';

import 'package:flutter/material.dart';

import 'home_page.dart';

/// 应用内启动页：与系统 splash 同色的夜空底 + 星月书 Logo，
/// 停留片刻后淡入书架。保证在不渲染系统 splash 图标的定制 ROM 上
/// 也有一致的品牌启动体验。
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  Timer? _leaveTimer;

  static const Color _solidBase = Color(0xFF192350);
  static const Color _gradientTop = Color(0xFF263474);
  static const Color _gradientBottom = Color(0xFF0C122C);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    // 首帧保持与系统 splash 一致的纯色，随后渐入渐变与 Logo，避免跳变。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
    _leaveTimer = Timer(const Duration(milliseconds: 1300), _enterBookshelf);
  }

  void _enterBookshelf() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement<void, void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder:
            (
              BuildContext context,
              Animation<double> animation,
              Animation<double> secondary,
            ) => FadeTransition(opacity: animation, child: const HomePage()),
      ),
    );
  }

  @override
  void dispose() {
    _leaveTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const ColoredBox(color: _solidBase),
          FadeTransition(
            opacity: _fade,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[_gradientTop, _gradientBottom],
                ),
              ),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1.0).animate(_fade),
                child: Image.asset(
                  'assets/images/splash_logo.png',
                  width: 260,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
