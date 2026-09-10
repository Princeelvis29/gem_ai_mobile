import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_in_app_messaging/firebase_in_app_messaging.dart'; 

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  DateTime? currentBackPressTime; 

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
      ::-webkit-scrollbar { display: none; }
    `;
    if (window.location.hostname.includes('gem-ai.top')) {
      if(document.head) {
         document.head.appendChild(style);
      } else {
         document.documentElement.appendChild(style);
      }
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
      useShouldOverrideUrlLoading: true, 
      transparentBackground: true, 
      supportZoom: false, 
      builtInZoomControls: false,
      displayZoomControls: false,
      disableContextMenu: true, 
      overScrollMode: OverScrollMode.NEVER, 
    );

    _checkConnectivity();
    subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      setState(() => isOffline = result.contains(ConnectivityResult.none));
    });

    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: const Color(0xFF007BFF)),
      onRefresh: () async {
        HapticFeedback.lightImpact(); 
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
    HapticFeedback.mediumImpact(); 
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

  // --- NATIVE ARKTECH ABOUT DIALOG ---
  void _showAboutAppDialog() {
    HapticFeedback.selectionClick();
    final surfaceColor = isDarkMode ? const Color(0xFF1F2937) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007BFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Gem AI\nfor Android', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18, height: 1.2)),
                        const SizedBox(height: 4),
                        Text('1.0.0', style: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600], fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Gem AI is a powerful media suite designed for your creative workflows. The Android version provides a seamless, secure native experience to manage your media on the go.',
                style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 24),
              Text('Powered and Developed by Arktech Solutions', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => launchUrl(Uri.parse('https://arktechsolution.top')),
                child: const Text('https://arktechsolution.top', style: TextStyle(color: Color(0xFF007BFF), fontSize: 14)),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      showLicensePage(
                        context: context,
                        applicationName: 'Gem AI for Android',
                        applicationVersion: '1.0.0',
                        applicationIcon: const Icon(Icons.all_inclusive_rounded, size: 48, color: Color(0xFF007BFF)),
                      );
                    },
                    child: const Text('View licenses', style: TextStyle(color: Color(0xFF007BFF), fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close', style: TextStyle(color: Color(0xFF007BFF), fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            ],
          ),
        );
      }
    );
  }

  void _showPaymentPopup(WebUri paymentUrl) {
    HapticFeedback.heavyImpact(); 
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false, 
      builder: (BuildContext modalContext) {
        final surfaceColor = isDarkMode ? const Color(0xFF1F2937) : Colors.white;
        final textColor = isDarkMode ? Colors.white : Colors.black87;
        
        return Container(
          height: MediaQuery.of(context).size.height * 0.90, 
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, -5))],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock_rounded, color: Colors.green, size: 22),
                        const SizedBox(width: 8),
                        Text("Secure Checkout", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
                      ]
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        Navigator.pop(modalContext);
                      },
                    )
                  ],
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(url: paymentUrl),
                    initialSettings: InAppWebViewSettings(transparentBackground: true, supportZoom: false),
                    onLoadStart: (controller, url) {
                      if (url != null && url.host.contains('gem-ai.top')) {
                         Navigator.pop(modalContext);
                         webViewController?.loadUrl(urlRequest: URLRequest(url: url)); 
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Divider(color: isDarkMode ? Colors.grey[700] : Colors.grey[200])),
                ],
                
                _buildMenuItem(sheetContext, Icons.monetization_on_rounded, 'Pricing', "https://gem-ai.top/pricing", textColor),
                _buildMenuItem(sheetContext, Icons.help_outline_rounded, 'FAQs', "https://gem-ai.top/faqs", textColor),
                _buildMenuItem(sheetContext, Icons.article_outlined, 'Blog', "https://gem-ai.top/blog", textColor),
                _buildMenuItem(sheetContext, Icons.contact_mail_outlined, 'Contact Us', "https://gem-ai.top/contact", textColor),
                
                Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Divider(color: isDarkMode ? Colors.grey[700] : Colors.grey[200])),
                
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: const Icon(Icons.settings_rounded, color: Colors.grey),
                  title: Text('App Settings', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SettingsScreen(
                          isDarkMode: isDarkMode,
                          onThemeToggle: _toggleDarkMode,
                          onClearCache: () async {
                            await webViewController?.clearCache();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Web cache cleared successfully.')),
                            );
                          },
                          onShowAbout: _showAboutAppDialog,
                        ),
                      ),
                    );
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
    HapticFeedback.lightImpact(); 
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

  // --- NATIVE SIDE DRAWER ---
  Widget _buildDrawer() {
    final surfaceColor = isDarkMode ? const Color(0xFF1F2937) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Drawer(
      backgroundColor: surfaceColor,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF007BFF)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 48),
                SizedBox(height: 10),
                Text('Gem AI', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ListTile(
            leading: Icon(Icons.home_rounded, color: textColor),
            title: Text('Home', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context); // Close Drawer
              _onItemTapped(0);
            },
          ),
          ListTile(
            leading: Icon(Icons.settings_rounded, color: textColor),
            title: Text('Settings', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context); // Close Drawer
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    isDarkMode: isDarkMode,
                    onThemeToggle: _toggleDarkMode,
                    onClearCache: () async {
                      await webViewController?.clearCache();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Web cache cleared successfully.')),
                      );
                    },
                    onShowAbout: _showAboutAppDialog,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.info_outline_rounded, color: textColor),
            title: Text('About', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context); // Close Drawer
              _showAboutAppDialog();
            },
          ),
        ],
      ),
    );
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
        drawer: _buildDrawer(), // Integrated the Side Navigation Drawer
        appBar: AppBar(
          backgroundColor: surfaceColor,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: IconThemeData(color: textColor), // Hamburger menu color
          title: Text('Gem AI', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.5)),
          actions: [
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
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                var uri = navigationAction.request.url;
                if (uri != null && (uri.host.contains('paystack.com') || uri.path.contains('/checkout'))) {
                  _showPaymentPopup(uri);
                  return NavigationActionPolicy.CANCEL; 
                }
                return NavigationActionPolicy.ALLOW;
              },
              onDownloadStartRequest: (controller, downloadRequest) async {
                final uri = downloadRequest.url;
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
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

// --- DEDICATED NATIVE SETTINGS SCREEN ---
class SettingsScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onThemeToggle;
  final VoidCallback onClearCache;
  final VoidCallback onShowAbout;

  const SettingsScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeToggle,
    required this.onClearCache,
    required this.onShowAbout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool localIsDarkMode;
  bool pushNotificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    localIsDarkMode = widget.isDarkMode;
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = localIsDarkMode ? const Color(0xFF111827) : const Color(0xFFF3F4F6);
    final surfaceColor = localIsDarkMode ? const Color(0xFF1F2937) : Colors.white;
    final textColor = localIsDarkMode ? Colors.white : Colors.black87;
    final subTextColor = localIsDarkMode ? Colors.grey[400] : Colors.grey[600];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: textColor),
        title: Text('Settings', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 10),
          
          // PREFERENCES SECTION
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Preferences', style: TextStyle(color: const Color(0xFF007BFF), fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Container(
            color: surfaceColor,
            child: Column(
              children: [
                SwitchListTile(
                  activeColor: const Color(0xFF007BFF),
                  title: Text('Dark Mode', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                  subtitle: Text('Switch between crisp light and dark themes.', style: TextStyle(color: subTextColor, fontSize: 13)),
                  value: localIsDarkMode,
                  onChanged: (value) {
                    setState(() => localIsDarkMode = value);
                    widget.onThemeToggle(); // Syncs with web view seamlessly
                  },
                ),
                Divider(height: 1, color: localIsDarkMode ? Colors.grey[800] : Colors.grey[200]),
                SwitchListTile(
                  activeColor: const Color(0xFF007BFF),
                  title: Text('Push Notifications', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                  subtitle: Text('Receive alerts for new features and updates.', style: TextStyle(color: subTextColor, fontSize: 13)),
                  value: pushNotificationsEnabled,
                  onChanged: (value) {
                    HapticFeedback.lightImpact();
                    setState(() => pushNotificationsEnabled = value);
                  },
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // STORAGE SECTION
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Storage & Data', style: TextStyle(color: const Color(0xFF007BFF), fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Container(
            color: surfaceColor,
            child: ListTile(
              title: Text('Clear Web Cache', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
              subtitle: Text('Free up space by clearing cached web data.', style: TextStyle(color: subTextColor, fontSize: 13)),
              trailing: Icon(Icons.delete_outline_rounded, color: subTextColor),
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onClearCache();
              },
            ),
          ),
          
          const SizedBox(height: 20),
          
          // ABOUT SECTION
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('About', style: TextStyle(color: const Color(0xFF007BFF), fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Container(
            color: surfaceColor,
            child: ListTile(
              title: Text('About Gem AI', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
              subtitle: Text('Version 2.1.0\nDeveloped by Arktech Solutions', style: TextStyle(color: subTextColor, fontSize: 13, height: 1.4)),
              isThreeLine: true,
              onTap: widget.onShowAbout,
            ),
          ),
        ],
      ),
    );
  }
}