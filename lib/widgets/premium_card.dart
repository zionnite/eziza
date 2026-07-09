import 'package:flutter/material.dart';

import '../constants/colors.dart';

/// Shared "premium" visual language for delivery/bid/earnings cards --
/// floating white shell (soft diffuse shadow, no hard border), gradient
/// icon badges instead of tiny line icons, a compact route timeline
/// instead of nested bordered address boxes, and gradient-filled tags/
/// buttons instead of flat tinted pills. Built once so every role
/// (rider/company/customer) renders the same premium feel instead of
/// each dashboard file drifting its own flat/boxy style.

/// Elevated white shell with a soft, diffuse shadow (no hard border) and
/// a real ink ripple on tap.
class PremiumCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? glow;
  final double radius;

  const PremiumCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 14),
    this.glow,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: EzizaColors.kWhite,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: (glow ?? EzizaColors.kNavy).withValues(alpha: 0.10),
            blurRadius: 28,
            offset: const Offset(0, 14),
            spreadRadius: -10,
          ),
          BoxShadow(
            color: EzizaColors.kNavy.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: EzizaColors.kPurple.withValues(alpha: 0.06),
          highlightColor: EzizaColors.kPurple.withValues(alpha: 0.03),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Soft gradient-tinted circular icon badge -- replaces small flat line
/// icons for a card's primary status/role indicator.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.46),
    );
  }
}

/// Gradient-filled status pill (solid saturated fill, not a tinted outline
/// -- reads as more premium at small sizes than a bordered chip).
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const StatusPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.2)),
      );
}

/// Compact pickup -> drop-off timeline (dot, connecting line, dot) used
/// inside cards -- replaces two separately-bordered address boxes with one
/// clean Uber/Bolt-style route line.
class RouteTimeline extends StatelessWidget {
  final String pickup;
  final String dropoff;
  final TextStyle? style;

  const RouteTimeline({
    super.key,
    required this.pickup,
    required this.dropoff,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = style ??
        const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: EzizaColors.kText,
            height: 1.25);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 3),
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: EzizaColors.kGold)),
        Container(
          width: 2,
          height: 24,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                EzizaColors.kGold.withValues(alpha: 0.45),
                EzizaColors.kPurple.withValues(alpha: 0.45),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: EzizaColors.kPurple)),
      ]),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pickup,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
          const SizedBox(height: 13),
          Text(dropoff,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
        ]),
      ),
    ]);
  }
}

/// Gradient-filled money tag -- solid saturated pill with a bold amount,
/// used wherever a card needs to draw the eye to a price/fee/earning.
class MoneyTag extends StatelessWidget {
  final String amount;
  final IconData icon;
  final List<Color> colors;

  const MoneyTag({
    super.key,
    required this.amount,
    this.icon = Icons.payments_rounded,
    this.colors = const [EzizaColors.kSuccess, Color(0xFF1E8449)],
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: colors.first.withValues(alpha: 0.30),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(amount,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
      );
}

/// Gradient CTA button with glow shadow + real ink ripple -- the shared
/// premium action button (e.g. "Make an Offer", "Track Live").
class PremiumButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final List<Color> colors;
  final Color iconColor;
  final double radius;

  const PremiumButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.colors = const [EzizaColors.kPurple, EzizaColors.kPurpleD],
    this.iconColor = Colors.white,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                    color: colors.last.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5)),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 7),
              Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.2)),
            ]),
          ),
        ),
      );
}

/// Small soft-tint info pill (icon + label) -- for meta info like time,
/// distance, state, that isn't a status or a money amount.
class InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const InfoPill({
    super.key,
    required this.icon,
    required this.label,
    this.color = EzizaColors.kMuted,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
        ]),
      );
}
