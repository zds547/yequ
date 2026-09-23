import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bookshelf_page.dart';
import 'search_page.dart';

/// 主框架：底部「书架 / 搜书」双 Tab。
/// IndexedStack 保持两页状态（WebView 不会因切 Tab 重载，书架滚动位置也保留）。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<SearchPageState> _searchKey = GlobalKey<SearchPageState>();
  int _index = 0;

  /// 处理返回键：搜书页里先回退 WebView 历史，退无可退再退出应用。
  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop) return;
    final SearchPageState? search = _searchKey.currentState;
    if (_index == 1 && search != null && await search.maybeGoBack()) return;
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: <Widget>[
            const BookshelfPage(),
            SearchPage(key: _searchKey, active: _index == 1),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F1E9),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 12,
                spreadRadius: 0,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: NavigationBar(
            height: 64,
            elevation: 0,
            selectedIndex: _index,
            backgroundColor: const Color(0xFFF5F1E9),
            surfaceTintColor: const Color(0xFFF5F1E9),
            indicatorColor: const Color(0xFFD8B25E).withValues(alpha: 0.35),
            onDestinationSelected: (int i) => setState(() => _index = i),
            destinations: const <Widget>[
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined, color: Color(0xFF948D7C)),
                selectedIcon: Icon(Icons.menu_book, color: Color(0xFF16224E)),
                label: '书架',
              ),
              NavigationDestination(
                icon: Icon(
                  Icons.travel_explore_outlined,
                  color: Color(0xFF948D7C),
                ),
                selectedIcon: Icon(
                  Icons.travel_explore,
                  color: Color(0xFF16224E),
                ),
                label: '搜书',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
