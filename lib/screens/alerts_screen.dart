import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/bus_models.dart';
import '../providers/bus_provider.dart';
import '../theme/app_theme.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: Consumer<BusProvider>(
        builder: (context, busProvider, child) {
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                title: Text(strings.t('alerts_notifications')),
                floating: true,
                pinned: true,
              ),
              if (busProvider.alerts.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          strings.t(
                            'unread_alerts',
                            params: {
                              'count':
                                  '${busProvider.alerts.where((a) => !a.isRead).length}',
                            },
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        TextButton(
                          onPressed: () async =>
                              await busProvider.clearAllAlerts(),
                          child: Text(
                            strings.t('clear_all'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (busProvider.alerts.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppTheme.surface(context),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.shadow(context),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.notifications_active_outlined,
                            size: 64,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          strings.t('no_active_alerts'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.t('caught_up'),
                          style: TextStyle(
                            fontSize: 15,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final alert = busProvider.alerts[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AlertCard(
                          alert: alert,
                          onTap: () async =>
                              await busProvider.markAlertAsRead(alert.id),
                        ),
                      );
                    }, childCount: busProvider.alerts.length),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AlertCard extends StatelessWidget {
  final Alert alert;
  final VoidCallback onTap;

  const AlertCard({super.key, required this.alert, required this.onTap});

  Color _getAlertColor(String type) {
    switch (type.toLowerCase()) {
      case 'error':
        return AppTheme.alertRed;
      case 'warning':
        return AppTheme.accentOrange;
      case 'info':
        return AppTheme.primaryBlue;
      default:
        return AppTheme.textMuted;
    }
  }

  IconData _getAlertIcon(String type) {
    switch (type.toLowerCase()) {
      case 'error':
        return Icons.error_rounded;
      case 'warning':
        return Icons.warning_rounded;
      case 'info':
        return Icons.info_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final alertColor = _getAlertColor(alert.type);
    final alertIcon = _getAlertIcon(alert.type);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: alert.isRead ? Colors.transparent : AppTheme.surface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: alert.isRead
                ? AppTheme.divider(context)
                : Colors.transparent,
          ),
          boxShadow: alert.isRead
              ? null
              : [
                  BoxShadow(
                    color: AppTheme.shadow(context),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: alert.isRead
                    ? AppTheme.divider(context)
                    : alertColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                alertIcon,
                color: alert.isRead
                    ? AppTheme.textSecondary(context)
                    : alertColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          alert.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: alert.isRead
                                ? FontWeight.w600
                                : FontWeight.w700,
                            color: alert.isRead
                                ? AppTheme.textSecondary(context)
                                : AppTheme.textPrimary(context),
                          ),
                        ),
                      ),
                      if (!alert.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: alertColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    alert.message,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary(context),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _formatTime(context, alert.timestamp),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(BuildContext context, DateTime timestamp) {
    final strings = context.strings;
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return strings.t('just_now');
    if (diff.inMinutes < 60) {
      return strings.t('mins_ago', params: {'count': '${diff.inMinutes}'});
    }
    if (diff.inHours < 24) {
      return strings.t('hours_ago', params: {'count': '${diff.inHours}'});
    }
    return strings.t('days_ago', params: {'count': '${diff.inDays}'});
  }
}
