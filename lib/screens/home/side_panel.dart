import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';

Future<void> showSidePanel({
  required BuildContext context,
  required Widget child,
  bool fromRight = false,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final begin = fromRight ? const Offset(1, 0) : const Offset(-1, 0);
        return SlideTransition(
          position: Tween(begin: begin, end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
    ),
  );
}

class SidePanelShell extends StatelessWidget {
  final bool fromRight;
  final Widget icon; // top-right or top-left button matching trigger
  final List<Widget> items;

  const SidePanelShell({
    super.key,
    required this.fromRight,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: fromRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 260,
          height: double.infinity,
          decoration: BoxDecoration(
            color: AppTheme.bg,
            border: Border(
              left: fromRight
                  ? const BorderSide(color: Colors.white10, width: 0.5)
                  : BorderSide.none,
              right: !fromRight
                  ? const BorderSide(color: Colors.white10, width: 0.5)
                  : BorderSide.none,
            ),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Align(
                    alignment: fromRight ? Alignment.centerRight : Alignment.centerLeft,
                    child: icon,
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: items,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SidePanelGroup extends StatelessWidget {
  final List<SidePanelItem> items;

  const SidePanelGroup({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(items.length, (index) {
          final isLast = index == items.length - 1;
          if (isLast) {
            return items[index];
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              items[index],
              const Divider(
                height: 1,
                color: Colors.white10,
                indent: 16,
                endIndent: 16,
              ),
            ],
          );
        }),
      ),
    );
  }
}

class SidePanelItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const SidePanelItem({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white30,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
