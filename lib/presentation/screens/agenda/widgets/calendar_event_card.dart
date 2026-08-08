import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../domain/models/calendar_event.dart';

class CalendarEventCard extends StatelessWidget {
  final CalendarEvent event;
  final VoidCallback onTap;

  const CalendarEventCard({
    super.key,
    required this.event,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (indicatorColor, bgColor, sourceName, isAi) = _getEventStyling();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: indicatorColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_formatTime(event.startTime)} - ${_formatTime(event.endTime)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isAi ? indicatorColor : AppColors.textSecondary,
                          fontWeight: isAi ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (isAi)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: indicatorColor.withOpacity(0.1),
                                border: Border.all(color: indicatorColor.withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome, size: 10, color: indicatorColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    sourceName,
                                    style: TextStyle(fontSize: 10, color: indicatorColor),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                sourceName,
                                style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                              ),
                            ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  (Color, Color, String, bool) _getEventStyling() {
    switch (event.source) {
      case EventSource.sopro:
        return (AppColors.accent, AppColors.backgroundCard, 'Sopro', false);
      case EventSource.soproAi:
        return (AppColors.onboardingNotification, AppColors.onboardingNotification.withOpacity(0.05), 'Sopro AI', true);
      case EventSource.google:
        return (const Color(0xFF4285F4), AppColors.backgroundCard, 'Google', false);
      case EventSource.apple:
        return (const Color(0xFFA3AAAE), AppColors.backgroundCard, 'Apple', false);
      case EventSource.outlook:
        return (const Color(0xFF0078D4), AppColors.backgroundCard, 'Outlook', false);
      case EventSource.other:
      default:
        return (AppColors.textDisabled, AppColors.backgroundCard, event.calendarName ?? 'Outro', false);
    }
  }
}
