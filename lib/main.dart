import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Added for Haptics and System Exits
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock orientation to portrait for a more controlled app experience
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);
  await Permission.storage.request();
  
  runApp(const GemAiApp());
}

class GemAiApp extends StatelessWidget {
  const GemAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gem AI',
      theme: ThemeData(
        primaryColor: const Color(0xFF007BFF),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const WebViewScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

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
  bool isLoggedIn = false; 
  bool isDarkMode = false;
  int _selectedIndex = 0;
  DateTime? currentBackPressTime; // For double-tap to exit

  List<String> get _currentNavUrls {
    if (isLoggedIn) {
      return [
        "https://gem-ai.top",
        "", 
        "https://gem-ai.top/dashboard",
        "https://gem-ai.top/profile", 
      ];
    }
    return [
      "https://gem-ai.top",
      "", 
      "https://gem-ai.top/register", 
      "https://gem-ai.top/login",   
    ];
  }

  List<BottomNavigationBarItem> get _navItems {
    if (isLoggedIn) {
      return const [
        BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Menu'),
        BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
        BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
      ];
    }
    return const [
      BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
      BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Menu'),
      BottomNavigationBarItem(icon: Icon(Icons.person_add_rounded), label: 'Register'),
      BottomNavigationBarItem(icon: Icon(Icons.login_rounded), label: 'Login'),
    ];
  }

  final String _nativeStyles = """
    var style = document.createElement('style');
    style.innerHTML = `
      header, nav, footer, .navbar, .mobile-header, #header, #footer { display: none !important; }
      body { 
        overscroll-behavior-y: none;
        -webkit-touch-callout: none !important; 
        -webkit-user-select: none !important; 
        user-select: none !important; 
        -webkit-tap-highlight-color: transparent !important;
      }
      input, textarea { 
        -webkit-user-select: auto !important; 
        user-select: auto !important; 
      }
      /* Hide web scrollbars for a cleaner native look */
      ::-webkit-scrollbar { display: none; }
    `;
    if(document.head) {
       document.head.appendChild(style);
    } else {
       document.documentElement.appendChild(style);
    }
  """;

  late InAppWebViewSettings settings;

  @override
  void initState() {
    super.initState();
    
    settings = InAppWebViewSettings(
      isInspectable: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      iframeAllow: "camera; microphone",
      iframeAllowFullscreen: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      useShouldInterceptRequest: true,
      transparentBackground: true, 
      supportZoom: false, // Prevents pinch-to-zoom
      builtInZoomControls: false,
      displayZoomControls: false,
      disableContextMenu: true, // Prevents long-press web menus
      overScrollMode: OverScrollMode.NEVER, // Kills Android webview stretch effect
    );

    _checkConnectivity();
    subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      setState(() => isOffline = result.contains(ConnectivityResult.none));
    });

    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: const Color(0xFF007BFF)),
      onRefresh: () async {
        HapticFeedback.lightImpact(); // Haptic on refresh pull
        webViewController?.reload();
      },
    );
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() => isOffline = result.contains(ConnectivityResult.none));
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  void _toggleDarkMode() async {
    HapticFeedback.mediumImpact(); // Native feel for theme switch
    await webViewController?.evaluateJavascript(source: """
      document.documentElement.classList.toggle('dark');
      localStorage.setItem('color-theme', document.documentElement.classList.contains('dark') ? 'dark' : 'light');
    """);
    bool isDarkNow = await webViewController?.evaluateJavascript(source: "document.documentElement.classList.contains('dark')") ?? !isDarkMode;
    setState(() => isDarkMode = isDarkNow);
  }

  void _performLogout() async {
    HapticFeedback.heavyImpact();
    await webViewController?.evaluateJavascript(source: """
      var logoutForm = document.querySelector('form[action*="logout"]');
      if(logoutForm) { logoutForm.submit(); }
    """);
    setState(() {
      isLoggedIn = false;
      _selectedIndex = 0;
    });
  }

  void _navigateToProfile() {
    setState(() => _selectedIndex = 3);
    webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri("https://gem-ai.top/profile")));
  }

  void _showNativeMenu(BuildContext context) {
    HapticFeedback.selectionClick();
    final surfaceColor = isDarkMode ? const Color(0xFF1F2937) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 20),
                
                if (isLoggedIn) ...[
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF007BFF),
                      child: Icon(Icons.person_rounded, color: Colors.white),
                    ),
                    title: Text('My Account', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                    subtitle: Text('Manage your profile and settings', style: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600])),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _navigateToProfile();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Divider(color: isDarkMode ? Colors.grey[700] : Colors.grey[200]),
                  ),
                ],
                
                _buildMenuItem(sheetContext, Icons.monetization_on_rounded, 'Pricing', "https://gem-ai.top/pricing", textColor),
                _buildMenuItem(sheetContext, Icons.help_outline_rounded, 'FAQs', "https://gem-ai.top/faqs", textColor),
                _buildMenuItem(sheetContext, Icons.article_outlined, 'Blog', "https://gem-ai.top/blog", textColor),
                _buildMenuItem(sheetContext, Icons.contact_mail_outlined, 'Contact Us', "https://gem-ai.top/contact", textColor),
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Divider(color: isDarkMode ? Colors.grey[700] : Colors.grey[200]),
                ),
                
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: Icon(isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: isDarkMode ? Colors.yellow[400] : Colors.grey[800]),
                  title: Text(isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    _toggleDarkMode();
                  },
                ),
                
                if (isLoggedIn) ...[
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                    title: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      _performLogout();
                    },
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  ListTile _buildMenuItem(BuildContext sheetContext, IconData icon, String title, String url, Color textColor) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(icon, color: const Color(0xFF007BFF)),
      title: Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.pop(sheetContext);
        webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      },
    );
  }

  void _onItemTapped(int index) {
    HapticFeedback.lightImpact(); // Subtle vibration on tab switch
    if (index == 1) {
      _showNativeMenu(context);
      return;
    }
    setState(() => _selectedIndex = index);
    if (isLoggedIn && index == 3) {
      _navigateToProfile();
    } else {
      webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(_currentNavUrls[index])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = isDarkMode ? const Color(0xFF111827) : Colors.white; 
    final surfaceColor = isDarkMode ? const Color(0xFF1F2937) : Colors.white; 
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        // Native Back Button & Double Tap to Exit Handling
        if (webViewController != null && await webViewController!.canGoBack()) {
          webViewController!.goBack(); 
        } else {
          DateTime now = DateTime.now();
          if (currentBackPressTime == null || now.difference(currentBackPressTime!) > const Duration(seconds: 2)) {
            currentBackPressTime = now;
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Tap back again to exit', style: TextStyle(color: Colors.white)),
                  backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[900],
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            }
          } else {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: surfaceColor,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0x1A007BFF), 
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.all_inclusive_rounded, color: Color(0xFF007BFF), size: 24), 
              ),
              const SizedBox(width: 10),
              Text('Gem AI', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.5)),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded, 
                         color: isDarkMode ? Colors.yellow[400] : Colors.grey[700]),
              onPressed: _toggleDarkMode,
            ),
            if (isLoggedIn) ...[
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                color: surfaceColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                offset: const Offset(0, 45),
                icon: const CircleAvatar(
                  backgroundColor: Color(0xFF007BFF),
                  radius: 15,
                  child: Text('E', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                onSelected: (value) {
                  HapticFeedback.selectionClick();
                  if (value == 'profile') _navigateToProfile();
                  if (value == 'logout') _performLogout();
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'profile',
                    child: Row(children: [
                      Icon(Icons.manage_accounts_rounded, color: isDarkMode ? Colors.grey[400] : Colors.grey[700]),
                      const SizedBox(width: 12),
                      Text('Profile and Settings', style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(children: [
                      Icon(Icons.logout_rounded, color: Colors.redAccent),
                      SizedBox(width: 12),
                      Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ],
              ),
            ],
            const SizedBox(width: 8),
          ],
        ),
        
        body: isOffline ? _buildOfflineScreen() : Stack(
          children: [
            InAppWebView(
              key: webViewKey,
              initialUrlRequest: URLRequest(url: WebUri(_currentNavUrls[0])),
              initialSettings: settings,
              initialUserScripts: UnmodifiableListView<UserScript>([
                UserScript(
                  source: _nativeStyles,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                )
              ]),
              pullToRefreshController: pullToRefreshController,
              onWebViewCreated: (controller) => webViewController = controller,
              onLoadStart: (controller, url) => setState(() => isLoading = true),
              onLoadStop: (controller, url) async {
                pullToRefreshController?.endRefreshing();
                bool authCheck = await controller.evaluateJavascript(source: "document.querySelector('form[action*=\"logout\"]') !== null") ?? false;
                bool themeCheck = await controller.evaluateJavascript(source: "document.documentElement.classList.contains('dark')") ?? false;
                
                setState(() { 
                  isLoading = false; 
                  isLoggedIn = authCheck;
                  isDarkMode = themeCheck;
                });
              },
              onDownloadStartRequest: (controller, downloadRequest) async {
                final uri = downloadRequest.url;
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              // Intercept Web Javascript Alerts and show Native Flutter Dialogs
              onJsAlert: (controller, jsAlertRequest) async {
                HapticFeedback.mediumImpact();
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: surfaceColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    content: Text(jsAlertRequest.message ?? '', style: TextStyle(color: textColor)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('OK', style: TextStyle(color: Color(0xFF007BFF), fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                );
                return JsAlertResponse(handledByClient: true);
              },
              onJsConfirm: (controller, jsConfirmRequest) async {
                HapticFeedback.mediumImpact();
                bool result = false;
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: surfaceColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    content: Text(jsConfirmRequest.message ?? '', style: TextStyle(color: textColor)),
                    actions: [
                      TextButton(
                        onPressed: () { result = false; Navigator.of(context).pop(); },
                        child: Text('Cancel', style: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600])),
                      ),
                      TextButton(
                        onPressed: () { result = true; Navigator.of(context).pop(); },
                        child: const Text('Confirm', style: TextStyle(color: Color(0xFF007BFF), fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                );
                return JsConfirmResponse(handledByClient: true, action: result ? JsConfirmResponseAction.CONFIRM : JsConfirmResponseAction.CANCEL);
              },
            ),
            if (isLoading)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF007BFF)),
                  backgroundColor: surfaceColor,
                  minHeight: 3,
                ),
              ),
          ],
        ),
        
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            border: Border(top: BorderSide(color: isDarkMode ? Colors.grey[800]! : Colors.grey[200]!, width: 1)),
          ),
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.transparent,
            elevation: 0,
            items: _navItems,
            currentIndex: _selectedIndex,
            selectedItemColor: const Color(0xFF007BFF),
            unselectedItemColor: isDarkMode ? Colors.grey[500] : Colors.grey[400],
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            onTap: _onItemTapped,
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, size: 80, color: isDarkMode ? Colors.grey[600] : Colors.grey[400]),
          const SizedBox(height: 20),
          Text("No Internet Connection", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87)),
          const SizedBox(height: 10),
          Text("Please check your network settings.", style: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600], fontSize: 16)),
          const SizedBox(height: 30),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007BFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
            ),
            onPressed: () async {
              HapticFeedback.lightImpact();
              await _checkConnectivity();
              if (!isOffline) webViewController?.reload();
            },
            child: const Text("Try Again", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}