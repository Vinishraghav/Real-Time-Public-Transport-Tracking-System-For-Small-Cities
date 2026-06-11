import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/auth_provider.dart';
import '../providers/bus_provider.dart';
import '../providers/location_provider.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isSaving = false;

  Future<void> _updatePreference(Future<void> Function() action) async {
    setState(() => _isSaving = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final backgroundColor = AppTheme.background(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Consumer3<AuthProvider, BusProvider, LocationProvider>(
        builder: (context, authProvider, busProvider, locationProvider, _) {
          final session = authProvider.session;
          final isDriver = session?.isDriver ?? false;
          final title = isDriver
              ? 'Driver - Bus ${session?.busNumber ?? "N/A"}'
              : (session?.displayName ??
                    (strings.isTamil ? 'பயணி' : 'Passenger'));
          final subtitle = isDriver
              ? 'Status: ${busProvider.tripStatus.name.toUpperCase()}'
              : (strings.isTamil
                    ? 'நேரடி பஸ் கண்காணிப்பு'
                    : 'Tracking buses in real-time');

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                backgroundColor: AppTheme.primaryBlue,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppTheme.primaryBlue, Color(0xFF1D3557)],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                color: AppTheme.surface(context),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                                border: Border.all(
                                  color: AppTheme.accentOrange,
                                  width: 3,
                                ),
                              ),
                              child: const Icon(
                                Icons.person_rounded,
                                size: 48,
                                color: AppTheme.primaryBlue,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              title,
                              style: const TextStyle(
                                color: AppTheme.surfaceWhite,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isDriver
                                    ? AppTheme.successGreen
                                    : Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                subtitle,
                                style: const TextStyle(
                                  color: AppTheme.surfaceWhite,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSection(
                        context: context,
                        title: strings.t('account_preferences'),
                        children: [
                          _buildTile(
                            context: context,
                            icon: Icons.person_outline_rounded,
                            title: strings.t('edit_profile'),
                            subtitle:
                                session?.displayName ??
                                strings.t('set_display_name'),
                            onTap: session == null
                                ? null
                                : () => _showProfileDialog(
                                    authProvider,
                                    session.displayName,
                                  ),
                          ),
                          _buildSwitchTile(
                            context: context,
                            icon: Icons.dark_mode_rounded,
                            title: strings.t('dark_mode'),
                            subtitle: strings.t('switch_appearance'),
                            value: session?.darkMode ?? false,
                            onChanged: (value) => _updatePreference(
                              () => authProvider.updatePreferences(
                                darkMode: value,
                              ),
                            ),
                          ),
                          _buildTile(
                            context: context,
                            icon: Icons.language_rounded,
                            title: strings.t('language'),
                            subtitle: session?.language ?? 'English',
                            onTap: session == null
                                ? null
                                : () => _showLanguageDialog(authProvider),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildSection(
                        context: context,
                        title: strings.t('application_settings'),
                        children: [
                          _buildSwitchTile(
                            context: context,
                            icon: Icons.my_location_rounded,
                            title: strings.t('location_services'),
                            subtitle: locationProvider.isLocationEnabled
                                ? strings.t('access_granted')
                                : strings.t('access_denied'),
                            value: locationProvider.isLocationEnabled,
                            onChanged: (value) {
                              if (value) {
                                locationProvider.requestLocationPermission();
                              } else {
                                locationProvider.openLocationSettings();
                              }
                            },
                          ),
                          _buildSwitchTile(
                            context: context,
                            icon: Icons.notifications_active_rounded,
                            title: strings.t('push_notifications'),
                            subtitle: strings.t('stay_updated'),
                            value: session?.notificationsEnabled ?? true,
                            onChanged: (value) => _updatePreference(
                              () => authProvider.updatePreferences(
                                notificationsEnabled: value,
                              ),
                            ),
                          ),
                          _buildSwitchTile(
                            context: context,
                            icon: Icons.data_saver_on_rounded,
                            title: strings.t('data_saver'),
                            subtitle: strings.t('reduce_refresh_scope'),
                            value: session?.dataSaver ?? false,
                            onChanged: (value) => _updatePreference(
                              () => authProvider.updatePreferences(
                                dataSaver: value,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildSection(
                        context: context,
                        title: strings.t('support_info'),
                        children: [
                          _buildTile(
                            context: context,
                            icon: Icons.info_rounded,
                            title: strings.t('about_citybus'),
                            subtitle: strings.t('about_version'),
                            onTap: _showAboutDialog,
                          ),
                          _buildTile(
                            context: context,
                            icon: Icons.logout_rounded,
                            title: strings.t('logout'),
                            subtitle: strings.t('sign_out_current'),
                            isDestructive: true,
                            onTap: session == null
                                ? null
                                : () async {
                                    await authProvider.signOut();
                                    locationProvider.stopLocationStream();
                                    if (context.mounted) {
                                      context.go('/login');
                                    }
                                  },
                          ),
                        ],
                      ),
                      if (_isSaving) ...[
                        const SizedBox(height: 24),
                        const Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(context),
              letterSpacing: -0.3,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppTheme.shadow(context),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      (isDestructive ? AppTheme.alertRed : AppTheme.primaryBlue)
                          .withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: isDestructive
                      ? AppTheme.alertRed
                      : AppTheme.primaryBlue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDestructive
                            ? AppTheme.alertRed
                            : AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppTheme.textSecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppTheme.primaryBlue, size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.surfaceWhite,
            activeTrackColor: AppTheme.successGreen,
            inactiveTrackColor: AppTheme.divider(context),
            inactiveThumbColor: AppTheme.surfaceWhite,
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(AuthProvider authProvider) {
    final strings = context.l10n;
    String tempLanguage = authProvider.session?.language ?? 'English';
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                strings.t('select_language'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: ['English', 'Tamil']
                    .map(
                      (language) => ListTile(
                        title: Text(
                          language,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        leading: Icon(
                          tempLanguage == language
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: tempLanguage == language
                              ? AppTheme.primaryBlue
                              : AppTheme.textMuted,
                        ),
                        onTap: () async {
                          setDialogState(() => tempLanguage = language);
                          await authProvider.updatePreferences(
                            language: language,
                          );
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    )
                    .toList(),
              ),
            );
          },
        );
      },
    );
  }

  void _showProfileDialog(AuthProvider authProvider, String currentName) {
    final strings = context.l10n;
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(strings.t('edit_profile')),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: strings.t('set_display_name'),
              prefixIcon: const Icon(Icons.person_rounded),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.t('cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                await authProvider.updatePreferences(
                  displayName: controller.text.trim(),
                );
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(strings.t('save')),
            ),
          ],
        );
      },
    ).then((_) => controller.dispose());
  }

  void _showAboutDialog() {
    final strings = context.l10n;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.directions_bus_rounded,
                  size: 56,
                  color: AppTheme.primaryBlue,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'CityBus Live',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.t('about_version'),
                style: TextStyle(
                  color: AppTheme.textSecondary(context),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                strings.isTamil
                    ? 'டிரைவர்கள் மற்றும் பயணிகளுக்கான நேரடி பஸ் கண்காணிப்பு, ETA, ride alerts மற்றும் route visibility உடன்.'
                    : 'Real-time bus tracking for drivers and passengers with trip sync, ETA, ride alerts, and live route visibility.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary(context),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(strings.t('continue')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
