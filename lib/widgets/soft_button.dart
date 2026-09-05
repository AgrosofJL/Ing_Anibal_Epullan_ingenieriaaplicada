import 'package:flutter/material.dart';
import '../constantes/tema.dart';

class SoftButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool isSecondary;

  const SoftButton({
    super.key,
    required this.child,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.borderRadius = AgroTheme.radiusMd,
    this.isSecondary = false,
  });

  @override
  State<SoftButton> createState() => _SoftButtonState();
}

class _SoftButtonState extends State<SoftButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool disabled = widget.onTap == null;

    return GestureDetector(
      onTapDown: disabled ? null : (_) => setState(() => _isPressed = true),
      onTapUp: disabled ? null : (_) => setState(() => _isPressed = false),
      // 🛠️ ESTO LO MODIFIQUE: onTapCancel sin argumentos
      onTapCancel: disabled ? null : () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.identity()..scale(_isPressed ? 0.98 : 1.0),
        padding: widget.padding,
        decoration: BoxDecoration(
          color: disabled
              ? Colors.grey.shade300
              : _isPressed
                  ? AgroTheme.colorActiveBg
                  : widget.isSecondary
                      ? AgroTheme.colorSurface
                      : AgroTheme.colorAccent,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            color: _isPressed
                ? AgroTheme.colorActiveBorder
                : widget.isSecondary
                    ? AgroTheme.colorBorder
                    : Colors.transparent,
            width: 1.2,
          ),
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                    color: const Color(0xFFFBC02D).withOpacity(0.35),
                    blurRadius: 6,
                    spreadRadius: 1,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: const Color(0x141E1803).withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
        ),
        child: widget.child,
      ),
    );
  }
}