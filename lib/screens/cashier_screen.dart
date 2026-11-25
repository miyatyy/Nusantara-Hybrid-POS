import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/localization_service.dart';
import '../services/connectivity_service.dart';
import '../services/ai_service.dart';
import '../services/firestore_service.dart';
import '../services/settings_service.dart';
import '../models/menu_item.dart';
import '../models/order_item.dart';
import '../models/raw_material.dart';
import '../models/transaction_model.dart';
import '../models/receipt_calculation.dart';
import '../services/offline_outbox_service.dart';
import '../state/pos_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_order_box.dart';
import '../widgets/menu_image_banner.dart';
import '../widgets/thermal_receipt_dialog.dart';
import '../widgets/midtrans_payment_dialog.dart';
import '../widgets/cooking_chef_3d.dart';
import '../services/shift_service.dart';
import '../services/menu_availability_notifier.dart';
import '../services/menu_catalog_service.dart';
import '../services/whatsapp_gateway_service.dart';
import '../services/local_kitchen_bridge.dart';
import '../widgets/shift_handover_modal.dart';

class CashierScreen extends StatefulWidget {
  final List<MenuItem> menuItems;
  final List<RawMaterial> rawMaterials;
  final List<PosTransaction> transactions;

  const CashierScreen({
    super.key,
    required this.menuItems,
    required this.rawMaterials,
    this.transactions = const [],
  });

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final PosState _posState = PosState();
  final SettingsService _settings = SettingsService();
  final TextEditingController _searchController = TextEditingController();

  double? _prefilledCashReceived;
  bool _isListView = false;

  @override
  void initState() {
    super.initState();
    LocalKitchenBridge().startMasterServer();
  }

  Map<String, RawMaterial> get _rawStockMap {
    return {for (var r in widget.rawMaterials) r.id: r};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_posState, _settings, MenuAvailabilityNotifier(), MenuCatalogService()]),
      builder: (context, _) {
        final catalogItems = MenuCatalogService().items.isNotEmpty
            ? MenuCatalogService().items
            : widget.menuItems;
        // Filter menu items by category and search query (Inspired by Foodzone)
        final filteredItems = catalogItems.where((item) {
          final matchesCategory = _posState.selectedCategory == 'All' ||
              item.category.toLowerCase() == _posState.selectedCategory.toLowerCase();
          final matchesSearch = _posState.searchQuery.isEmpty ||
              item.name.toLowerCase().contains(_posState.searchQuery.toLowerCase()) ||
              item.nameEn.toLowerCase().contains(_posState.searchQuery.toLowerCase());
          return matchesCategory && matchesSearch;
        }).toList();

        return Scaffold(
          backgroundColor: AppTheme.iceBlueScaffold,
          body: SafeArea(
            child: Column(
              children: [
                // 1. Top Header: Store Greeting & Settings
                _buildStoreHeader(),

                // Main Scrollable Area
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      // 1. Clean Hero Banner with 3D Cooking Chef Mascot & Compact AI Order Box
                      SliverToBoxAdapter(
                        child: _buildHeroSunburstWithFloatingAiOrder(),
                      ),

                      // 2. Dual Action Pills (Dine In / Take Away & Switch Shift)
                      SliverToBoxAdapter(
                        child: _buildDualActionPills(),
                      ),

                      // 3. Category Filter Chips & Search Bar (Foodzone inspired)
                      SliverToBoxAdapter(
                        child: _build3DCategoryTilesAndSearch(),
                      ),

                      // 4. 2-Column F&B Menu Catalog Grid or Compact List View
                      filteredItems.isEmpty
                          ? SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 40),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.search_off_rounded, size: 48, color: AppTheme.slateLight),
                                      const SizedBox(height: 8),
                                      Text(
                                        tr('search_menu'),
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : _isListView
                              ? SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 95),
                                  sliver: SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final item = filteredItems[index];
                                        final isReady = MenuAvailabilityNotifier().isItemReady(item, _rawStockMap);
                                        final availablePortions = item.calculateAvailablePortions(_rawStockMap);

                                        return _buildCompactListCard(
                                          item: item,
                                          availablePortions: availablePortions,
                                          isReady: isReady,
                                          currencyFormatter: currencyFormatter,
                                        );
                                      },
                                      childCount: filteredItems.length,
                                    ),
                                  ),
                                )
                              : SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 95),
                                  sliver: SliverGrid(
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 3 : 2,
                                      childAspectRatio: 0.78,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final item = filteredItems[index];
                                        final isReady = MenuAvailabilityNotifier().isItemReady(item, _rawStockMap);
                                        final availablePortions = item.calculateAvailablePortions(_rawStockMap);

                                        return _buildMenuCard(
                                          item: item,
                                          availablePortions: availablePortions,
                                          isReady: isReady,
                                          currencyFormatter: currencyFormatter,
                                        );
                                      },
                                      childCount: filteredItems.length,
                                    ),
                                  ),
                                ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _buildStickyCartCheckoutBar(currencyFormatter),
        );
      },
    );
  }

  // 1. Store Status Strip: Greeting, Outbox Sync & Settings
  Widget _buildStoreHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.cardBorder, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.lightBlueTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: AppTheme.cobaltBlue,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _settings.storeName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.darkNavy,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Text(
                  'Real-Time Offline Stock Deduction',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: AppTheme.slateMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Offline JSON Outbox Sync Indicator Pill
          AnimatedBuilder(
            animation: OfflineOutboxService(),
            builder: (context, _) {
              final pending = OfflineOutboxService().pendingCount;
              final isPending = pending > 0;
              return Tooltip(
                message: isPending
                    ? '$pending offline transactions pending sync'
                    : 'All offline transactions synced',
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    OfflineOutboxService().syncPendingOutbox();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        duration: const Duration(seconds: 2),
                        content: Text(
                          isPending
                              ? 'Syncing $pending offline transaction(s)...'
                              : 'All offline records are up-to-date with Cloud Firestore!',
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPending ? const Color(0xFFFEF3C7) : AppTheme.lightBlueTint,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isPending ? const Color(0xFFF59E0B) : AppTheme.blueSubtle,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPending ? Icons.cloud_upload_rounded : Icons.cloud_done_rounded,
                          size: 13,
                          color: isPending ? const Color(0xFFB45309) : AppTheme.royalBlue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isPending ? '$pending' : 'Sync',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: isPending ? const Color(0xFFB45309) : AppTheme.royalBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // 2. Sunburst Hero Banner with Animated Gatotkaca Mascot & Compact AI Order Box
  Widget _buildHeroSunburstWithFloatingAiOrder() {
    return Column(
      children: [
        _buildHeroSunburstBanner(),
        const SizedBox(height: 3),
        AiOrderBox(
          menuItems: MenuCatalogService().items.isNotEmpty ? MenuCatalogService().items : widget.menuItems,
          rawStockMap: _rawStockMap,
          onCashDetected: (cash) {
            setState(() {
              _prefilledCashReceived = cash;
            });
          },
        ),
      ],
    );
  }

  Widget _buildHeroSunburstBanner() {
    return AnimatedBuilder(
      animation: ShiftService(),
      builder: (context, _) {
        final session = ShiftService().currentSession;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.goldenAmber.withAlpha(30),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: CustomPaint(
              painter: _SunburstPainter(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left Column: Status Pill, Bold Display Headline & Subtitle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Glassy Cashier Status Pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(220),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(8),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 8,
                                  backgroundColor: AppTheme.royalBlue,
                                  child: Text(
                                    session.cashierName.isNotEmpty
                                        ? session.cashierName[0].toUpperCase()
                                        : 'K',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.brightYellow,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    '${session.cashierName} • ${session.shiftLabel}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.darkNavy,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Bold Display Headline
                          Text(
                            tr('hero_headline'),
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.darkNavy,
                              height: 1.15,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Subtitle Tagline
                          Text(
                            tr('hero_sub'),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.royalBlue,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Right Side: Nusantara Blue Chef Logo
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                      },
                      child: const CookingChef3DWidget(
                        size: 114,
                        animate: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // 3. Dual Action Pills (Dine In / Take Away & Switch Shift / Z-Report)
  Widget _buildDualActionPills() {
    return AnimatedBuilder(
      animation: ShiftService(),
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(
            children: [
              // Pill 1: Dine In / Take Away Mode Switcher
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.royalBlue.withAlpha(10),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _buildOrderModeTab('Dine In', tr('dine_in'), Icons.restaurant_rounded),
                      _buildOrderModeTab('Take Away', tr('take_away'), Icons.takeout_dining_rounded),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Pill 2: Switch Shift / Z-Report Action
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  ShiftHandoverModal.show(
                    context,
                    transactions: widget.transactions,
                    onShiftChanged: () {
                      setState(() {});
                    },
                  );
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.goldenAmber, Color(0xFFF59E0B)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.goldenAmber.withAlpha(60),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.swap_horiz_rounded, size: 15, color: AppTheme.darkNavy),
                      const SizedBox(width: 5),
                      Text(
                        tr('switch_shift'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.darkNavy,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOrderModeTab(String modeKey, String label, IconData icon) {
    final isSelected = _posState.orderMode == modeKey;
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            _posState.setOrderMode(modeKey);
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.royalBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? AppTheme.brightYellow : AppTheme.royalBlue,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  color: isSelected ? Colors.white : AppTheme.darkNavy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 3. Category Filter Chips & Dual View Search Bar (Foodzone inspired)
  Widget _build3DCategoryTilesAndSearch() {
    final categories = ['All', 'Minuman', 'Makanan', 'Cemilan', 'Paket'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row of 3D-Styled Claymorphic Category Tiles
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isSelected = _posState.selectedCategory == cat;
                String label;
                IconData icon;
                Color accentColor;

                switch (cat) {
                  case 'All':
                    label = tr('cat_all');
                    icon = Icons.auto_awesome_rounded;
                    accentColor = AppTheme.brightYellow;
                    break;
                  case 'Minuman':
                    label = tr('cat_drink');
                    icon = Icons.local_cafe_rounded;
                    accentColor = const Color(0xFF38BDF8); // Sky Blue
                    break;
                  case 'Makanan':
                    label = tr('cat_food');
                    icon = Icons.restaurant_rounded;
                    accentColor = AppTheme.goldenAmber;
                    break;
                  case 'Cemilan':
                    label = tr('cat_snack');
                    icon = Icons.bakery_dining_rounded;
                    accentColor = const Color(0xFFF97316); // Amber Orange
                    break;
                  case 'Paket':
                    label = tr('cat_bundle');
                    icon = Icons.lunch_dining_rounded;
                    accentColor = const Color(0xFFA855F7); // Purple
                    break;
                  default:
                    label = cat;
                    icon = Icons.fastfood_rounded;
                    accentColor = AppTheme.goldenAmber;
                }

                return Padding(
                  padding: const EdgeInsets.only(right: 9),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _posState.setCategory(cat);
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 68,
                      height: 70,
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [AppTheme.royalBlue, Color(0xFF1E40AF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : const LinearGradient(
                                colors: [Colors.white, Color(0xFFF8FAFC)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.brightYellow
                              : AppTheme.cardBorder,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                        boxShadow: [
                          if (isSelected) ...[
                            BoxShadow(
                              color: AppTheme.royalBlue.withAlpha(60),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ] else ...[
                            BoxShadow(
                              color: Colors.white,
                              blurRadius: 3,
                              offset: const Offset(-2, -2),
                            ),
                            BoxShadow(
                              color: Colors.black.withAlpha(10),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 3D-Styled Icon Orb
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: isSelected
                                    ? [
                                        accentColor,
                                        accentColor.withAlpha(190),
                                      ]
                                    : [
                                        accentColor.withAlpha(45),
                                        accentColor.withAlpha(15),
                                      ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withAlpha(isSelected ? 90 : 25),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              icon,
                              size: 17,
                              color: isSelected ? AppTheme.darkNavy : AppTheme.royalBlue,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: isSelected ? Colors.white : AppTheme.darkNavy,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),

          // Search Bar + Grid/List View Mode Switcher
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: tr('search_menu'),
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.cobaltBlue),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _posState.setSearchQuery('');
                                });
                              },
                            )
                          : null,
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppTheme.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppTheme.cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppTheme.cobaltBlue, width: 1.5),
                      ),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _posState.setSearchQuery(val);
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _isListView = !_isListView;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isListView ? Icons.grid_view_rounded : Icons.view_list_rounded,
                        size: 16,
                        color: AppTheme.royalBlue,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isListView ? 'Grid' : 'List',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.royalBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 6. Modern F&B Menu Card - Dominant Food Photography with Compact Balanced Details
  Widget _buildMenuCard({
    required MenuItem item,
    required int availablePortions,
    required bool isReady,
    required NumberFormat currencyFormatter,
  }) {
    final isBundle = item.category.toLowerCase() == 'paket';
    final qtyInCart = _posState.getItemQuantity(item.id);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: !isReady ? Colors.red.shade200 : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              _showMenuItemDetailModal(
                item: item,
                availablePortions: availablePortions,
                isReady: isReady,
                currencyFormatter: currencyFormatter,
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Prominent Food Photo with Floating Pill Badges & Bottom Shadow
                Stack(
                  children: [
                    MenuImageBanner(
                      imageUrl: item.imageUrl,
                      category: item.category,
                      iconEmoji: item.iconEmoji,
                      height: 125,
                      isSoldOut: !isReady,
                    ),
                    // Subtle photo shadow gradient at bottom of image
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 24,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withAlpha(45),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Floating Badge (Top-Left)
                    Positioned(
                      top: 7,
                      left: 7,
                      child: isBundle
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.goldenAmber,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(40),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome, size: 10, color: AppTheme.darkNavy),
                                  SizedBox(width: 3),
                                  Text(
                                    'AI BUNDLE',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.darkNavy,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : (!isReady
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.roseRed,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(30),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    tr('stock_out'),
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink()),
                    ),
                    // Floating Cart Count Badge (Top-Right)
                    if (qtyInCart > 0 && isReady)
                      Positioned(
                        top: 7,
                        right: 7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: AppTheme.royalBlue,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(40),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.shopping_bag_outlined, size: 10, color: Colors.white),
                              const SizedBox(width: 3),
                              Text(
                                '$qtyInCart',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

                // Card Bottom Details (Clean, balanced, zero excessive whitespace)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Name and category line
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: !isReady ? Colors.grey : AppTheme.darkNavy,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  item.category,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                if (availablePortions > 0 && availablePortions <= 5) ...[
                                  Text(' • ', style: TextStyle(color: Colors.grey.shade400, fontSize: 9)),
                                  Text(
                                    'Sisa $availablePortions',
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFD97706),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),

                        // Price and Action Button / Stepper Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                currencyFormatter.format(item.price),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w900,
                                  color: !isReady ? Colors.grey : AppTheme.royalBlue,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),

                            // Dynamic Action: Inline Stepper if in Cart, else Golden "+" Button
                            if (qtyInCart > 0 && isReady)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.lightBlueTint,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.blueSubtle),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        _posState.updateQuantity(item.id, qtyInCart - 1);
                                        setState(() {});
                                      },
                                      child: const Icon(Icons.remove_rounded, size: 16, color: AppTheme.royalBlue),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 5),
                                      child: Text(
                                        '$qtyInCart',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 11,
                                          color: AppTheme.darkNavy,
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        _posState.updateQuantity(item.id, qtyInCart + 1);
                                        setState(() {});
                                      },
                                      child: const Icon(Icons.add_rounded, size: 16, color: AppTheme.royalBlue),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Material(
                                color: !isReady ? Colors.grey.shade300 : AppTheme.goldenAmber,
                                shape: const CircleBorder(),
                                elevation: !isReady ? 0 : 2,
                                shadowColor: AppTheme.goldenAmber.withAlpha(120),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: !isReady
                                      ? () {
                                          _showMenuItemDetailModal(
                                            item: item,
                                            availablePortions: availablePortions,
                                            isReady: isReady,
                                            currencyFormatter: currencyFormatter,
                                          );
                                        }
                                      : () {
                                          HapticFeedback.lightImpact();
                                          _posState.addToCart(item);
                                          setState(() {});
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              backgroundColor: AppTheme.royalBlue,
                                              behavior: SnackBarBehavior.floating,
                                              duration: const Duration(milliseconds: 900),
                                              content: Text('+1 ${item.name}'),
                                            ),
                                          );
                                        },
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.add_rounded,
                                      size: 16,
                                      color: AppTheme.darkNavy,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 6b. Ultra-Compact List Card (Toast / Square POS style: 62dp height per item)
  Widget _buildCompactListCard({
    required MenuItem item,
    required int availablePortions,
    required bool isReady,
    required NumberFormat currencyFormatter,
  }) {
    final qtyInCart = _posState.getItemQuantity(item.id);
    final isBundle = item.category.toLowerCase() == 'paket';

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: !isReady ? Colors.red.shade200 : AppTheme.cardBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalBlue.withAlpha(8),
            blurRadius: 5,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () {
            _showMenuItemDetailModal(
              item: item,
              availablePortions: availablePortions,
              isReady: isReady,
              currencyFormatter: currencyFormatter,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            child: Row(
              children: [
                // 48x48 Square Thumbnail
                MenuImageBanner(
                  imageUrl: item.imageUrl,
                  category: item.category,
                  iconEmoji: item.iconEmoji,
                  height: 48,
                  width: 48,
                  borderRadius: BorderRadius.circular(9),
                  isSoldOut: !isReady,
                ),
                const SizedBox(width: 10),

                // Title, Category & Portions
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: !isReady ? Colors.grey : AppTheme.darkNavy,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isBundle) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.goldenAmber,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text(
                                'BUNDLE',
                                style: TextStyle(
                                  fontSize: 7.5,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.darkNavy,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (!isReady) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                tr('stock_out'),
                                style: const TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.roseRed,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            item.category,
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: AppTheme.slateMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Price & Stepper / Add button
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currencyFormatter.format(item.price),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: !isReady ? Colors.grey : AppTheme.royalBlue,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (qtyInCart > 0 && isReady)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppTheme.lightBlueTint,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.blueSubtle),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _posState.updateQuantity(item.id, qtyInCart - 1);
                                setState(() {});
                              },
                              child: const Icon(Icons.remove_rounded, size: 13, color: AppTheme.royalBlue),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                '$qtyInCart',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10,
                                  color: AppTheme.darkNavy,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _posState.updateQuantity(item.id, qtyInCart + 1);
                                setState(() {});
                              },
                              child: const Icon(Icons.add_rounded, size: 13, color: AppTheme.royalBlue),
                            ),
                          ],
                        ),
                      )
                    else
                      Material(
                        color: !isReady ? Colors.grey.shade300 : AppTheme.goldenAmber,
                        shape: const CircleBorder(),
                        elevation: !isReady ? 0 : 1,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: !isReady
                              ? () {
                                  _showMenuItemDetailModal(
                                    item: item,
                                    availablePortions: availablePortions,
                                    isReady: isReady,
                                    currencyFormatter: currencyFormatter,
                                  );
                                }
                              : () {
                                  HapticFeedback.lightImpact();
                                  _posState.addToCart(item);
                                  setState(() {});
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: AppTheme.royalBlue,
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(milliseconds: 900),
                                      content: Text('+1 ${item.name}'),
                                    ),
                                  );
                                },
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.add_rounded,
                              size: 14,
                              color: AppTheme.darkNavy,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 6c. Modern Food Detail & Description Bottom Sheet Modal
  void _showMenuItemDetailModal({
    required MenuItem item,
    required int availablePortions,
    required bool isReady,
    required NumberFormat currencyFormatter,
  }) {
    HapticFeedback.lightImpact();
    int selectedQty = 1;
    final notesController = TextEditingController();
    final isBundle = item.category.toLowerCase() == 'paket';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.90,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 20,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Drag Handle & Category Badge Row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.lightBlueTint,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(item.iconEmoji, style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 5),
                              Text(
                                item.category.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.cobaltBlue,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Center Drag Bar
                        Container(
                          width: 40,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        // Close Button
                        Material(
                          color: Colors.grey.shade100,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => Navigator.pop(ctx),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.close_rounded, size: 20, color: AppTheme.darkNavy),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Scrollable Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        4,
                        16,
                        MediaQuery.of(ctx).viewInsets.bottom + 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Food Photo Banner with Floating Badges (Full Immersive View)
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: MenuImageBanner(
                                  imageUrl: item.imageUrl,
                                  category: item.category,
                                  iconEmoji: item.iconEmoji,
                                  height: 230,
                                  width: double.infinity,
                                  borderRadius: BorderRadius.circular(18),
                                  isSoldOut: !isReady,
                                ),
                              ),
                              // Subtle shadow gradient at bottom of full image
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  height: 45,
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        Colors.black.withAlpha(70),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // Floating Badges
                              Positioned(
                                top: 10,
                                left: 10,
                                child: isBundle
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppTheme.goldenAmber,
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: const [
                                            BoxShadow(color: Colors.black26, blurRadius: 6),
                                          ],
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.auto_awesome, size: 12, color: AppTheme.darkNavy),
                                            SizedBox(width: 4),
                                            Text(
                                              'AI SMART COMBO',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                                color: AppTheme.darkNavy,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              Positioned(
                                top: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: !isReady ? AppTheme.roseRed : const Color(0xFF15803D),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black26, blurRadius: 6),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        !isReady ? Icons.block_rounded : Icons.check_circle_rounded,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        !isReady
                                            ? tr('stock_out')
                                            : 'In Stock',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // 2. Title, Subtitle, and Price
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.darkNavy,
                                        height: 1.2,
                                      ),
                                    ),
                                    if (item.nameEn.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        item.nameEn,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: Colors.grey.shade500,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                currencyFormatter.format(item.price),
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.royalBlue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // 3. Deskripsi Makanan (Description Card for Customers)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.menu_book_rounded, size: 16, color: AppTheme.royalBlue),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Menu Description',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.darkNavy,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  item.description.isNotEmpty
                                      ? item.description
                                      : 'Delicious specialty prepared with premium fresh ingredients and authentic Nusantara flavors.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // 4. Notes / Catatan Pesanan
                          TextField(
                            controller: notesController,
                            style: const TextStyle(fontSize: 13, color: AppTheme.darkNavy),
                            decoration: InputDecoration(
                              hintText: 'Special instructions (e.g. less ice, extra sauce)',
                              hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                              prefixIcon: const Icon(Icons.edit_note_rounded, size: 20, color: AppTheme.royalBlue),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppTheme.cardBorder),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppTheme.cardBorder),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppTheme.royalBlue, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 6. Quantity Stepper & Add to Order Button
                          Row(
                            children: [
                              // Quantity Stepper
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.cardBorder),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_rounded, size: 18),
                                      color: selectedQty > 1 ? AppTheme.royalBlue : Colors.grey.shade400,
                                      onPressed: selectedQty > 1
                                          ? () => setModalState(() => selectedQty--)
                                          : null,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text(
                                        '$selectedQty',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: AppTheme.darkNavy,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_rounded, size: 18),
                                      color: isReady ? AppTheme.royalBlue : Colors.grey.shade400,
                                      onPressed: isReady && (availablePortions >= 999 || selectedQty < availablePortions)
                                          ? () => setModalState(() => selectedQty++)
                                          : null,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Big Add Button
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: !isReady ? Colors.grey.shade300 : AppTheme.royalBlue,
                                    foregroundColor: Colors.white,
                                    elevation: !isReady ? 0 : 3,
                                    shadowColor: AppTheme.royalBlue.withAlpha(80),
                                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: !isReady
                                      ? null
                                      : () {
                                          HapticFeedback.mediumImpact();
                                          _posState.addToCart(
                                            item,
                                            quantity: selectedQty,
                                            notes: notesController.text.trim(),
                                          );
                                          Navigator.pop(ctx);
                                          setState(() {});
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              backgroundColor: AppTheme.royalBlue,
                                              behavior: SnackBarBehavior.floating,
                                              duration: const Duration(seconds: 1),
                                              content: Row(
                                                children: [
                                                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      '${selectedQty}x ${item.name} ditambahkan!',
                                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            !isReady ? Icons.block_rounded : Icons.add_shopping_cart_rounded,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            !isReady
                                                ? tr('stock_out')
                                                : 'Add to Order',
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (isReady)
                                        Text(
                                          currencyFormatter.format(item.price * selectedQty),
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w900,
                                            color: AppTheme.brightYellow,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Sticky Floating Bottom Cart Checkout Bar
  Widget _buildStickyCartCheckoutBar(NumberFormat currencyFormatter) {
    return AnimatedBuilder(
      animation: _posState,
      builder: (context, _) {
        final itemCount = _posState.totalItemCount;
        if (itemCount == 0) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.royalBlue, Color(0xFF1D4ED8)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppTheme.royalBlue.withAlpha(80),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.brightYellow,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(20),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shopping_bag_rounded, size: 15, color: AppTheme.darkNavy),
                      const SizedBox(width: 4),
                      Text(
                        '$itemCount',
                        style: const TextStyle(
                          color: AppTheme.darkNavy,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL (${_posState.orderMode.toUpperCase()})',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      currencyFormatter.format(_posState.total),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _openCheckoutBottomSheet(currencyFormatter),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.goldenAmber,
                    foregroundColor: AppTheme.darkNavy,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.payment_rounded, size: 16, color: AppTheme.darkNavy),
                  label: const Text(
                    'Pay Now',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: AppTheme.darkNavy,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Checkout modal bottom sheet
  void _openCheckoutBottomSheet(NumberFormat currencyFormatter) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _CheckoutModal(
          currencyFormatter: currencyFormatter,
          initialCash: _prefilledCashReceived,
          rawMaterials: widget.rawMaterials,
          onCompleted: () {
            setState(() {
              _prefilledCashReceived = null;
            });
          },
          onCompletedWithItems: (items) {
            _checkLowStockAfterCheckout(items);
          },
        );
      },
    );
  }

  void _checkLowStockAfterCheckout(List<OrderItem> items) {
    final lowIngredients = <String>[];
    for (final it in items) {
      it.menuItem.recipe.forEach((rawMaterialId, amountNeeded) {
        final raw = widget.rawMaterials.firstWhere(
          (m) => m.id == rawMaterialId,
          orElse: () => const RawMaterial(
            id: '',
            name: '',
            category: '',
            currentStock: 999,
            unit: '',
            minSafetyStock: 0,
            costPerUnit: 0.0,
          ),
        );
        if (raw.id.isNotEmpty) {
          final remaining = raw.currentStock - (amountNeeded * it.quantity);
          final threshold = raw.minThreshold > 0 ? raw.minThreshold : raw.minSafetyStock;
          if (remaining <= threshold && !lowIngredients.contains(raw.name)) {
            lowIngredients.add(raw.name);
          }
        }
      });
    }

    if (lowIngredients.isNotEmpty && mounted) {
      HapticFeedback.heavyImpact();
      try {
        SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.brightYellow),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'LOW STOCK ALERT: ${lowIngredients.join(', ')} nearing minimum threshold!',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}

class _CheckoutModal extends StatefulWidget {
  final NumberFormat currencyFormatter;
  final double? initialCash;
  final VoidCallback onCompleted;
  final void Function(List<OrderItem> items)? onCompletedWithItems;
  final List<RawMaterial> rawMaterials;

  const _CheckoutModal({
    required this.currencyFormatter,
    this.initialCash,
    required this.onCompleted,
    this.onCompletedWithItems,
    this.rawMaterials = const [],
  });

  @override
  State<_CheckoutModal> createState() => _CheckoutModalState();
}

class _CheckoutModalState extends State<_CheckoutModal> {
  final PosState _pos = PosState();
  final FirestoreService _firestore = FirestoreService();
  final AiService _ai = AiService();
  final ConnectivityService _connectivity = ConnectivityService();
  final SettingsService _settings = SettingsService();

  String _paymentMethod = 'Cash'; // 'Cash', 'Midtrans Sandbox', 'Card'
  late TextEditingController _cashController;
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  bool _isCheckingOut = false;

  @override
  void initState() {
    super.initState();
    final initialCalc = ReceiptCalculation.compute(
      items: _pos.cart,
      taxPercent: _settings.taxRate,
      servicePercent: _settings.serviceChargeRate,
      rawCashInput: null,
    );
    final defaultCash = widget.initialCash?.round() ?? initialCalc.grandTotal;
    _cashController = TextEditingController(text: defaultCash.toString());
    _notesController.text = _pos.orderNotes;
  }

  @override
  void dispose() {
    _cashController.dispose();
    _notesController.dispose();
    _customerPhoneController.dispose();
    _customerNameController.dispose();
    super.dispose();
  }

  ReceiptCalculation get _currentCalc {
    final rawInput = _paymentMethod == 'Cash' ? _cashController.text : null;
    final session = ShiftService().currentSession;
    return ReceiptCalculation.compute(
      items: _pos.cart,
      taxPercent: _settings.taxRate,
      servicePercent: _settings.serviceChargeRate,
      rawCashInput: rawInput,
      paymentMethod: _paymentMethod,
      orderMode: _pos.orderMode,
      orderNotes: _pos.orderNotes,
      customerPhone: _customerPhoneController.text.trim(),
      customerName: _customerNameController.text.trim().isEmpty ? 'Customer' : _customerNameController.text.trim(),
      cashierName: session.cashierName,
      shiftLabel: session.shiftLabel,
      shiftHours: session.shiftHours,
    );
  }

  Future<void> _handleConfirmCheckout() async {
    final calc = _currentCalc;

    if (_paymentMethod == 'Cash' && !calc.isPaidSufficient) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.roseRed,
          content: Text(
            'Insufficient cash: short Rp ${ReceiptCalculation.formatRupiah(calc.shortage)}!',
          ),
        ),
      );
      return;
    }

    final orderId = 'TX-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final itemsSnapshot = List.of(_pos.cart);
    final engineSource = _ai.activeEngine == ActiveAiEngine.localNano
        ? 'ON_DEVICE'
        : 'IN_CLOUD';
    final isOffline = !_connectivity.isOnline;
    final session = ShiftService().currentSession;
    final queueNum = await SettingsService().getNextQueueNumber();
    final custPhone = _customerPhoneController.text.trim();
    final custName = _customerNameController.text.trim().isEmpty ? 'Customer' : _customerNameController.text.trim();
    if (!mounted) return;

    // Handle Midtrans Sandbox (QRIS & Card Modal)
    if (_paymentMethod == 'Midtrans Sandbox') {
      if (isOffline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.roseRed,
            content: Text(tr('midtrans_offline_warning')),
          ),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (_) => MidtransPaymentDialog(
          orderId: orderId,
          total: calc.grandTotal.toDouble(),
          items: itemsSnapshot,
          currencyFormatter: widget.currencyFormatter,
          onPaymentSuccess: (methodName) async {
            final midtransCalc = ReceiptCalculation.compute(
              items: itemsSnapshot,
              taxPercent: _settings.taxRate,
              servicePercent: _settings.serviceChargeRate,
              rawCashInput: null,
              paymentMethod: methodName,
              orderMode: _pos.orderMode,
              orderNotes: _pos.orderNotes,
              customerPhone: custPhone,
              customerName: custName,
              cashierName: session.cashierName,
              shiftLabel: session.shiftLabel,
              shiftHours: session.shiftHours,
              queueNumber: queueNum,
            );

            await _firestore.checkoutOrder(
              items: itemsSnapshot,
              subtotal: midtransCalc.subtotal.toDouble(),
              tax: midtransCalc.taxAmount.toDouble(),
              total: midtransCalc.grandTotal.toDouble(),
              serviceAmount: midtransCalc.serviceAmount.toDouble(),
              paymentMethod: methodName,
              cashReceived: midtransCalc.amountPaid.toDouble(),
              changeAmount: 0.0,
              aiSource: engineSource,
              orderMode: _pos.orderMode,
              orderNotes: _pos.orderNotes,
              customerPhone: custPhone,
              customerName: custName,
              cashierName: session.cashierName,
              shiftLabel: session.shiftLabel,
              shiftHours: session.shiftHours,
              queueNumber: queueNum,
              isOffline: false,
              customOrderId: orderId,
              trackingToken: midtransCalc.trackingToken,
            );

            final txRecord = PosTransaction(
              id: orderId,
              timestamp: DateTime.now(),
              items: itemsSnapshot,
              subtotal: midtransCalc.subtotal.toDouble(),
              tax: midtransCalc.taxAmount.toDouble(),
              serviceAmount: midtransCalc.serviceAmount.toDouble(),
              total: midtransCalc.grandTotal.toDouble(),
              paymentMethod: methodName,
              cashReceived: midtransCalc.amountPaid.toDouble(),
              changeAmount: 0.0,
              aiSource: engineSource,
              orderMode: _pos.orderMode,
              orderNotes: _pos.orderNotes,
              customerPhone: custPhone,
              customerName: custName,
              cashierName: session.cashierName,
              shiftLabel: session.shiftLabel,
              shiftHours: session.shiftHours,
              queueNumber: queueNum,
              isOffline: false,
              trackingToken: midtransCalc.trackingToken,
            );
            LocalKitchenBridge().registerLocalOrder(txRecord);

            if (custPhone.isNotEmpty) {
              WhatsAppGatewayService().sendOrderConfirmation(
                customerPhone: custPhone,
                order: txRecord,
                storeName: _settings.storeName.isNotEmpty ? _settings.storeName : 'Nusantara POS',
                customerName: custName,
              );
            }

            _pos.clearCart();
            widget.onCompleted();
            widget.onCompletedWithItems?.call(itemsSnapshot);

            if (mounted) {
              Navigator.of(context).pop(); // Close checkout bottom sheet

              showDialog(
                context: context,
                builder: (_) => ThermalReceiptDialog(
                  orderId: orderId,
                  timestamp: DateTime.now(),
                  items: itemsSnapshot,
                  subtotal: midtransCalc.subtotal.toDouble(),
                  tax: midtransCalc.taxAmount.toDouble(),
                  total: midtransCalc.grandTotal.toDouble(),
                  paymentMethod: methodName,
                  cashReceived: midtransCalc.amountPaid.toDouble(),
                  changeAmount: 0.0,
                  aiSource: engineSource,
                  isOffline: false,
                  calculation: midtransCalc,
                ),
              );
            }
          },
        ),
      );
      return;
    }

    setState(() {
      _isCheckingOut = true;
    });

    try {
      final finalCalc = ReceiptCalculation.compute(
        items: itemsSnapshot,
        taxPercent: _settings.taxRate,
        servicePercent: _settings.serviceChargeRate,
        rawCashInput: _paymentMethod == 'Cash' ? _cashController.text : null,
        paymentMethod: _paymentMethod,
        orderMode: _pos.orderMode,
        orderNotes: _pos.orderNotes,
        customerPhone: custPhone,
        customerName: custName,
        cashierName: session.cashierName,
        shiftLabel: session.shiftLabel,
        shiftHours: session.shiftHours,
        queueNumber: queueNum,
      );

      await _firestore.checkoutOrder(
        items: itemsSnapshot,
        subtotal: finalCalc.subtotal.toDouble(),
        tax: finalCalc.taxAmount.toDouble(),
        total: finalCalc.grandTotal.toDouble(),
        serviceAmount: finalCalc.serviceAmount.toDouble(),
        paymentMethod: _paymentMethod,
        cashReceived: finalCalc.amountPaid.toDouble(),
        changeAmount: finalCalc.changeAmount.toDouble(),
        aiSource: engineSource,
        orderMode: _pos.orderMode,
        orderNotes: _pos.orderNotes,
        customerPhone: custPhone,
        customerName: custName,
        cashierName: session.cashierName,
        shiftLabel: session.shiftLabel,
        shiftHours: session.shiftHours,
        queueNumber: queueNum,
        isOffline: isOffline,
        customOrderId: orderId,
        trackingToken: finalCalc.trackingToken,
      );

      final txRecord = PosTransaction(
        id: orderId,
        timestamp: DateTime.now(),
        items: itemsSnapshot,
        subtotal: finalCalc.subtotal.toDouble(),
        tax: finalCalc.taxAmount.toDouble(),
        serviceAmount: finalCalc.serviceAmount.toDouble(),
        total: finalCalc.grandTotal.toDouble(),
        paymentMethod: _paymentMethod,
        cashReceived: finalCalc.amountPaid.toDouble(),
        changeAmount: finalCalc.changeAmount.toDouble(),
        aiSource: engineSource,
        orderMode: _pos.orderMode,
        orderNotes: _pos.orderNotes,
        customerPhone: custPhone,
        customerName: custName,
        cashierName: session.cashierName,
        shiftLabel: session.shiftLabel,
        shiftHours: session.shiftHours,
        queueNumber: queueNum,
        isOffline: isOffline,
        trackingToken: finalCalc.trackingToken,
      );
      LocalKitchenBridge().registerLocalOrder(txRecord);

      if (custPhone.isNotEmpty) {
        WhatsAppGatewayService().sendOrderConfirmation(
          customerPhone: custPhone,
          order: txRecord,
          storeName: _settings.storeName.isNotEmpty ? _settings.storeName : 'Nusantara POS',
          customerName: custName,
        );
      }

      _pos.clearCart();
      widget.onCompleted();
      widget.onCompletedWithItems?.call(itemsSnapshot);

      if (mounted) {
        Navigator.of(context).pop(); // Close bottom sheet

        showDialog(
          context: context,
          builder: (_) => ThermalReceiptDialog(
            orderId: orderId,
            timestamp: DateTime.now(),
            items: itemsSnapshot,
            subtotal: finalCalc.subtotal.toDouble(),
            tax: finalCalc.taxAmount.toDouble(),
            total: finalCalc.grandTotal.toDouble(),
            paymentMethod: _paymentMethod,
            cashReceived: finalCalc.amountPaid.toDouble(),
            changeAmount: finalCalc.changeAmount.toDouble(),
            aiSource: engineSource,
            isOffline: isOffline,
            calculation: finalCalc,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.roseRed,
            content: Text('Checkout notice: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final calc = _currentCalc;
    final canCheckout = !_isCheckingOut && (_paymentMethod != 'Cash' || calc.isPaidSufficient);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shopping_cart_checkout, color: AppTheme.royalBlue, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      tr('cart_title'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.royalBlue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.lightBlueTint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _pos.orderMode,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.royalBlue),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () {
                    _pos.clearCart();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Clear Cart', style: TextStyle(color: AppTheme.roseRed, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const Divider(),

            // Items list in cart with Dismissible (swipe-to-delete)
            ..._pos.cart.map((item) {
              return Dismissible(
                key: Key(item.menuItem.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  color: AppTheme.roseRed,
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                onDismissed: (_) {
                  _pos.updateQuantity(item.menuItem.id, 0);
                  setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text(item.menuItem.iconEmoji, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.menuItem.name,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.darkNavy),
                            ),
                            if (item.notes.isNotEmpty)
                              Text(
                                item.notes,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                              ),
                            Text(
                              widget.currencyFormatter.format(item.totalPrice),
                              style: const TextStyle(fontSize: 12, color: AppTheme.royalBlue, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20, color: AppTheme.royalBlue),
                        onPressed: () {
                          _pos.updateQuantity(item.menuItem.id, item.quantity - 1);
                          setState(() {});
                        },
                      ),
                      Text(
                        '${item.quantity}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, size: 20, color: AppTheme.royalBlue),
                        onPressed: () {
                          _pos.updateQuantity(item.menuItem.id, item.quantity + 1);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 8),
            // Customer Phone & Name for WhatsApp E-Receipt & Loyalty
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: TextField(
                    controller: _customerNameController,
                    decoration: InputDecoration(
                      hintText: 'Customer Name',
                      hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                      prefixIcon: const Icon(Icons.person_outline_rounded, size: 16, color: AppTheme.royalBlue),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: _customerPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: 'WhatsApp (08xx)',
                      hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                      prefixIcon: const Icon(Icons.phone_iphone_rounded, size: 16, color: Color(0xFF15803D)),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Order Notes Input Field
            TextField(
              controller: _notesController,
              decoration: InputDecoration(
                hintText: tr('order_notes_hint'),
                hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.edit_note_rounded, size: 18, color: AppTheme.royalBlue),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (val) => _pos.setOrderNotes(val),
            ),

            const Divider(height: 20),
            // Summary with Service Charge and Tax (Guaranteed integer Rupiah rounding)
            _buildSummaryRow(tr('subtotal'), calc.formattedSubtotal),
            if (calc.serviceAmount > 0)
              _buildSummaryRow(
                '${tr('service_charge')} (${_settings.serviceChargeRate.toStringAsFixed(0)}%)',
                calc.formattedServiceAmount,
              ),
            _buildSummaryRow(
              '${tr('tax')} (${_settings.taxRate.toStringAsFixed(0)}%)',
              calc.formattedTaxAmount,
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr('total'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
                ),
                Text(
                  calc.formattedGrandTotal,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.royalBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Payment Methods
            Text(
              tr('payment_method'),
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_settings.enableCash) ...[
                  _buildPayChip('Cash', Icons.money, 'Cash (Offline)'),
                  const SizedBox(width: 8),
                ],
                if (_settings.enableMidtransQris || _settings.enableMidtransCard) ...[
                  _buildPayChip('Midtrans Sandbox', Icons.qr_code_2_rounded, 'Midtrans (QRIS/Card)'),
                  const SizedBox(width: 8),
                ],
                _buildPayChip('Card', Icons.credit_card, 'EDC Terminal'),
              ],
            ),

            if (_paymentMethod == 'Midtrans Sandbox') ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: !_connectivity.isOnline ? const Color(0xFFFEF3C7) : AppTheme.lightBlueTint,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: !_connectivity.isOnline ? const Color(0xFFFDE68A) : AppTheme.blueSubtle,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      !_connectivity.isOnline ? Icons.wifi_off_rounded : Icons.shield_rounded,
                      color: !_connectivity.isOnline ? const Color(0xFFB45309) : AppTheme.cobaltBlue,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        !_connectivity.isOnline
                            ? tr('midtrans_offline_warning')
                            : 'Midtrans Sandbox Snap Modal (QRIS & Kartu Kredit Uji) • Real-time API',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: !_connectivity.isOnline ? const Color(0xFFB45309) : AppTheme.darkNavy,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_paymentMethod == 'Cash') ...[
              const SizedBox(height: 12),
              Text(
                tr('cash_received'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.darkNavy),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _cashController,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  prefixText: 'Rp ',
                  hintText: 'Contoh: 100k, 50rb, 100.000',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                    borderSide: BorderSide(color: AppTheme.royalBlue, width: 1.5),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              // Quick cash chips: Uang Pas, 20k, 50k, 100k, 200k
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickCashChip('Uang Pas', calc.grandTotal.toDouble()),
                    const SizedBox(width: 6),
                    _buildQuickCashChip('20k', 20000),
                    const SizedBox(width: 6),
                    _buildQuickCashChip('50k', 50000),
                    const SizedBox(width: 6),
                    _buildQuickCashChip('100k', 100000),
                    const SizedBox(width: 6),
                    _buildQuickCashChip('200k', 200000),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: calc.isPaidSufficient ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: calc.isPaidSufficient ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          calc.isPaidSufficient ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                          size: 16,
                          color: calc.isPaidSufficient ? const Color(0xFF15803D) : AppTheme.roseRed,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          calc.isPaidSufficient ? tr('change') : 'Insufficient Cash',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: calc.isPaidSufficient ? AppTheme.darkNavy : AppTheme.roseRed,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      calc.isPaidSufficient
                          ? calc.formattedChange
                          : '- Rp ${ReceiptCalculation.formatRupiah(calc.shortage)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: calc.isPaidSufficient ? const Color(0xFF15803D) : AppTheme.roseRed,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: canCheckout ? _handleConfirmCheckout : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canCheckout ? AppTheme.goldenAmber : Colors.grey.shade300,
                  foregroundColor: canCheckout ? AppTheme.darkNavy : Colors.grey.shade600,
                  elevation: canCheckout ? 2 : 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isCheckingOut
                    ? const SizedBox.shrink()
                    : Icon(
                        _paymentMethod == 'Midtrans Sandbox'
                            ? Icons.qr_code_2_rounded
                            : Icons.check_circle_rounded,
                        size: 20,
                        color: canCheckout ? AppTheme.darkNavy : Colors.grey.shade600,
                      ),
                label: _isCheckingOut
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: AppTheme.darkNavy, strokeWidth: 2.5),
                      )
                    : Text(
                        _paymentMethod == 'Midtrans Sandbox'
                            ? 'Open Midtrans Snap Checkout'
                            : tr('confirm_payment'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: canCheckout ? AppTheme.darkNavy : Colors.grey.shade600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildPayChip(String method, IconData icon, [String? displayLabel]) {
    final isSelected = _paymentMethod == method;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _paymentMethod = method),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.royalBlue : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.royalBlue : AppTheme.cardBorder,
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: isSelected ? AppTheme.brightYellow : AppTheme.darkNavy),
              const SizedBox(height: 3),
              Text(
                displayLabel ?? method,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? Colors.white : AppTheme.darkNavy,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickCashChip(String label, double amount) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.royalBlue)),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      backgroundColor: AppTheme.lightBlueTint,
      side: const BorderSide(color: AppTheme.blueSubtle),
      onPressed: () {
        setState(() {
          _cashController.text = amount.toStringAsFixed(0);
        });
      },
    );
  }
}

class _SunburstPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Radial gradient: warm sun yellow to soft warm cream
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0.65, -0.1),
        radius: 1.15,
        colors: [
          Color(0xFFFEF9C3), // Soft Warm Sun Yellow
          Color(0xFFFFFBEB), // Cream Warm White
          Color(0xFFFEF3C7), // Amber Light
        ],
      ).createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(24)), bgPaint);

    final origin = Offset(size.width * 0.78, size.height * 0.45);
    final rayPaint = Paint()
      ..color = const Color(0xFFFDE68A).withAlpha(80)
      ..style = PaintingStyle.fill;

    const numRays = 16;
    final rayRadius = math.max(size.width, size.height) * 1.5;
    final sweep = (2 * math.pi) / (numRays * 2);

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(24)));
    for (int i = 0; i < numRays; i++) {
      final angle = i * 2 * sweep;
      final path = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(origin.dx + rayRadius * math.cos(angle), origin.dy + rayRadius * math.sin(angle))
        ..lineTo(origin.dx + rayRadius * math.cos(angle + sweep), origin.dy + rayRadius * math.sin(angle + sweep))
        ..close();
      canvas.drawPath(path, rayPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
