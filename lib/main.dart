import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'services/localization_service.dart';
import 'services/connectivity_service.dart';
import 'services/firestore_service.dart';
import 'services/settings_service.dart';
import 'services/menu_catalog_service.dart';
import 'services/menu_availability_notifier.dart';
import 'services/offline_outbox_service.dart';
import 'services/customer_session_service.dart';
import 'services/customer_directory_service.dart';
import 'services/email_auth_service.dart';
import 'services/local_kitchen_bridge.dart';
import 'services/shift_service.dart';
import 'sdk/nusantara_printer_sdk.dart';
import 'models/menu_item.dart';
import 'models/raw_material.dart';
import 'models/transaction_model.dart';
import 'state/pos_state.dart';
import 'theme/app_theme.dart';
import 'widgets/language_toggle_pill.dart';
import 'widgets/low_stock_alert_modal.dart';
import 'widgets/app_navigation_drawer.dart';
import 'screens/cashier_screen.dart';
import 'screens/kitchen_screen.dart';
import 'screens/customer_order_tracker_screen.dart';
import 'screens/queue_display_screen.dart';
import 'screens/customer_role_screen.dart';
import 'screens/printer_station_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/email_login_screen.dart';
import 'screens/web_admin_portal_screen.dart';
import 'firebase_options.dart';

enum AppRole {
  cashier,
  queueDisplay,
  kitchenDisplay,
  customer,
  printerStation,
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase with automatic platform config from DefaultFirebaseOptions
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase.initializeApp notice: $e');
  }

  // 2. Activate Firebase App Check with AndroidDebugProvider for sideloaded hackathon APKs
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: const AndroidDebugProvider(),
      providerApple: const AppleDebugProvider(),
    );
    debugPrint('Firebase App Check activated with AndroidDebugProvider (AndroidProvider.debug).');
  } catch (e) {
    debugPrint('Firebase App Check activation notice: $e');
  }

  // 3. Enable Cloud Firestore offline persistence
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    debugPrint('Cloud Firestore offline persistence enabled.');
  } catch (e) {
    debugPrint('Firestore offline settings notice: $e');
  }

  // 4. Initialize Core App Services
  try {
    await initializeDateFormatting('id_ID', null);
    await initializeDateFormatting('en_US', null);
  } catch (e) {
    debugPrint('DateFormatting init notice: $e');
  }
  await SettingsService().init();
  await MenuCatalogService().init();
  await MenuAvailabilityNotifier().init();
  await LocalizationService().init();
  await ConnectivityService().init();
  await EmailAuthService().init();
  await OfflineOutboxService().init();
  await CustomerSessionService().init();
  await CustomerDirectoryService().init();
  await LocalKitchenBridge().init();
  await NusantaraPrinterSDK().init();
  await ShiftService().init();

  // 5. Seed realistic initial F&B inventory, menus with photos, and past transactions if empty
  FirestoreService().seedInitialDataIfEmpty();

  runApp(const NusantaraPosApp());
}

class NusantaraPosApp extends StatelessWidget {
  const NusantaraPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService();

    // Check for web deep-link parameter: ?trackOrder=... OR ?admin=true (Web-only Account Management Portal)
    String? deepLinkOrderId;
    String? deepLinkTenant;
    String? deepLinkToken;
    int deepLinkQueue = 1;
    int deepLinkEta = 10;
    bool isWebAdminPortal = false;
    if (kIsWeb) {
      try {
        isWebAdminPortal = Uri.base.queryParameters['admin'] == 'true' ||
            Uri.base.path.toLowerCase().contains('admin');
        deepLinkOrderId = Uri.base.queryParameters['trackOrder'];
        deepLinkTenant = Uri.base.queryParameters['tenant'];
        deepLinkToken = Uri.base.queryParameters['token'];
        deepLinkQueue = int.tryParse(Uri.base.queryParameters['queue'] ?? '') ?? 1;
        deepLinkEta = int.tryParse(Uri.base.queryParameters['eta'] ?? '') ?? 10;
      } catch (_) {}
    }

    return ValueListenableBuilder<String>(
      valueListenable: loc.currentLanguage,
      builder: (context, lang, _) {
        return MaterialApp(
          title: 'Nusantara Hybrid POS',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.themeData,
          home: isWebAdminPortal
              ? const WebAdminPortalScreen()
              : (deepLinkOrderId != null && deepLinkOrderId.isNotEmpty)
                  ? CustomerOrderTrackerScreen(
                      orderId: deepLinkOrderId,
                      tenantId: deepLinkTenant,
                      trackingToken: deepLinkToken ?? '',
                      queueNumber: deepLinkQueue,
                      initialEtaMinutes: deepLinkEta,
                    )
                  : const MainNavigationScreen(),
        );
      },
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final PosState _posState = PosState();
  final FirestoreService _firestore = FirestoreService();

  AppRole _currentRole = AppRole.cashier;

  @override
  void initState() {
    super.initState();
    _loadSavedRole();
  }

  Future<void> _loadSavedRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('app_current_role');
      if (saved != null) {
        final match = AppRole.values.firstWhere(
          (r) => r.name == saved,
          orElse: () => AppRole.cashier,
        );
        if (mounted) setState(() => _currentRole = match);
      }
    } catch (_) {}
  }

  Future<void> _switchRole(AppRole newRole) async {
    HapticFeedback.mediumImpact();
    setState(() => _currentRole = newRole);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_current_role', newRole.name);
    } catch (_) {}
  }

  Widget _buildFloatingDrawerButton({bool dark = false}) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        _scaffoldKey.currentState?.openDrawer();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: dark ? AppTheme.royalBlue : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: dark ? AppTheme.brightYellow : AppTheme.royalBlue,
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Icon(
          Icons.menu_rounded,
          size: 20,
          color: dark ? Colors.white : AppTheme.royalBlue,
        ),
      ),
    );
  }

  Widget _buildCurrentBody({
    required BuildContext context,
    required List<Widget> screens,
    required int currentTab,
    required List<PosTransaction> transactions,
  }) {
    switch (_currentRole) {
      case AppRole.queueDisplay:
        return Stack(
          children: [
            QueueDisplayScreen(transactions: transactions),
            Positioned(
              top: 10,
              left: 14,
              child: SafeArea(
                child: _buildFloatingDrawerButton(dark: true),
              ),
            ),
          ],
        );
      case AppRole.kitchenDisplay:
        return Stack(
          children: [
            KitchenScreen(transactions: transactions),
            Positioned(
              top: 10,
              left: 14,
              child: SafeArea(
                child: _buildFloatingDrawerButton(dark: false),
              ),
            ),
          ],
        );
      case AppRole.customer:
        return CustomerRoleScreen(
          transactions: transactions,
          onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
        );
      case AppRole.printerStation:
        return PrinterStationScreen(
          onReturnToCashier: () => _switchRole(AppRole.cashier),
          onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
        );
      case AppRole.cashier:
        return screens[currentTab.clamp(0, screens.length - 1)];
    }
  }

  @override
  Widget build(BuildContext context) {
    // Combine real-time Firestore streams with reliable offline fallback seeds
    return StreamBuilder<List<RawMaterial>>(
      stream: _firestore.streamRawMaterials(),
      initialData: FirestoreService.defaultSeedRawMaterials,
      builder: (context, rawSnap) {
        final rawMaterials = (rawSnap.data != null && rawSnap.data!.isNotEmpty)
            ? rawSnap.data!
            : FirestoreService.defaultSeedRawMaterials;

        return StreamBuilder<List<MenuItem>>(
          stream: _firestore.streamMenuItems(),
          initialData: MenuCatalogService().items,
          builder: (context, menuSnap) {
            final menuItems = (menuSnap.data != null && menuSnap.data!.isNotEmpty)
                ? menuSnap.data!
                : MenuCatalogService().items;

            return StreamBuilder<List<PosTransaction>>(
              stream: _firestore.streamTransactions(),
              builder: (context, txSnap) {
                final transactions = txSnap.data ?? [];

                return AnimatedBuilder(
                  animation: Listenable.merge([
                    _posState,
                    SettingsService(),
                    MenuCatalogService(),
                    MenuAvailabilityNotifier(),
                    EmailAuthService(),
                  ]),
                  builder: (context, _) {
                    final currentTab = _posState.currentTabIndex;
                    final bool showAuthGate = !EmailAuthService().isLoggedIn && _currentRole != AppRole.queueDisplay;

                    final List<Widget> screens = [
                      CashierScreen(
                        menuItems: menuItems,
                        rawMaterials: rawMaterials,
                        transactions: transactions,
                      ),
                      KitchenScreen(
                        transactions: transactions,
                      ),
                      MenuScreen(
                        menuItems: menuItems,
                        rawMaterials: rawMaterials,
                      ),
                      InventoryScreen(
                        rawMaterials: rawMaterials,
                        transactions: transactions,
                      ),
                      AnalyticsScreen(
                        transactions: transactions,
                        menuItems: menuItems,
                        rawMaterials: rawMaterials,
                      ),
                    ];

                    return Scaffold(
                      key: _scaffoldKey,
                      drawer: AppNavigationDrawer(
                        currentRole: _currentRole,
                        onSelectRole: (role) => _switchRole(role),
                        currentTab: currentTab,
                        onSelectTab: (index) {
                          if (_currentRole != AppRole.cashier) {
                            _switchRole(AppRole.cashier);
                          }
                          _posState.setTabIndex(index);
                        },
                        onOpenSettings: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SettingsScreen(
                                menuItems: menuItems,
                                rawMaterials: rawMaterials,
                              ),
                            ),
                          );
                        },
                        storeName: SettingsService().storeName.isNotEmpty
                            ? SettingsService().storeName
                            : tr('app_title'),
                        cashierName: EmailAuthService().isLoggedIn
                            ? EmailAuthService().loggedInName
                            : 'Nurmiyaty',
                        shiftLabel: EmailAuthService().isLoggedIn
                            ? EmailAuthService().loggedInEmail
                            : 'Morning Shift',
                        isOnline: true,
                        activeTransactionsCount: transactions
                            .where((t) => t.kitchenStatus != 'completed')
                            .length,
                        lowStockCount: rawMaterials.where((r) => r.isLowStock).length,
                      ),
                      appBar: (!showAuthGate && _currentRole == AppRole.cashier)
                          ? AppBar(
                              leading: IconButton(
                                icon: const Icon(Icons.menu_rounded, color: Colors.white),
                                tooltip: 'Menu Navigasi',
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  _scaffoldKey.currentState?.openDrawer();
                                },
                              ),
                              title: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(40),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppTheme.brightYellow.withAlpha(160)),
                                    ),
                                    child: const Icon(
                                      Icons.storefront_rounded,
                                      color: AppTheme.brightYellow,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          SettingsService().storeName.isNotEmpty
                                              ? SettingsService().storeName
                                              : tr('app_title'),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.2,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const Text(
                                          '#BuildHybridAI • Gemini 3.8 Flash & Nano',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.white70,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              actions: [
                                // Low-Stock Alert Notification Bell
                                Builder(
                                  builder: (ctx) {
                                    final lowStockCount = rawMaterials.where((r) => r.isLowStock).length;
                                    if (lowStockCount == 0) return const SizedBox.shrink();
                                    return IconButton(
                                      icon: Badge(
                                        label: Text(
                                          '$lowStockCount',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 9,
                                            color: Colors.white,
                                          ),
                                        ),
                                        backgroundColor: AppTheme.roseRed,
                                        child: const Icon(
                                          Icons.notifications_active_rounded,
                                          color: AppTheme.brightYellow,
                                          size: 22,
                                        ),
                                      ),
                                      tooltip: 'Low-Stock Alert ($lowStockCount bahan)',
                                      onPressed: () {
                                        HapticFeedback.heavyImpact();
                                        LowStockAlertModal.show(
                                          ctx,
                                          rawMaterials: rawMaterials,
                                          menuItems: menuItems,
                                        );
                                      },
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.settings_rounded, color: Colors.white),
                                  tooltip: 'Settings',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => SettingsScreen(
                                          menuItems: menuItems,
                                          rawMaterials: rawMaterials,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                // Mandatory Rule 6 Compliance: EN | ID Language Toggle Pill
                                const LanguageTogglePill(),
                              ],
                            )
                          : null,
                      body: showAuthGate
                          ? EmailLoginScreen(
                              onOpenQueueDisplay: () => _switchRole(AppRole.queueDisplay),
                              onLoginSuccess: () async {
                                await MenuCatalogService().reloadForTenant();
                                await CustomerDirectoryService().reloadForTenant();
                                await LocalKitchenBridge().reloadForTenant();
                                await OfflineOutboxService().reloadForTenant();
                                FirestoreService().seedInitialDataIfEmpty();
                                if (mounted) setState(() {});
                              },
                            )
                          : _buildCurrentBody(
                              context: context,
                              screens: screens,
                              currentTab: currentTab,
                              transactions: transactions,
                            ),
                      bottomNavigationBar: (!showAuthGate && _currentRole == AppRole.cashier)
                          ? BottomNavigationBar(
                              currentIndex: currentTab.clamp(0, 4),
                              onTap: (index) => _posState.setTabIndex(index),
                              type: BottomNavigationBarType.fixed,
                              backgroundColor: Colors.white,
                              selectedItemColor: AppTheme.royalBlue,
                              unselectedItemColor: AppTheme.slateLight,
                              selectedFontSize: 10.5,
                              unselectedFontSize: 9.5,
                              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900),
                              elevation: 8,
                              items: [
                                BottomNavigationBarItem(
                                  icon: Badge(
                                    isLabelVisible: _posState.totalItemCount > 0,
                                    label: Text(
                                      '${_posState.totalItemCount}',
                                      style: const TextStyle(
                                        color: AppTheme.darkNavy,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    backgroundColor: AppTheme.goldenAmber,
                                    child: const Icon(Icons.point_of_sale_rounded),
                                  ),
                                  label: tr('nav_cashier'),
                                ),
                                BottomNavigationBarItem(
                                  icon: Builder(
                                    builder: (_) {
                                      final activeCount = transactions
                                          .where((t) => t.kitchenStatus != 'completed')
                                          .length;
                                      return Badge(
                                        isLabelVisible: activeCount > 0,
                                        label: Text(
                                          '$activeCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 9,
                                          ),
                                        ),
                                        backgroundColor: const Color(0xFFD97706),
                                        child: const Icon(Icons.soup_kitchen_rounded),
                                      );
                                    },
                                  ),
                                  label: 'Dapur',
                                ),
                                BottomNavigationBarItem(
                                  icon: const Icon(Icons.restaurant_menu_rounded),
                                  label: tr('nav_menu'),
                                ),
                                BottomNavigationBarItem(
                                  icon: const Icon(Icons.inventory_2_rounded),
                                  label: tr('nav_inventory'),
                                ),
                                BottomNavigationBarItem(
                                  icon: const Icon(Icons.insights_rounded),
                                  label: tr('nav_analytics'),
                                ),
                              ],
                            )
                          : null,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
