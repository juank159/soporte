import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import '../config/theme.dart';

class SignaturePadWidget extends StatefulWidget {
  final String label;
  final ValueChanged<Uint8List?> onSigned;
  final Color penColor;
  final double penStrokeWidth;

  const SignaturePadWidget({
    super.key,
    required this.label,
    required this.onSigned,
    this.penColor = Colors.black,
    this.penStrokeWidth = 2.0,
  });

  @override
  State<SignaturePadWidget> createState() => _SignaturePadWidgetState();
}

class _SignaturePadWidgetState extends State<SignaturePadWidget> {
  late final SignatureController _controller;
  bool _hasSigned = false;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: widget.penStrokeWidth,
      penColor: widget.penColor,
      exportBackgroundColor: Colors.transparent,
      exportPenColor: Colors.black,
    );
    _controller.addListener(() {
      if (_controller.isNotEmpty && !_hasSigned) {
        setState(() => _hasSigned = true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmSignature() async {
    if (_controller.isEmpty) return;
    final data = await _controller.toPngBytes();
    setState(() => _confirmed = true);
    widget.onSigned(data);
  }

  void _clearSignature() {
    _controller.clear();
    setState(() {
      _hasSigned = false;
      _confirmed = false;
    });
    widget.onSigned(null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary)),
            if (_confirmed) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: AppTheme.accentGreen, size: 14),
                    SizedBox(width: 4),
                    Text('Confirmada',
                        style: TextStyle(
                            color: AppTheme.accentGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
                color: _confirmed
                    ? AppTheme.accentGreen
                    : AppTheme.dividerColor),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: IgnorePointer(
              ignoring: _confirmed,
              child: Signature(
                controller: _controller,
                height: 120,
                backgroundColor: Colors.grey.shade50,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_confirmed)
              TextButton.icon(
                onPressed: _clearSignature,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Volver a firmar', style: TextStyle(fontSize: 12)),
              )
            else ...[
              TextButton.icon(
                onPressed: _hasSigned ? _clearSignature : null,
                icon: const Icon(Icons.clear_rounded, size: 16),
                label: const Text('Limpiar', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _hasSigned ? _confirmSignature : null,
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Confirmar firma',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
