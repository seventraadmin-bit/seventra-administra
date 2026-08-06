import 'package:drift/drift.dart';

import 'configuracion_cobro_vigencia_table.dart';

/// Un correo de envío de la Configuración de cobro vigente de un
/// Servicio (Etapa 4H.1) — tabla hija para permitir crecer sin rediseñar
/// el modelo (Resolución E), en vez de un texto delimitado.
///
/// Sin `AuditColumns`: igual que `HorarioDetalle`, esta fila no tiene
/// ciclo de vida propio — al editar los correos de una vigencia, se
/// borran todas las filas existentes y se insertan las nuevas dentro de
/// la misma transacción, nunca un archivado fila por fila.
class ConfiguracionCobroCorreo extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get configuracionCobroVigenciaId =>
      text().references(ConfiguracionCobroVigencia, #id, onDelete: KeyAction.cascade)();

  TextColumn get correo => text()();
}
