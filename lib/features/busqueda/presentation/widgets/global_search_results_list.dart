import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/usecases/resultado_busqueda_entidad.dart';
import '../busqueda_controller.dart';

/// Lista de resultados agrupados de Búsqueda global (Etapa 14A) —
/// compartida por el overlay de la barra superior y el diálogo de
/// modo compacto, para no duplicar el renderizado. Un grupo se omite
/// por completo si su campo llegó en `null` (sin autorización) o
/// vacío (autorizado, sin coincidencias) — nunca un encabezado de
/// grupo sin filas.
class GlobalSearchResultsList extends ConsumerWidget {
  const GlobalSearchResultsList({required this.onSelect, super.key});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(busquedaControllerProvider);

    if (state.cargando) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final resultados = state.resultados;
    if (resultados == null) return const SizedBox.shrink();

    if (resultados.sinResultados) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(l10n.busquedaSinResultados(state.texto.trim())),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grupo(l10n.busquedaGrupoPersonal, Icons.people_outline, resultados.empleados),
            _grupo(l10n.busquedaGrupoClientes, Icons.handshake_outlined, resultados.clientes),
            _grupo(l10n.busquedaGrupoServicios, Icons.assignment_outlined, resultados.servicios),
            _grupo(l10n.busquedaGrupoArticulos, Icons.inventory_2_outlined, resultados.articulos),
            _grupo(l10n.busquedaGrupoCompras, Icons.shopping_cart_outlined, resultados.compras),
            _grupo(l10n.busquedaGrupoVehiculos, Icons.directions_car_outlined, resultados.vehiculos),
            _grupo(l10n.busquedaGrupoLineasTelefonicas, Icons.phone_iphone_outlined, resultados.lineasTelefonicas),
            _grupo(l10n.busquedaGrupoUsuarios, Icons.badge_outlined, resultados.usuarios),
          ],
        ),
      ),
    );
  }

  Widget _grupo(String titulo, IconData icono, List<ResultadoBusquedaEntidad>? items) {
    if (items == null || items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxs),
          child: Text(titulo.toUpperCase(), style: AppTypography.label),
        ),
        for (final item in items)
          InkWell(
            onTap: () => onSelect(item.ruta),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(icono, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.titulo, overflow: TextOverflow.ellipsis),
                        Text(item.subtitulo, style: AppTypography.caption, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
