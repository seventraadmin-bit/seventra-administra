import 'package:flutter/material.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

/// Botón compacto de exportación (Etapa 12D) — reutilizado por las 4
/// pestañas de Reportes (nunca uno distinto por pantalla). Administra
/// su propio estado de carga para deshabilitarse mientras exporta y
/// evitar doble clic, sin que cada pantalla tenga que repetir esa
/// lógica.
class ReporteExportButton extends StatefulWidget {
  const ReporteExportButton({required this.label, required this.onExportar, this.icon, super.key});

  final String label;
  final IconData? icon;
  final Future<void> Function() onExportar;

  @override
  State<ReporteExportButton> createState() => _ReporteExportButtonState();
}

class _ReporteExportButtonState extends State<ReporteExportButton> {
  var _exportando = false;

  Future<void> _onPressed() async {
    setState(() => _exportando = true);
    try {
      await widget.onExportar();
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RisegButton(
      label: widget.label,
      icon: widget.icon,
      variant: RisegButtonVariant.ghost,
      size: RisegButtonSize.compact,
      loading: _exportando,
      onPressed: _exportando ? null : _onPressed,
    );
  }
}
