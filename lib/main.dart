import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp();
  
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  
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

  // Added a blank placeholder at index 1 for the Menu button
  final List<String> _navUrls = [
    "https://gem-ai.top",
    "", 
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

  // Re-added the script to hide the web header
  final String hideHeaderScript = """
    var style = document.createElement('style');
    style.innerHTML = 'header, nav, .navbar, .mobile-header, #header { display: none !important; }';
    document.head.appendChild(style);
  """;

  @override
  void initState() {
    super.initState();
    
    _checkConnectivity();
    
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

  // Show Native Bottom Sheet Menu
  void _showNativeMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.monetization_on, color: Color(0xFF007BFF)),
                title: const Text('Pricing'),
                onTap: () {
                  Navigator.pop(context);
                  webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri("https://gem-ai.top/pricing")));
                },
              ),
              ListTile(
                leading: const Icon(Icons.help, color: Color(0xFF007BFF)),
                title: const Text('FAQs'),
                onTap: () {
                  Navigator.pop(context);
                  webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri("https://gem-ai.top/faqs")));
                },
              ),
              ListTile(
                leading: const Icon(Icons.article, color: Color(0xFF007BFF)),
                title: const Text('Blog'),
                onTap: () {
                  Navigator.pop(context);
                  webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri("https://gem-ai.top/blog")));
                },
              ),
              ListTile(
                leading: const Icon(Icons.contact_mail, color: Color(0xFF007BFF)),
                title: const Text('Contact'),
                onTap: () {
                  Navigator.pop(context);
                  webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri("https://gem-ai.top/contact")));
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.dark_mode, color: Colors.black87),
                title: const Text('Toggle Dark/Light Mode'),
                onTap: () async {
                  Navigator.pop(context);
                  // JavaScript to trigger your website's dark mode
                  await webViewController?.evaluateJavascript(source: """
                    var moonBtn = document.querySelector('.fa-moon, .moon-icon, [class*="moon"]');
                    if(moonBtn) { moonBtn.click(); } 
                    else { document.body.classList.toggle('dark-mode'); document.body.classList.toggle('dark'); }
                  """);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _onItemTapped(int index) {
    // If the user taps the Menu icon (index 1), show the popup instead of loading a URL
    if (index == 1) {
      _showNativeMenu(context);
      return;
    }
    
    setState(() {
      _selectedIndex = index;
    });
    webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(_navUrls[index])));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (webViewController != null) {
          bool canGoBack = await webViewController!.canGoBack();
          if (canGoBack) {
            webViewController!.goBack(); 
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
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
          type: BottomNavigationBarType.fixed, // Forces all 4 icons to display properly
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu),
              label: 'Menu',
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