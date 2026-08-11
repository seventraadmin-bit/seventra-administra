import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/permissions/modulos_permiso.dart';

/// Nombre humano de un módulo del catálogo de permisos — nunca se
/// muestra el código técnico (`'personal'`, `'nomina'`, ...) al
/// usuario administrativo. Reutiliza las etiquetas ya existentes del
/// sidebar donde el módulo coincide 1:1 con un destino del Shell;
/// `'nomina'` y `'usuarios'` son las únicas excepciones (Nómina vive
/// como pestaña dentro de Personal, Usuarios dentro de Configuración —
/// ninguno de los dos es una ruta de primer nivel propia).
String moduloPermisoLabel(AppLocalizations l10n, String codigo) {
  return switch (codigo) {
    'personal' => l10n.modulePersonal,
    'nomina' => l10n.permisoModuloNomina,
    'finanzas' => l10n.moduleFinanzas,
    'compras' => l10n.moduleCompras,
    'inventario' => l10n.moduleInventario,
    'vehiculos' => l10n.moduleVehiculos,
    'telefonia' => l10n.moduleTelefonia,
    'organizacion' => l10n.moduleOrganizacion,
    'comercial' => l10n.moduleComercial,
    'reportes' => l10n.moduleReportes,
    'usuarios' => l10n.usuariosListadoTitulo,
    _ => codigo,
  };
}

String accionBaseLabel(AppLocalizations l10n, AccionBase accion) {
  return switch (accion) {
    AccionBase.ver => l10n.permisoAccionVer,
    AccionBase.crear => l10n.permisoAccionCrear,
    AccionBase.modificar => l10n.permisoAccionModificar,
    AccionBase.archivar => l10n.permisoAccionCancelarArchivar,
    AccionBase.eliminar => l10n.permisoAccionEliminar,
  };
}

/// Etiqueta humana de un código especial (`'nomina.cerrar'`, ...) —
/// cae al propio código solo si aparece uno nuevo en el catálogo sin
/// registrar aquí todavía (nunca debería pasar en producción, pero es
/// preferible a un `throw` en una pantalla administrativa).
String permisoEspecialLabel(AppLocalizations l10n, String codigo) {
  return switch (codigo) {
    'personal.cambiarSueldo' => l10n.permisoPersonalCambiarSueldo,
    'nomina.cerrar' => l10n.permisoNominaCerrar,
    'nomina.pagar' => l10n.permisoNominaPagar,
    'usuarios.administrar' => l10n.permisoUsuariosAdministrar,
    _ => codigo,
  };
}
