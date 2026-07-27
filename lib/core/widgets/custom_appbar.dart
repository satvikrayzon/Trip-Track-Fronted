import 'package:flutter/material.dart';
import 'package:trip_track/core/utils/device_utils.dart';
import '../layout/adaptive_layout.dart';

import '../utils/font_utils.dart';

// class CustomAppBar extends StatefulWidget {
//   final String title;
//   final double? height;
//   final bool showBackButton;
//   final Widget? leading;
//   final Widget? titleWidget;
//   final List<Widget>? action;
//   Function(String?)? onChange;
//   final VoidCallback? onBackTap;
//   final bool isCenterTitle;
//   final VoidCallback? onClear;
//   bool showSearch;
//   TextEditingController? controller;

//   CustomAppBar(
//       {super.key,
//       required this.title,
//       this.action,
//       this.onBackTap,
//       this.showBackButton = true,
//       this.onChange,
//       this.isCenterTitle = false,
//       this.height,
//       this.leading,
//       this.titleWidget,
//       this.showSearch = false,
//       this.controller,
//       this.onClear});

//   @override
//   State<CustomAppBar> createState() => _CustomAppBarState();
// }

// class _CustomAppBarState extends State<CustomAppBar> {
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: MediaQuery.of(context).size.width,
//       decoration: BoxDecoration(
//           borderRadius: BorderRadius.vertical(
//             bottom: Radius.circular(20.scp(context)),
//           ),
//           color: Colors.transparent),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.start,
//         children: [
//           widget.leading ??
//               Visibility(
//                 visible: widget.showBackButton,
//                 child: Padding(
//                   padding: EdgeInsets.fromLTRB(
//                       16.scp(context), 8.scp(context), 0, 8.scp(context)),
//                   child: Material(
//                     color: Colors.transparent,
//                     child: InkWell(
//                       onTap: widget.onBackTap ??
//                           () {
//                             if (Navigator.canPop(context)) {
//                               Navigator.pop(context);
//                             }
//                           },
//                       customBorder: const CircleBorder(),
//                       borderRadius: BorderRadius.circular(12.scp(context)),
//                       child: FancyBorderCard(
//                         boxShape: BoxShape.circle,
//                         child: Padding(
//                           padding: EdgeInsets.all(8.scp(context)),
//                           child: Icon(Icons.arrow_back_rounded,
//                               color: VariableUtilities.theme.blackColor,
//                               size: 18.scp(context)),
//                         ),
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//           if (widget.isCenterTitle) ...{const Spacer()},
//           widget.titleWidget ??
//               Padding(
//                 padding:
//                     EdgeInsets.only(left: !widget.isCenterTitle ? 12.0 : 0),
//                 child: Text(
//                   widget.title,
//                   style: FontUtilities.style(
//                       fontSize: 18.scp(context),
//                       fontWeight: FWT.extraBold,
//                       fontColor: VariableUtilities.theme.blackColor),
//                 ),
//               ),
//           const Spacer(),
//           Row(
//             mainAxisAlignment: MainAxisAlignment.end,
//             children: [
//               Row(
//                 children: widget.action ?? [],
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
// }

// TODO: Main AppBar Code
class CustomAppBar extends StatefulWidget {
  final String title;
  final double? height;
  final bool showBackButton;
  final Widget? leading;
  final Widget? titleWidget;
  final List<Widget>? action;
  Function(String?)? onChange;
  final VoidCallback? onBackTap;
  final bool isCenterTitle;
  final VoidCallback? onClear;
  bool showSearch;
  TextEditingController? controller;

  CustomAppBar(
      {super.key,
      required this.title,
      this.action,
      this.onBackTap,
      this.showBackButton = true,
      this.onChange,
      this.isCenterTitle = false,
      this.height,
      this.leading,
      this.titleWidget,
      this.showSearch = false,
      this.controller,
      this.onClear});

  @override
  State<CustomAppBar> createState() => _CustomAppBarState();
}

class _CustomAppBarState extends State<CustomAppBar> {
  @override
  Widget build(BuildContext context) {
    final isDesktop = !AdaptiveLayout.isCompact(context);
    final foregroundColor = isDesktop ? const Color(0xFF1F2937) : Colors.white;
    final backIconColor = isDesktop ? const Color(0xFF4B5563) : Colors.white;

    return Container(
      width: MediaQuery.of(context).size.width,
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          widget.leading ??
              Visibility(
                visible: widget.showBackButton,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onBackTap ??
                        () {
                          if (Navigator.canPop(context)) {
                            Navigator.pop(context);
                          }
                        },
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.arrow_back,
                        color: backIconColor,
                        size: isDesktop ? 24 : 22.scp(context),
                      ),
                    ),
                  ),
                ),
              ),
          if (widget.isCenterTitle) ...{const Spacer()},
          widget.titleWidget ??
              Padding(
                padding: EdgeInsets.only(left: !widget.isCenterTitle ? 12.0 : 0),
                child: Text(
                  widget.title,
                  style: FontUtilities.style(
                    fontSize: isDesktop ? 20 : 16.scp(context),
                    fontWeight: FWT.bold,
                    fontColor: foregroundColor,
                  ),
                ),
              ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconTheme(
                data: IconThemeData(
                  color: foregroundColor,
                  size: isDesktop ? 20 : 16.scp(context),
                ),
                child: Row(
                  children: widget.action ?? [],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// class CustomAppBar extends StatefulWidget {
//   final String title;
//   final double? height;
//   final bool showBackButton;
//   final Widget? leading;
//   final Widget? titleWidget;
//   final List<Widget>? action;
//   Function(String?)? onChange;
//   final VoidCallback? onBackTap;
//   final bool isCenterTitle;
//   final VoidCallback? onClear;
//   bool showSearch;
//   TextEditingController? controller;

//   CustomAppBar({
//     super.key,
//     required this.title,
//     this.action,
//     this.onBackTap,
//     this.showBackButton = true,
//     this.onChange,
//     this.isCenterTitle = false,
//     this.height,
//     this.leading,
//     this.titleWidget,
//     this.showSearch = false,
//     this.controller,
//     this.onClear,
//   });

//   @override
//   State<CustomAppBar> createState() => _CustomAppBarState();
// }

// class _CustomAppBarState extends State<CustomAppBar> {
//   @override
//   Widget build(BuildContext context) {
//     return ClipRRect(
//       borderRadius:
//           BorderRadius.vertical(bottom: Radius.circular(44.scp(context))),
//       child: Container(
//         width: MediaQuery.of(context).size.width,
//         height: widget.height ?? 90.scp(context),
//         decoration: BoxDecoration(
//           borderRadius:
//               BorderRadius.vertical(bottom: Radius.circular(44.scp(context))),
//           boxShadow: [
//             BoxShadow(
//                 color: Colors.black.withOpacity(0.17),
//                 blurRadius: 12,
//                 offset: const Offset(0, 4)),
//           ],
//         ),
//         child: Stack(
//           children: [
//             // Background: glass with reflection
//             BackdropFilter(
//               filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
//               child: Container(
//                 decoration: BoxDecoration(
//                   gradient: LinearGradient(colors: [
//                     Colors.white.withOpacity(0.14),
//                     Colors.white.withOpacity(0.10),
//                   ], begin: Alignment.topLeft, end: Alignment.bottomRight),
//                   border: Border(
//                       bottom: BorderSide(
//                           color: Colors.white.withOpacity(0.05), width: 1.5)),
//                 ),
//               ),
//             ),

//             // subtle inner highlight gradient
//             Container(
//               decoration: BoxDecoration(
//                 gradient: LinearGradient(colors: [
//                   Colors.white.withOpacity(0.1),
//                   Colors.transparent,
//                 ], begin: Alignment.topCenter, end: Alignment.bottomCenter),
//               ),
//             ),

//             // Bottom edge: double border illusion
//             Positioned(
//               bottom: 0,
//               left: 0,
//               right: 0,
//               child: Container(
//                 height: 4.2.scp(context),
//                 decoration: BoxDecoration(
//                     color: Colors.white.withOpacity(0.17),
//                     borderRadius: BorderRadius.circular(33.scp(context))),
//               ),
//             ),
//             Padding(
//               padding: EdgeInsets.fromLTRB(30.scp(context), 40.scp(context),
//                   12.scp(context), 12.scp(context)),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.start,
//                 children: [
//                   widget.leading ??
//                       Visibility(
//                         visible: widget.showBackButton,
//                         child: Material(
//                           color: Colors.transparent,
//                           child: InkWell(
//                             onTap: widget.onBackTap ??
//                                 () {
//                                   if (Navigator.canPop(context)) {
//                                     Navigator.pop(context);
//                                   }
//                                 },
//                             borderRadius:
//                                 BorderRadius.circular(12.scp(context)),
//                             child: Container(
//                               decoration: BoxDecoration(
//                                 color: Colors.white.withOpacity(0.1),
//                                 borderRadius:
//                                     BorderRadius.circular(12.scp(context)),
//                                 border: Border.all(
//                                     color: Colors.white.withOpacity(0.3),
//                                     width: 1.2),
//                               ),
//                               padding: EdgeInsets.all(8.scp(context)),
//                               child: Icon(Icons.arrow_back_rounded,
//                                   color: Colors.white, size: 20.scp(context)),
//                             ),
//                           ),
//                         ),
//                       ),
//                   if (widget.isCenterTitle) const Spacer(),
//                   widget.titleWidget ??
//                       Padding(
//                         padding: EdgeInsets.only(
//                             left: !widget.isCenterTitle ? 20.scp(context) : 0),
//                         child: Text(
//                           widget.title,
//                           style: FontUtilities.style(
//                               fontSize: 20.scp(context),
//                               fontWeight: FWT.semiBold,
//                               fontColor: Colors.white,
//                               letterSpacing: 1.2),
//                         ),
//                       ),
//                   const Spacer(),
//                   Row(
//                     mainAxisAlignment: MainAxisAlignment.end,
//                     children: [
//                       Row(
//                         children: widget.action ?? [],
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
