import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Permission.storage.request();
  runApp(const GemAiApp());
}

class GemAiApp extends StatelessWidget {
  const GemAiApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gem AI',
      theme: ThemeData(
        primaryColor: const Color(0xFF007BFF),
        primarySwatch: Colors.blue,
      ),
      home: const WebViewScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({Key? key}) : super(key: key);

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;
  PullToRefreshController? pullToRefreshController;
  late StreamSubscription<List<ConnectivityResult>> subscription;

  bool isLoading = true;
  bool isOffline = false;
  int _selectedIndex = 0;

  final List<String> _navUrls = [
    "https://gem-ai.top",
    "https://gem-ai.top/register", 
    "https://gem-ai.top/login",   
  ];

  InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: true,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    iframeAllow: "camera; microphone",
    iframeAllowFullscreen: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    useShouldInterceptRequest: true,
  );

  final String hideHeaderScript = """
    var style = document.createElement('style');
    style.innerHTML = 'header, nav, .navbar, .mobile-header, #header { display: none !important; }';
    document.head.appendChild(style);
  """;

  @override
  void initState() {
    super.initState();
    
    // Check initial internet connection
    _checkConnectivity();
    
    // Listen for internet connection changes in real-time
    subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      setState(() {
        isOffline = result.contains(ConnectivityResult.none);
      });
    });

    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: const Color(0xFF007BFF),
      ),
      onRefresh: () async {
        webViewController?.reload();
      },
    );
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() {
      isOffline = result.contains(ConnectivityResult.none);
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(_navUrls[index])));
  }

  @override
  Widget build(BuildContext context) {
    // PopScope intercepts the Android hardware back button
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (webViewController != null) {
          bool canGoBack = await webViewController!.canGoBack();
          if (canGoBack) {
            webViewController!.goBack(); // Go back one page in the browser
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          // Switch between the Offline Screen and the actual Web App
          child: isOffline ? _buildOfflineScreen() : Stack(
            children: [
              InAppWebView(
                key: webViewKey,
                initialUrlRequest: URLRequest(url: WebUri(_navUrls[0])),
                initialSettings: settings,
                pullToRefreshController: pullToRefreshController,
                onWebViewCreated: (controller) {
                  webViewController = controller;
                },
                onLoadStart: (controller, url) {
                  setState(() { isLoading = true; });
                },
                onLoadStop: (controller, url) async {
                  pullToRefreshController?.endRefreshing();
                  setState(() { isLoading = false; });
                  await controller.evaluateJavascript(source: hideHeaderScript);
                },
                onDownloadStartRequest: (controller, downloadRequest) async {
                  final uri = downloadRequest.url;
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF007BFF)),
                      ),
                    )
                  : const SizedBox.shrink(),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_add),
              label: 'Register',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.login),
              label: 'Login',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: const Color(0xFF007BFF),
          unselectedItemColor: Colors.grey,
          onTap: _onItemTapped,
        ),
      ),
    );
  }

  // The custom layout for the No Internet screen
  Widget _buildOfflineScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, size: 80, color: Colors.grey),
          const SizedBox(height: 20),
          const Text(
            "No Internet Connection",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            "Please check your network settings.",
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007BFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30.0),
              ),
            ),
            onPressed: () async {
              await _checkConnectivity();
              if (!isOffline) {
                webViewController?.reload();
              }
            },
            child: const Text("Try Again", style: TextStyle(fontSize: 16)),
          )
        ],
      ),
    );
  }
}