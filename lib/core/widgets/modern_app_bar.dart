import 'package:flutter/material.dart';

import '../layout/adaptive_layout.dart';
import '../utils/asset_utils.dart';
import '../utils/device_utils.dart';
import '../utils/font_utils.dart';

/// Modern AppBar with gradient background and custom design
class ModernAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final Widget? leading;
  final Color? backgroundColor;
  final bool centerTitle;
  final bool showGradient;

  const ModernAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBackButton = true,
    this.onBackPressed,
    this.leading,
    this.backgroundColor,
    this.centerTitle = false,
    this.showGradient = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final isDesktop = !AdaptiveLayout.isCompact(context);
    final foregroundColor = isDesktop ? const Color(0xFF1F2937) : Colors.white;
    final backIconColor = isDesktop ? const Color(0xFF4B5563) : Colors.white;

    if (isDesktop) {
      return Container(
        color: Colors.transparent,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                // Leading/Back button
                if (showBackButton || leading != null)
                  leading ??
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Icon(
                            Icons.arrow_back_ios_new,
                            color: backIconColor,
                            size: 18,
                          ),
                        ),
                        onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
                      ),

                // Title
                if (centerTitle) const Spacer(),
                Expanded(
                  flex: centerTitle ? 0 : 1,
                  child: Text(
                    title,
                    style: FontUtilities.style(
                      fontSize: 22,
                      fontWeight: FWT.bold,
                      fontColor: foregroundColor,
                    ),
                    textAlign: centerTitle ? TextAlign.center : TextAlign.left,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                if (centerTitle) const Spacer(),

                // Actions
                if (actions != null) ...[
                  const SizedBox(width: 8),
                  ...actions!.map((action) {
                    if (action is IconButton) {
                      return Container(
                        margin: const EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: IconTheme(
                          data: IconThemeData(color: foregroundColor, size: 20),
                          child: action,
                        ),
                      );
                    }
                    return action;
                  }),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: showGradient
          ? const BoxDecoration(
              image: DecorationImage(
                image: AssetImage(AssetUtilities.bgImage),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            )
          : BoxDecoration(
              color: backgroundColor ?? const Color(0xFF095763),
            ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.scp(context), vertical: 8.scp(context)),
          child: Row(
            children: [
              // Leading/Back button
              if (showBackButton || leading != null)
                leading ??
                    IconButton(
                      icon: Container(
                        padding: EdgeInsets.all(8.scp(context)),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                          size: 18.scp(context),
                        ),
                      ),
                      onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
                    ),

              // Title
              if (centerTitle) const Spacer(),
              Expanded(
                flex: centerTitle ? 0 : 1,
                child: Text(
                  title,
                  style: FontUtilities.style(
                    fontSize: 20.scp(context),
                    fontWeight: FWT.bold,
                    fontColor: Colors.white,
                  ),
                  textAlign: centerTitle ? TextAlign.center : TextAlign.left,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              if (centerTitle) const Spacer(),

              // Actions
              if (actions != null) ...[
                SizedBox(width: 8.scp(context)),
                ...actions!.map((action) {
                  if (action is IconButton) {
                    return Container(
                      margin: EdgeInsets.only(left: 4.scp(context)),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: action,
                    );
                  }
                  return action;
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating AppBar for special screens
class FloatingAppBar extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final VoidCallback? onBackPressed;
  final bool showGradient;

  const FloatingAppBar({
    super.key,
    required this.title,
    this.actions,
    this.onBackPressed,
    this.showGradient = true,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        margin: EdgeInsets.all(16.scp(context)),
        padding: EdgeInsets.symmetric(horizontal: 16.scp(context), vertical: 12.scp(context)),
        decoration: BoxDecoration(
          image: showGradient
              ? const DecorationImage(
                  image: AssetImage(AssetUtilities.bgImage),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                )
              : null,
          color: showGradient ? null : Colors.white,
          borderRadius: BorderRadius.circular(16.scp(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          children: [
            // Back button
            IconButton(
              icon: Container(
                padding: EdgeInsets.all(8.scp(context)),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 18.scp(context),
                ),
              ),
              onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
            ),

            SizedBox(width: 8.scp(context)),

            // Title
            Expanded(
              child: Text(
                title,
                style: FontUtilities.style(
                  fontSize: 18.scp(context),
                  fontWeight: FWT.bold,
                  fontColor: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Actions
            if (actions != null) ...actions!,
          ],
        ),
      ),
    );
  }
}
