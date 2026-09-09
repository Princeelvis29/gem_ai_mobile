import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp();
  
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
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
  bool isLoggedIn = false; // Tracks dynamic auth state
  int _selectedIndex = 0;

  // Dynamic URLs based on Auth State
  List<String> get _currentNavUrls {
    if (isLoggedIn) {
      return [
        "https://gem-ai.top",
        "", 
        "https://gem-ai.top/dashboard",
        "https://gem-ai.top/user/profile", // Fallback URL
      ];
    }
    return [
      "https://gem-ai.top",
      "", 
      "https://gem-ai.top/register", 
      "https://gem-ai.top/login",   
    ];
  }

  // Dynamic Bottom Nav Items based on Auth State
  List<BottomNavigationBarItem> get _navItems {
    if (isLoggedIn) {
      return const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.menu), label: 'Menu'),
        BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
      ];
    }
    return const [
      BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
      BottomNavigationBarItem(icon: Icon(Icons.menu), label: 'Menu'),
      BottomNavigationBarItem(icon: Icon(Icons.person_add), label: 'Register'),
      BottomNavigationBarItem(icon: Icon(Icons.login), label: 'Login'),
    ];
  }

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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Native Profile Header (Only shows if logged in)
                if (isLoggedIn) ...[
                  const SizedBox(height: 10),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF007BFF),
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: const Text('My Account', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Manage your profile and settings'),
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToProfile();
                    },
                  ),
                  const Divider(),
                ],
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
                    await webViewController?.evaluateJavascript(source: """
                      var themeIcon = document.querySelector('.fa-sun, .fa-moon');
                      if (themeIcon) {
                        var btn = themeIcon.closest('button') || themeIcon.parentElement;
                        if (btn) {
                          btn.click();
                        } else {
                          themeIcon.click();
                        }
                      } else {
                        document.body.classList.toggle('dark-mode');
                        document.body.classList.toggle('dark');
                      }
                    """);
                  },
                ),
                // Native Log Out Button (Only shows if logged in)
                if (isLoggedIn) ...[
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    onTap: () async {
                      Navigator.pop(context);
                      // Finds and securely submits the hidden Laravel logout form
                      await webViewController?.evaluateJavascript(source: """
                        var logoutForm = document.querySelector('form[action*="logout"]');
                        if(logoutForm) { logoutForm.submit(); }
                      """);
                    },
                  ),
                ],
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  void _navigateToProfile() {
    setState(() { _selectedIndex = 3; });
    // Safely attempt to click the web link first, fallback to standard URL if not found
    webViewController?.evaluateJavascript(source: """
      var profileLink = Array.from(document.querySelectorAll('a')).find(a => a.innerText.includes('Profile and Settings'));
      if (profileLink) profileLink.click();
      else window.location.href = '/user/profile';
    """);
  }

  void _onItemTapped(int index) {
    if (index == 1) {
      _showNativeMenu(context);
      return;
    }
    
    setState(() {
      _selectedIndex = index;
    });

    if (isLoggedIn && index == 3) {
      _navigateToProfile();
    } else {
      webViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(_currentNavUrls[index])));
    }
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
                initialUrlRequest: URLRequest(url: WebUri(_currentNavUrls[0])),
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
                  
                  // Intelligently check auth state by looking for the logout form
                  bool authCheck = await controller.evaluateJavascript(source: "document.querySelector('form[action*=\"logout\"]') !== null") ?? false;
                  
                  setState(() { 
                    isLoading = false; 
                    isLoggedIn = authCheck;
                  });

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
          type: BottomNavigationBarType.fixed,
          items: _navItems,
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