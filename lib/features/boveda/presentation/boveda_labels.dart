import 'package:flutter_gen/gen_l10n/app_localizations.dart';

String tipoAccesoBovedaLabel(AppLocalizations l10n, String tipo) {
  return switch (tipo) {
    'pcr' => l10n.tipoAccesoBovedaPcr,
    'correo' => l10n.tipoAccesoBovedaCorreo,
    'portal' => l10n.tipoAccesoBovedaPortal,
    'proveedor' => l10n.tipoAccesoBovedaProveedor,
    'software' => l10n.tipoAccesoBovedaSoftware,
    'pagina' => l10n.tipoAccesoBovedaPagina,
    'otro' => l10n.tipoAccesoBovedaOtro,
    _ => tipo,
  };
}

String eventoCredencialBovedaLabel(AppLocalizations l10n, String tipoEvento) {
  return switch (tipoEvento) {
    'creada' => l10n.bovedaEventoCreada,
    'editada' => l10n.bovedaEventoEditada,
    'secretoCambiado' => l10n.bovedaEventoSecretoCambiado,
    'secretoRevelado' => l10n.bovedaEventoSecretoRevelado,
    'secretoCopiado' => l10n.bovedaEventoSecretoCopiado,
    'dadaDeBaja' => l10n.bovedaEventoDadaDeBaja,
    'reactivada' => l10n.bovedaEventoReactivada,
    _ => tipoEvento,
  };
}
