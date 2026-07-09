import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AmbientShaderBackground extends StatefulWidget {
  final Widget child;
  final bool isCharging;

  const AmbientShaderBackground({
    Key? key,
    required this.child,
    required this.isCharging,
  }) : super(key: key);

  @override
  State<AmbientShaderBackground> createState() => _AmbientShaderBackgroundState();
}

class _AmbientShaderBackgroundState extends State<AmbientShaderBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _ShaderPainter(
            time: _controller.value,
            isCharging: widget.isCharging,
            isDark: isDark,
          ),
          child: widget.child,
        );
      },
    );
  }
}

class _ShaderPainter extends CustomPainter {
  final double time;
  final bool isCharging;
  final bool isDark;

  _ShaderPainter({
    required this.time,
    required this.isCharging,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw solid background
    final baseColor = isDark ? const Color(0xFF0F1813) : const Color(0xFFF1FCF1);
    final basePaint = Paint()..color = baseColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), basePaint);

    // 2. Draw soft ambient glow (shifting center)
    final center = Offset(
      size.width * (0.5 + 0.1 * sin(time * 2 * pi)),
      size.height * (0.5 + 0.1 * cos(time * 2 * pi)),
    );
    final radius = max(size.width, size.height) * 0.9;

    final accentColor = isCharging
        ? (isDark ? const Color(0xFF20354E) : const Color(0xFFB7C8DF)) // soft blue
        : (isDark ? const Color(0xFF1E3529) : const Color(0xFFD2E7DB)); // soft green

    final gradient = RadialGradient(
      center: Alignment.center,
      colors: [
        accentColor.withOpacity(isDark ? 0.5 : 0.35),
        baseColor.withOpacity(0.0),
      ],
      stops: const [0.0, 1.0],
    );

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      );

    canvas.drawCircle(center, radius, paint);

    // 3. Draw soft flowing circular pattern (rings/ambient current flow)
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = accentColor.withOpacity(isDark ? 0.3 : 0.2 * (sin(time * 2 * pi * 2) * 0.4 + 0.6));

    final ringRadius = min(size.width, size.height) * 0.35 +
        12.0 * sin(time * 2 * pi * 3);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), ringRadius, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _ShaderPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.isCharging != isCharging ||
      oldDelegate.isDark != isDark;
}

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const CustomAppBar({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? const Color(0xFFB6BBB7) : const Color(0xFF4F635B);
    final Color borderColor = isDark ? const Color(0xFF223228) : const Color(0xFFC2C8C4);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1813) : const Color(0xFFF1FCF1),
        border: Border(
          bottom: BorderSide(
            color: borderColor,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 56,
          child: NavigationToolbar(
            leading: IconButton(
              icon: Icon(Icons.eco, color: textColor),
              onPressed: () {},
            ),
            middle: Text(
              title,
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            trailing: const SizedBox(width: 48),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class CustomNavBar extends StatelessWidget {
  final int activeIndex;

  const CustomNavBar({Key? key, required this.activeIndex}) : super(key: key);

  void _onTabTapped(BuildContext context, int index) {
    if (index == activeIndex) return;

    switch (index) {
      case 0:
        Navigator.of(context).pushReplacementNamed('/status');
        break;
      case 1:
        Navigator.of(context).pushReplacementNamed('/energy');
        break;
      case 2:
        Navigator.of(context).pushReplacementNamed('/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bgColor = isDark ? const Color(0xFF16221A) : const Color(0xFFEBF7EC);
    final Color borderColor = isDark ? const Color(0xFF2A3D31) : const Color(0xFFDAE6DB).withOpacity(0.5);

    return Container(
      padding: EdgeInsets.only(
        top: 10,
        bottom: bottomPadding > 0 ? bottomPadding : 10,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border.all(
          color: borderColor,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            context,
            index: 0,
            icon: Icons.spa,
            label: 'Status',
            isDark: isDark,
          ),
          _buildNavItem(
            context,
            index: 1,
            icon: Icons.solar_power,
            label: 'Energy',
            isDark: isDark,
          ),
          _buildNavItem(
            context,
            index: 2,
            icon: Icons.settings,
            label: 'Settings',
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    final bool isActive = index == activeIndex;

    final Color activeBgColor = isDark ? const Color(0xFF2E4338) : const Color(0xFFD1E7DD);
    final Color activeTextColor = isDark ? const Color(0xFFE0EAE1) : const Color(0xFF141E17);
    final Color inactiveTextColor = isDark ? const Color(0xFF8B9B90) : const Color(0xFF424845);

    return GestureDetector(
      onTap: () => _onTabTapped(context, index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? activeBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? activeTextColor : inactiveTextColor,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? activeTextColor : inactiveTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
