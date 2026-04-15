import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signature/signature.dart';
import '../config/theme.dart';

class SignaturePadWidget extends StatefulWidget {
  final String label;
  final ValueChanged<Uint8List?> onSigned;
  final Color penColor;
  final double penStrokeWidth;
  /// If true, tapping opens a fullscreen dialog for signing (ideal for mobile clients)
  final bool fullScreen;

  const SignaturePadWidget({
    super.key,
    required this.label,
    required this.onSigned,
    this.penColor = Colors.black,
    this.penStrokeWidth = 2.0,
    this.fullScreen = false,
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

  Future<void> _openFullScreen() async {
    final result = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenSignature(
          label: widget.label,
          penColor: widget.penColor,
          penStrokeWidth: widget.penStrokeWidth,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _confirmed = true;
        _hasSigned = true;
      });
      widget.onSigned(result);
    }
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

        // Full screen mode: show tap-to-open area
        if (widget.fullScreen && !_confirmed)
          GestureDetector(
            onTap: _openFullScreen,
            child: Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.open_in_full_rounded, color: AppTheme.accentCyan, size: 32),
                  const SizedBox(height: 8),
                  Text('Toque para firmar en pantalla completa',
                      style: TextStyle(color: AppTheme.accentCyan, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Area mas grande para firmar comodamente',
                      style: TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
          )
        // Confirmed: show the signature image
        else if (_confirmed)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.accentGreen),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: IgnorePointer(
                ignoring: true,
                child: Signature(
                  controller: _controller,
                  height: 120,
                  backgroundColor: Colors.grey.shade50,
                ),
              ),
            ),
          )
        // Inline mode (desktop or technician)
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.dividerColor),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Signature(
                controller: _controller,
                height: 120,
                backgroundColor: Colors.grey.shade50,
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
            else if (!widget.fullScreen) ...[
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

/// Fullscreen signature page - rotates to landscape for maximum area
class _FullScreenSignature extends StatefulWidget {
  final String label;
  final Color penColor;
  final double penStrokeWidth;

  const _FullScreenSignature({
    required this.label,
    required this.penColor,
    required this.penStrokeWidth,
  });

  @override
  State<_FullScreenSignature> createState() => _FullScreenSignatureState();
}

class _FullScreenSignatureState extends State<_FullScreenSignature> {
  late final SignatureController _controller;
  bool _hasSigned = false;

  @override
  void initState() {
    super.initState();
    // Force landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _controller = SignatureController(
      penStrokeWidth: widget.penStrokeWidth + 1,
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
    // Restore all orientations
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_controller.isEmpty) return;
    final data = await _controller.toPngBytes();
    if (mounted) Navigator.pop(context, data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey.shade100,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.black54),
                  ),
                  const SizedBox(width: 8),
                  Text(widget.label,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      _controller.clear();
                      setState(() => _hasSigned = false);
                    },
                    icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.black54),
                    label: const Text('Limpiar', style: TextStyle(color: Colors.black54)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _hasSigned ? _confirm : null,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Confirmar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
            // Signature area - fills all remaining space
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Signature(
                        controller: _controller,
                        backgroundColor: Colors.grey.shade50,
                      ),
                      if (!_hasSigned)
                        Center(
                          child: Text('Firme aqui',
                              style: TextStyle(
                                  fontSize: 24,
                                  color: Colors.grey.shade300,
                                  fontWeight: FontWeight.w300)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
