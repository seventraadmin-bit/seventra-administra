import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';
import 'package:riseg_one/core/permissions/plantillas_permiso.dart';

import 'permiso_labels.dart';

/// Un módulo del catálogo con sus códigos ya resueltos y contados —
/// estructura de presentación, nunca persistida.
class _ModuloVisible {
  _ModuloVisible({required this.modulo, required this.codigos});

  final ModuloPermiso modulo;
  final List<String> codigos;
}

/// Selector de permisos de RISEG ONE (Etapa "Usuarios, permisos y UX de
/// seguridad") — reemplaza la lista plana anterior, que crecía sin
/// estructura hasta volverse imposible de recorrer con el catálogo
/// completo.
///
/// Lo usan DOS pantallas, con el mismo comportamiento exacto: el alta de
/// usuario (paso "Permisos") y la edición de permisos de una cuenta ya
/// existente. Una sola implementación — el criterio de la etapa anterior
/// sobre fuentes de verdad únicas aplica igual a la UI.
///
/// Estructura:
///  - buscador que filtra por nombre de permiso Y de módulo;
///  - módulos agrupados por `grupoVisual` (Finanzas, Personal, …), cada
///    grupo colapsable y con su contador `n/total`;
///  - "Marcar todo"/"Quitar todo" por grupo;
///  - el scroll vive AQUÍ dentro, para que el diálogo que lo aloja pueda
///    tener un footer fijo con Cancelar/Guardar.
///
/// No decide nada sobre permisos: recibe la selección y notifica
/// cambios. La normalización (`normalizarPermisos`, que garantiza que
/// ninguna acción quede sin su `ver`) la aplica quien guarda.
class SelectorPermisos extends StatefulWidget {
  const SelectorPermisos({
    required this.seleccionados,
    required this.onCambio,
    this.alto = 420,
    super.key,
  });

  final Set<String> seleccionados;
  final ValueChanged<Set<String>> onCambio;

  /// Alto fijo del área desplazable — el diálogo controla su propio
  /// tamaño y el contenido nunca lo empuja (footer siempre visible).
  final double alto;

  @override
  State<SelectorPermisos> createState() => _SelectorPermisosState();
}

class _SelectorPermisosState extends State<SelectorPermisos> {
  final _buscarCtrl = TextEditingController();
  String _busqueda = '';

  /// Grupos colapsados. Arranca vacío: todo abierto la primera vez, que
  /// es lo útil cuando el catálogo se explora por primera vez.
  final _colapsados = <String>{};

  /// Última plantilla aplicada — solo para el aviso de "se precargaron
  /// N permisos, revísalos". NO es el estado de la cuenta: en cuanto se
  /// toca una casilla suelta deja de reflejar la selección, y por eso se
  /// limpia en `_alternar`. Nada de esto se guarda.
  String? _plantillaAplicada;

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  /// Clave de agrupación: `grupoVisual` cuando existe; si no, el propio
  /// módulo es su grupo (Inventario, Vehículos, … no necesitan uno).
  String _grupoDe(ModuloPermiso m) => m.grupoVisual ?? m.codigo;

  bool _coincide(AppLocalizations l10n, ModuloPermiso modulo, String codigo) {
    if (_busqueda.isEmpty) return true;
    final termino = _busqueda.toLowerCase();
    return permisoLabel(l10n, codigo).toLowerCase().contains(termino) ||
        moduloLabel(l10n, modulo.codigo).toLowerCase().contains(termino) ||
        codigo.toLowerCase().contains(termino);
  }

  void _alternar(String codigo, bool marcado) {
    final nuevo = Set<String>.from(widget.seleccionados);
    if (marcado) {
      nuevo.add(codigo);
    } else {
      nuevo.remove(codigo);
    }
    setState(() => _plantillaAplicada = null);
    widget.onCambio(nuevo);
  }

  void _aplicarAGrupo(List<String> codigos, bool marcar) {
    final nuevo = Set<String>.from(widget.seleccionados);
    if (marcar) {
      nuevo.addAll(codigos);
    } else {
      nuevo.removeAll(codigos);
    }
    setState(() => _plantillaAplicada = null);
    widget.onCambio(nuevo);
  }

  /// Aplicar una plantilla REEMPLAZA la selección, no la suma. Sumar
  /// dejaría un conjunto que no es ni lo anterior ni la plantilla, y que
  /// nadie podría explicar después; reemplazar hace que "apliqué
  /// Tesorería" signifique exactamente eso, y lo que sobre o falte se
  /// ajusta a mano enseguida (para eso el catálogo sigue abierto).
  void _aplicarPlantilla(String? codigoPlantilla) {
    if (codigoPlantilla == null) {
      setState(() => _plantillaAplicada = null);
      widget.onCambio(<String>{});
      return;
    }
    setState(() => _plantillaAplicada = codigoPlantilla);
    widget.onCambio(codigosDePlantilla(codigoPlantilla));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    // Agrupa el catálogo aplicando el filtro de búsqueda; un módulo sin
    // ningún permiso coincidente desaparece, y un grupo sin módulos
    // visibles también.
    final grupos = <String, List<_ModuloVisible>>{};
    for (final modulo in modulosPermiso) {
      final codigos = modulo.todosLosCodigos.where((c) => _coincide(l10n, modulo, c)).toList()..sort();
      if (codigos.isEmpty) continue;
      (grupos[_grupoDe(modulo)] ??= []).add(_ModuloVisible(modulo: modulo, codigos: codigos));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Plantillas (punto 12): un punto de partida, nunca un rol. No
        // se persiste cuál se usó — lo que se guarda son los códigos
        // individuales resultantes, exactamente como si se hubieran
        // marcado a mano. Ver `plantillas_permiso.dart`.
        RisegSelect<String?>(
          key: const Key('selector_permisos_plantilla'),
          label: l10n.permisosPlantillaLabel,
          helperText: l10n.permisosPlantillaAyuda,
          value: _plantillaAplicada,
          items: [
            RisegSelectItem(value: null, label: l10n.permisosPlantillaNinguna),
            for (final plantilla in plantillasPermiso)
              RisegSelectItem(value: plantilla.codigo, label: plantillaPermisoLabel(l10n, plantilla.codigo)),
          ],
          onChanged: _aplicarPlantilla,
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          key: const Key('selector_permisos_buscar'),
          label: l10n.permisosBuscarLabel,
          controller: _buscarCtrl,
          onChanged: (valor) => setState(() => _busqueda = valor.trim()),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _plantillaAplicada != null
              ? l10n.permisosPlantillaAplicada(widget.seleccionados.length)
              : l10n.permisosSeleccionadosTotal(widget.seleccionados.length),
          style: AppTypography.caption.copyWith(
            color: _plantillaAplicada != null ? colors.info : colors.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: widget.alto,
          child: grupos.isEmpty
              ? Center(
                  child: Text(
                    l10n.permisosBusquedaSinResultados,
                    style: AppTypography.body.copyWith(color: colors.textMuted),
                  ),
                )
              : ListView(
                  primary: false,
                  children: [
                    for (final entrada in grupos.entries)
                      _GrupoPermisos(
                        // Al buscar, todo queda expandido: colapsar un
                        // resultado de búsqueda lo escondería justo
                        // cuando se está buscando.
                        colapsado: _busqueda.isEmpty && _colapsados.contains(entrada.key),
                        titulo: grupoLabel(l10n, entrada.key),
                        modulos: entrada.value,
                        seleccionados: widget.seleccionados,
                        onAlternarColapso: () => setState(() {
                          if (!_colapsados.remove(entrada.key)) _colapsados.add(entrada.key);
                        }),
                        onAlternarPermiso: _alternar,
                        onAplicarAGrupo: _aplicarAGrupo,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _GrupoPermisos extends StatelessWidget {
  const _GrupoPermisos({
    required this.titulo,
    required this.modulos,
    required this.seleccionados,
    required this.colapsado,
    required this.onAlternarColapso,
    required this.onAlternarPermiso,
    required this.onAplicarAGrupo,
  });

  final String titulo;
  final List<_ModuloVisible> modulos;
  final Set<String> seleccionados;
  final bool colapsado;
  final VoidCallback onAlternarColapso;
  final void Function(String codigo, bool marcado) onAlternarPermiso;
  final void Function(List<String> codigos, bool marcar) onAplicarAGrupo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final codigosDelGrupo = [for (final m in modulos) ...m.codigos];
    final marcadosDelGrupo = codigosDelGrupo.where(seleccionados.contains).length;
    final todosMarcados = marcadosDelGrupo == codigosDelGrupo.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onAlternarColapso,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs, horizontal: AppSpacing.xxs),
              child: Row(
                children: [
                  Icon(colapsado ? Icons.chevron_right : Icons.expand_more, size: 20, color: colors.textMuted),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(
                    child: Text(titulo, style: AppTypography.bodyStrong, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    l10n.permisosGrupoConteo(marcadosDelGrupo, codigosDelGrupo.length),
                    style: AppTypography.caption.copyWith(
                      color: marcadosDelGrupo > 0 ? colors.info : colors.textMuted,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  RisegButton(
                    label: todosMarcados ? l10n.permisosQuitarTodoGrupo : l10n.permisosMarcarTodoGrupo,
                    variant: RisegButtonVariant.ghost,
                    size: RisegButtonSize.compact,
                    onPressed: () => onAplicarAGrupo(codigosDelGrupo, !todosMarcados),
                  ),
                ],
              ),
            ),
          ),
          if (!colapsado)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final visible in modulos)
                    _ModuloPermisos(
                      visible: visible,
                      seleccionados: seleccionados,
                      onAlternarPermiso: onAlternarPermiso,
                      // Un grupo con un solo módulo del mismo nombre no
                      // repite el encabezado: sería ruido, no jerarquía.
                      mostrarEncabezado: modulos.length > 1 || visible.modulo.grupoVisual != null,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ModuloPermisos extends StatelessWidget {
  const _ModuloPermisos({
    required this.visible,
    required this.seleccionados,
    required this.onAlternarPermiso,
    required this.mostrarEncabezado,
  });

  final _ModuloVisible visible;
  final Set<String> seleccionados;
  final void Function(String codigo, bool marcado) onAlternarPermiso;
  final bool mostrarEncabezado;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final marcados = visible.codigos.where(seleccionados.contains).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mostrarEncabezado)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xxs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    moduloLabel(l10n, visible.modulo.codigo),
                    style: AppTypography.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  l10n.permisosGrupoConteo(marcados, visible.codigos.length),
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
        for (final codigo in visible.codigos)
          CheckboxListTile(
            key: Key('permiso_$codigo'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            visualDensity: VisualDensity.compact,
            title: Text(permisoLabel(l10n, codigo), style: AppTypography.body),
            value: seleccionados.contains(codigo),
            onChanged: (valor) => onAlternarPermiso(codigo, valor ?? false),
          ),
      ],
    );
  }
}
