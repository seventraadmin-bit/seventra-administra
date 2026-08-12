import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_input.dart';

import 'empresa_expediente_controller.dart';
import 'empresa_expediente_form_controllers.dart';
import 'empresa_expediente_state.dart';
import 'widgets/datos_generales_section.dart';
import 'widgets/direccion_fiscal_section.dart';
import 'widgets/logotipo_section.dart';
import 'widgets/medios_contacto_section.dart';

/// Pantalla de expediente de Empresa — consulta ↔ edición con
/// guardado transaccional. `/organizacion` apunta directo aquí mientras
/// no existan otras secciones funcionales de Organización.
class EmpresaExpedienteScreen extends ConsumerStatefulWidget {
  const EmpresaExpedienteScreen({super.key});

  @override
  ConsumerState<EmpresaExpedienteScreen> createState() => _EmpresaExpedienteScreenState();
}

class _EmpresaExpedienteScreenState extends ConsumerState<EmpresaExpedienteScreen> {
  final _datosGenerales = DatosGeneralesControllers();
  final _direccionFiscal = DireccionFiscalControllers();
  final _medioContacto = MedioContactoControllers();

  @override
  void dispose() {
    _datosGenerales.dispose();
    _direccionFiscal.dispose();
    _medioContacto.dispose();
    super.dispose();
  }

  void _poblarControladores(EmpresaExpedienteData datos) {
    _datosGenerales.poblar(datos.empresa);
    _direccionFiscal.poblar(datos.direccionFiscal);
    _medioContacto.poblar(datos.medioContacto);
  }

  void _iniciarEdicion(EmpresaExpedienteData datos) {
    _poblarControladores(datos);
    ref.read(empresaExpedienteControllerProvider.notifier).entrarModoEdicion();
  }

  Future<void> _cancelar(bool tieneCambios) async {
    final notifier = ref.read(empresaExpedienteControllerProvider.notifier);
    if (!tieneCambios) {
      notifier.cancelarEdicion();
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.empresaCancelarConfirmacionTitulo,
      message: l10n.empresaCancelarConfirmacionMensaje,
      confirmLabel: l10n.empresaCancelarConfirmacionConfirmar,
      cancelLabel: l10n.empresaCancelarConfirmacionCancelar,
      destructive: true,
    );
    if (confirmado == true) notifier.cancelarEdicion();
  }

  Future<void> _guardar() async {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(empresaExpedienteControllerProvider.notifier);
    final input = EmpresaExpedienteInput(
      datosGenerales: _datosGenerales.capturar(),
      direccionFiscal: _direccionFiscal.capturar(),
      medioContacto: _medioContacto.capturar(),
    );

    final exito = await notifier.guardar(input);
    if (!mounted) return;

    final estadoActual = ref.read(empresaExpedienteControllerProvider);
    if (exito) {
      // El RFC (y cualquier otra normalización) vuelve poblado desde el
      // estado ya persistido, para que una siguiente edición parta de los
      // valores reales guardados, no de lo que el usuario tecleó.
      if (estadoActual.datos != null) _poblarControladores(estadoActual.datos!);
      RisegFeedback.showSuccess(context, l10n.empresaGuardadoExito);
    } else if (estadoActual.errorGuardadoGeneral) {
      RisegFeedback.showError(context, l10n.empresaGuardadoErrorGeneral);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: const Key('empresa_expediente_screen'), child: _buildContent(context));
  }

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(empresaExpedienteControllerProvider);
    final notifier = ref.read(empresaExpedienteControllerProvider.notifier);

    if (state.datos == null && state.errorCarga != null) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.empresaExpedienteCargaErrorTitulo,
        message: l10n.empresaExpedienteCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('empresa_expediente_boton_reintentar'),
          label: l10n.empresaExpedienteBotonReintentar,
          onPressed: notifier.reintentarCarga,
        ),
      );
    }

    if (state.datos == null) {
      return _EmpresaExpedienteSkeleton(titulo: l10n.empresaExpedienteTitulo);
    }

    final datos = state.datos!;
    final esEdicion = state.modo == EmpresaExpedienteModo.edicion;
    final habilitado = !state.guardando;

    final logotipo = const RisegCard(child: LogotipoSection());
    final mediosContacto = RisegCard(
      child: MediosContactoSection(
        modo: state.modo,
        contacto: datos.medioContacto,
        controllers: _medioContacto,
        habilitado: habilitado,
        errores: state.erroresGuardado,
        onCampoModificado: notifier.marcarCambiosSinGuardar,
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.wide),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSectionHeader(
                title: l10n.empresaExpedienteTitulo,
                primaryAction: esEdicion
                    ? RisegButton(
                        key: const Key('empresa_expediente_boton_guardar'),
                        label: l10n.empresaExpedienteBotonGuardar,
                        loading: state.guardando,
                        onPressed: _guardar,
                      )
                    : RisegButton(
                        key: const Key('empresa_expediente_boton_editar'),
                        label: l10n.empresaExpedienteBotonEditar,
                        onPressed: () => _iniciarEdicion(datos),
                      ),
                secondaryAction: esEdicion
                    ? RisegButton(
                        key: const Key('empresa_expediente_boton_cancelar'),
                        label: l10n.empresaExpedienteBotonCancelar,
                        variant: RisegButtonVariant.ghost,
                        onPressed: state.guardando ? null : () => _cancelar(state.tieneCambiosSinGuardar),
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: DatosGeneralesSection(
                  modo: state.modo,
                  empresa: datos.empresa,
                  controllers: _datosGenerales,
                  habilitado: habilitado,
                  errores: state.erroresGuardado,
                  onCampoModificado: notifier.marcarCambiosSinGuardar,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              // Logotipo es una tarjeta pequeña y de solo lectura — se
              // coloca junto a Medios de contacto (también breve) en
              // vez de dejarla sola ocupando el ancho completo con
              // espacio vacío a la derecha.
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < AppBreakpoints.medium) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [logotipo, const SizedBox(height: AppSpacing.xl), mediosContacto],
                    );
                  }
                  // Sin `IntrinsicHeight`: `RisegFieldGrid` (dentro de
                  // `mediosContacto`) usa su propio `LayoutBuilder`, y
                  // Flutter no permite calcular dimensiones intrínsecas
                  // a través de un `LayoutBuilder` — produce un error
                  // real de layout, no solo una advertencia. Sin altura
                  // forzada, cada tarjeta simplemente toma su propia
                  // altura natural.
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: logotipo),
                      const SizedBox(width: AppSpacing.xl),
                      Expanded(flex: 3, child: mediosContacto),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: DireccionFiscalSection(
                  modo: state.modo,
                  direccion: datos.direccionFiscal,
                  controllers: _direccionFiscal,
                  habilitado: habilitado,
                  errores: state.erroresGuardado,
                  onCampoModificado: notifier.marcarCambiosSinGuardar,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estado de carga inicial — una estructura coherente con el expediente
/// real (título + 4 tarjetas con líneas de contenido), no un único
/// spinner centrado.
class _EmpresaExpedienteSkeleton extends StatelessWidget {
  const _EmpresaExpedienteSkeleton({required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget barra(double ancho) => Container(
          width: ancho,
          height: 14,
          margin: const EdgeInsets.only(top: AppSpacing.sm),
          decoration: BoxDecoration(color: colors.surfaceSunken, borderRadius: AppRadius.smRadius),
        );

    Widget tarjeta(List<double> anchos) => RisegCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 140,
                height: 16,
                decoration: BoxDecoration(color: colors.surfaceSunken, borderRadius: AppRadius.smRadius),
              ),
              for (final ancho in anchos) barra(ancho),
            ],
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.xl),
              tarjeta(const [220, 260, 180, 200]),
              const SizedBox(height: AppSpacing.xl),
              tarjeta(const [160]),
              const SizedBox(height: AppSpacing.xl),
              tarjeta(const [220, 180, 200, 160]),
              const SizedBox(height: AppSpacing.xl),
              tarjeta(const [200, 240]),
            ],
          ),
        ),
      ),
    );
  }
}
