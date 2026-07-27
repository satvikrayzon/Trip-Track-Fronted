import 'package:flutter/material.dart';

import '../layout/adaptive_layout.dart';
import '../utils/asset_utils.dart';
import '../utils/device_utils.dart';

/// Custom header widget with gradient background and curved design
class HeaderWidget extends StatelessWidget {
  final Widget headerChild;
  final Widget child;
  final bool resizeToAvoidBottomInset;
  final double? height;
  final EdgeInsets? padding;

  const HeaderWidget({
    super.key,
    required this.headerChild,
    required this.child,
    this.resizeToAvoidBottomInset = true,
    this.height,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = !AdaptiveLayout.isCompact(context);

    if (isDesktop) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Padding(
            padding: padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                headerChild,
                const SizedBox(height: 16),
                Expanded(
                  child: child,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Container(
          height: double.infinity,
          width: double.infinity,
          alignment: Alignment.topCenter,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage(AssetUtilities.bgImage),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16.0.scp(context),
                  40.scp(context),
                  16.scp(context),
                  6.scp(context),
                ),
                child: headerChild,
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4B8E97),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(50)),
                  ),
                  child: Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(top: 16.scp(context)),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                    ),
                    child: Padding(
                      padding: padding ?? EdgeInsets.only(top: 12.scp(context)),
                      child: child,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
