import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/book_meta.dart';
import '../services/library.dart';

/// 搜书页：内置浏览器打开必应搜书，网页里触发 TXT 下载时
/// 拦截到应用内下载并导入书架（复用 Library 的编码识别与指纹查重）。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.active = true});

  /// 是否为当前选中的 Tab。不可见时暂停 WebView 的 JS/渲染计时器，
  /// 避免后台网页（广告、动画等）抢占资源，导致阅读页上下滚动掉帧。
  final bool active;

  @override
  State<SearchPage> createState() => SearchPageState();
}

class SearchPageState extends State<SearchPage> with WidgetsBindingObserver {
  static const String _homeUrl = 'https://cn.bing.com';
  static const Color _appBar = Color(0xFF16224E);
  static const Color _paper = Color(0xFFF5F1E9);
  static const Color _ink = Color(0xFF23284A);

  InAppWebViewController? _controller;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = false;
  bool _loadFailed = false;
  bool _downloading = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  final ValueNotifier<int> _received = ValueNotifier<int>(0);

  /// 主框架加载失败的 URL，重试时优先重载它而不是回到首页。
  WebUri? _lastFailedUrl;

  /// WebView 计时器是否已暂停（pauseTimers 是全局状态，只在状态翻转时调用）。
  bool _timersPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    _received.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      _setWebPaused(!widget.active);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _setWebPaused(true);
    } else if (state == AppLifecycleState.resumed) {
      _setWebPaused(!widget.active);
    }
  }

  /// 暂停 / 恢复 WebView 的 JS、布局与动画计时器（全局生效）。
  Future<void> _setWebPaused(bool paused) async {
    final InAppWebViewController? c = _controller;
    if (c == null || _timersPaused == paused) return;
    _timersPaused = paused;
    try {
      if (paused) {
        await c.pauseTimers();
      } else {
        await c.resumeTimers();
      }
    } catch (_) {
      // 页面尚未就绪时忽略，切回可见后会按当前状态自然恢复。
    }
  }

  /// 主框架返回键回调：WebView 还有历史时先回退。消费了返回键返回 true。
  Future<bool> maybeGoBack() async {
    final InAppWebViewController? c = _controller;
    if (c == null) return false;
    if (await c.canGoBack()) {
      await c.goBack();
      return true;
    }
    return false;
  }

  /// 刷新后退/前进按钮的可用状态（每次页面变化后调用）。
  Future<void> _syncNavState() async {
    final InAppWebViewController? c = _controller;
    if (c == null || !mounted) return;
    final bool back = await c.canGoBack();
    final bool forward = await c.canGoForward();
    if (!mounted) return;
    if (back != _canGoBack || forward != _canGoForward) {
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    }
  }

  void _search(String query) {
    final String q = query.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loadFailed = false;
      _loading = true;
    });
    _controller?.loadUrl(
      urlRequest: URLRequest(
        url: WebUri(
          'https://cn.bing.com/search?q=${Uri.encodeQueryComponent(q)}',
        ),
      ),
    );
  }

  // —— 网页 TXT 下载 → 导入书架 ——

  Future<void> _handleDownload(DownloadStartRequest request) async {
    if (_downloading) return;
    final String name = _resolveFileName(request);
    final bool looksTxt =
        name.toLowerCase().endsWith('.txt') ||
        (request.mimeType ?? '').contains('text');
    if (!looksTxt) {
      _toast('仅支持下载 TXT 文件');
      return;
    }
    _downloading = true;
    _received.value = 0;
    try {
      final Uint8List bytes = await _downloadBytes(request, name);
      if (!mounted) return;

      final Library library = Library.instance;
      final BookMeta? existing = library.findDuplicate(
        bytes.length,
        Library.contentFingerprint(bytes),
      );
      if (existing != null) {
        _toast('《${existing.title}》已在书架中');
        return;
      }
      // 与书架导入规则一致：自动归入当前选中的分类（null = 全部 → 未分类）。
      // 下载完成即给出「正在导入」反馈，避免后台解析期间用户感觉无响应。
      final int dot = name.lastIndexOf('.');
      final String displayTitle = dot > 0 ? name.substring(0, dot) : name;
      _toast('正在导入《$displayTitle》…');
      final BookMeta meta = await library.importBytes(
        originalName: name,
        bytes: bytes,
        category: library.preferredFilter ?? '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _toast('已导入《${meta.title}》，可在书架查看');
    } on _DownloadCancelled {
      // 用户取消，静默处理。
    } catch (e) {
      if (mounted) _toast('下载失败：$e');
    } finally {
      _downloading = false;
    }
  }

  String _resolveFileName(DownloadStartRequest request) {
    final String? suggested = request.suggestedFilename;
    if (suggested != null && suggested.trim().isNotEmpty) {
      return suggested.trim();
    }
    final String path = request.url.path;
    final int slash = path.lastIndexOf('/');
    final String last = slash >= 0 ? path.substring(slash + 1) : path;
    if (last.isNotEmpty) {
      return last;
    }
    return 'book_${DateTime.now().millisecondsSinceEpoch}.txt';
  }

  /// 用 Dart HttpClient 下载（WebView 自身无法处理下载请求）。
  /// 带上当前页面的 Referer 与 Cookie，规避常见防盗链。
  Future<Uint8List> _downloadBytes(
    DownloadStartRequest request,
    String fileName,
  ) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final HttpClientRequest req = await client.getUrl(request.url);
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Mobile Safari/537.36',
      );
      final WebUri? pageUrl = await _controller?.getUrl();
      if (pageUrl != null) {
        req.headers.set(HttpHeaders.refererHeader, pageUrl.toString());
        final List<Cookie> cookies = await CookieManager.instance().getCookies(
          url: pageUrl,
        );
        if (cookies.isNotEmpty) {
          req.headers.set(
            HttpHeaders.cookieHeader,
            cookies.map((Cookie c) => '${c.name}=${c.value}').join('; '),
          );
        }
      }
      final HttpClientResponse resp = await req.close();
      if (resp.statusCode != HttpStatus.ok) {
        throw '服务器返回 ${resp.statusCode}';
      }
      return await _readWithProgress(resp, fileName);
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> _readWithProgress(
    HttpClientResponse resp,
    String fileName,
  ) async {
    final int total = resp.contentLength >= 0 ? resp.contentLength : -1;
    final BytesBuilder builder = BytesBuilder(copy: false);
    int received = 0;
    bool cancelled = false;
    BuildContext? dialogCtx;
    // 极小文件可能在弹窗首帧前就下载完成，用 Completer 保证关闭动作
    // 一定发生在弹窗真正建立之后，否则弹窗会永久残留。
    final Completer<void> dialogShown = Completer<void>();

    if (!mounted) throw '页面已关闭';
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        dialogCtx = ctx;
        if (!dialogShown.isCompleted) dialogShown.complete();
        return AlertDialog(
          title: const Text('正在下载'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 16),
              ValueListenableBuilder<int>(
                valueListenable: _received,
                builder: (BuildContext context, int v, Widget? child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      LinearProgressIndicator(
                        value: total > 0 ? v / total : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        total > 0
                            ? '${_fmtBytes(v)} / ${_fmtBytes(total)}'
                            : _fmtBytes(v),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                cancelled = true;
                Navigator.of(ctx).pop();
              },
              child: const Text('取消'),
            ),
          ],
        );
      },
    );

    try {
      await for (final List<int> chunk in resp) {
        if (cancelled) throw const _DownloadCancelled();
        builder.add(chunk);
        received += chunk.length;
        _received.value = received;
      }
    } finally {
      if (!dialogShown.isCompleted) {
        // 弹窗尚未建立：等它出现（通常一个帧内），再关闭。
        await dialogShown.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
      }
      if (dialogCtx?.mounted ?? false) {
        Navigator.of(dialogCtx!).pop(); // 关闭进度弹窗
      }
    }
    return builder.takeBytes();
  }

  String _fmtBytes(int n) {
    if (n >= 1048576) return '${(n / 1048576).toStringAsFixed(1)} MB';
    if (n >= 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    return '$n B';
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  // —— 界面 ——

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        backgroundColor: _appBar,
        elevation: 0,
        titleSpacing: 12,
        title: TextField(
          controller: _searchCtrl,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          style: const TextStyle(fontSize: 15, color: _ink),
          decoration: InputDecoration(
            isDense: true,
            hintText: '在必应搜索想看的小说',
            hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            prefixIcon: Icon(
              Icons.search,
              size: 20,
              color: Colors.grey.shade600,
            ),
            filled: true,
            fillColor: _paper,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.only(right: 4),
        actions: <Widget>[
          IconButton(
            tooltip: '后退',
            iconSize: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: Icon(
              Icons.arrow_back_ios_new,
              size: 19,
              color: _canGoBack ? _paper : _paper.withValues(alpha: 0.35),
            ),
            onPressed: _canGoBack ? () => _controller?.goBack() : null,
          ),
          IconButton(
            tooltip: '前进',
            iconSize: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: Icon(
              Icons.arrow_forward_ios,
              size: 19,
              color: _canGoForward ? _paper : _paper.withValues(alpha: 0.35),
            ),
            onPressed: _canGoForward ? () => _controller?.goForward() : null,
          ),
          IconButton(
            tooltip: '刷新',
            iconSize: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: const Icon(Icons.refresh, size: 20, color: _paper),
            onPressed: () => _controller?.reload(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _loading
              ? const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: _appBar,
                  color: Color(0xFFD8B25E),
                )
              : const SizedBox(height: 2),
        ),
      ),
      body: _loadFailed ? _buildError() : _buildWebView(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.cloud_off, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('网页加载失败，请检查网络'),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {
              final WebUri retryUrl = _lastFailedUrl ?? WebUri(_homeUrl);
              setState(() {
                _loadFailed = false;
                _loading = true;
              });
              _controller?.loadUrl(urlRequest: URLRequest(url: retryUrl));
            },
            child: const Text('重新加载'),
          ),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_homeUrl)),
      initialSettings: InAppWebViewSettings(
        useHybridComposition: true,
        transparentBackground: false,
        supportZoom: false,
      ),
      onWebViewCreated: (InAppWebViewController c) {
        _controller = c;
        // 启动时若不在搜书 Tab（默认书架），WebView 一创建即冻结后台网页。
        if (!widget.active) _setWebPaused(true);
      },
      onLoadStart: (InAppWebViewController c, WebUri? url) {
        if (!mounted) return;
        setState(() {
          _loading = true;
          _loadFailed = false;
        });
        _syncNavState();
      },
      onLoadStop: (InAppWebViewController c, WebUri? url) {
        if (!mounted) return;
        setState(() => _loading = false);
        _syncNavState();
      },
      onUpdateVisitedHistory:
          (InAppWebViewController c, WebUri? url, bool? isReload) {
            _syncNavState();
          },
      onReceivedError:
          (
            InAppWebViewController c,
            WebResourceRequest request,
            WebResourceError error,
          ) {
            if (request.isForMainFrame != true || !mounted) return;
            setState(() {
              _loadFailed = true;
              _loading = false;
              _lastFailedUrl = request.url;
            });
          },
      onCreateWindow:
          (InAppWebViewController c, CreateWindowAction action) async {
            // target=_blank 的链接（部分搜索结果）也在本页打开。
            await c.loadUrl(urlRequest: action.request);
            return true;
          },
      onDownloadStartRequest:
          (InAppWebViewController c, DownloadStartRequest request) {
            _handleDownload(request);
          },
    );
  }
}

/// 用户主动取消下载，静默退出即可，不弹「下载失败」。
class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}
