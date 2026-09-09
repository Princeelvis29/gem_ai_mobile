import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

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

  bool isLoading = true;
  int _selectedIndex = 0;

  // 1. NATIVE NAVIGATION ROUTES
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

  // 2. CSS INJECTION (HIDE WEB HEADER)
  final String hideHeaderScript = """
    var style = document.createElement('style');
    style.innerHTML = 'header, nav, .navbar, .mobile-header, #header { display: none !important; }';
    document.head.appendChild(style);
  """;

  @override
  void initState() {
    super.initState();
    
    // 3. NATIVE PULL-TO-REFRESH
    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: const Color(0xFF007BFF),
      ),
      onRefresh: () async {
        webViewController?.reload();
      },
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Trigger WebView to navigate when a native tab is tapped
    webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(_navUrls[index])));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
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
                setState(() {
                  isLoading = true;
                });
              },
              onLoadStop: (controller, url) async {
                pullToRefreshController?.endRefreshing();
                setState(() {
                  isLoading = false;
                });
                
                // Execute the CSS script every time a page finishes loading
                await controller.evaluateJavascript(source: hideHeaderScript);
              },
              onDownloadStartRequest: (controller, downloadRequest) async {
                final uri = downloadRequest.url;
                if (await canLaunchUrl(uri)) {
                  await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                } else {
                  debugPrint("Could not launch $uri");
                }
              },
            ),
            
            // 4. NATIVE LOADING INDICATOR
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
      
      // 5. NATIVE BOTTOM NAVIGATION BAR
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
    );
  }
}