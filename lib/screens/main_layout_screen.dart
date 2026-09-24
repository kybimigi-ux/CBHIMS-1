import 'package:flutter/material.dart';
import '../services/hardware_context.dart';
import '../theme/app_theme.dart';
import '../widgets/sidebar.dart';
import 'tabs/dashboard_screen.dart';
import 'tabs/inventory_screen.dart';
import 'tabs/transactions_screen.dart';
import 'tabs/reports_screen.dart';
import 'tabs/settings_screen.dart';
import 'tabs/account_screen.dart';

/// The persistent app shell: a fixed sidebar on the left and a main
/// content area on the right that swaps screens based on the active
/// navigation item.
class MainLayoutScreen extends StatefulWidget {
  const MainLayoutScreen({super.key});

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  int _selectedIndex = 0;

  void setTab(int index) {
    if (index >= 0 && index < 6) {
      setState(() => _selectedIndex = index);
    }
  }

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return DashboardScreen(onNavigateToTab: setTab);
      case 1:
        return const InventoryScreen();
      case 2:
        return const TransactionsScreen();
      case 3:
        return const ReportsScreen();
      case 4:
        return const SettingsScreen();
      case 5:
        return const AccountScreen();
      default:
        return DashboardScreen(onNavigateToTab: setTab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showSidebarInline = MediaQuery.of(context).size.width >= 900;

    return ListenableBuilder(
      listenable: HardwareContext.instance,
      builder: (context, _) {
        final activeHw = HardwareContext.instance.activeHardware;
        final activeId = activeHw?.id ?? 'none';

        return Scaffold(
          backgroundColor: AppColors.background,
          drawer: showSidebarInline
              ? null
              : Drawer(
                  child: Sidebar(
                    selectedIndex: _selectedIndex,
                    onSelect: (i) {
                      setState(() => _selectedIndex = i);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
          appBar: showSidebarInline
              ? null
              : AppBar(
                  backgroundColor: AppColors.surface,
                  elevation: 0,
                  foregroundColor: AppColors.textPrimary,
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(kNavItems[_selectedIndex].label,
                          style: AppTextStyles.h3),
                      if (activeHw != null)
                        Text(
                          activeHw.name,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.primary, fontSize: 11),
                        ),
                    ],
                  ),
                ),
          body: Row(
            children: [
              if (showSidebarInline)
                Sidebar(
                  selectedIndex: _selectedIndex,
                  onSelect: (i) => setState(() => _selectedIndex = i),
                ),
              if (showSidebarInline)
                const VerticalDivider(
                    width: 1, thickness: 1, color: AppColors.border),
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey('${activeId}_$_selectedIndex'),
                  child: Container(
                    color: AppColors.background,
                    child: _buildScreen(_selectedIndex),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: showSidebarInline
              ? null
              : Container(
                  decoration: const BoxDecoration(
                    border: Border(
                        top: BorderSide(color: AppColors.border, width: 0.5)),
                  ),
                  child: BottomNavigationBar(
                    currentIndex: _selectedIndex < 5 ? _selectedIndex : 0,
                    onTap: (i) => setState(() => _selectedIndex = i),
                    type: BottomNavigationBarType.fixed,
                    backgroundColor: AppColors.surface,
                    selectedItemColor: AppColors.primary,
                    unselectedItemColor: AppColors.textMuted,
                    selectedFontSize: 11,
                    unselectedFontSize: 11,
                    iconSize: 22,
                    items: [
                      for (int i = 0; i < 5; i++)
                        BottomNavigationBarItem(
                          icon: Icon(kNavItems[i].icon),
                          activeIcon: Icon(kNavItems[i].activeIcon),
                          label: kNavItems[i].label,
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
