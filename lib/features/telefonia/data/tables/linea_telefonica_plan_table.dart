import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import 'linea_telefonica_table.dart';

/// Plan/costo de una línea telefónica (Etapa 9A) — variante
/// simplificada del patrón de vigencia ya usado en
/// `AsignacionServicioSueldoVigencia`/`ConfiguracionCobroVigencia`:
/// **sin** programación de cambios futuros por adelantado (nunca hay
/// más de una fila abierta a la vez, por construcción — siempre se
/// cierra la vigente antes de abrir una nueva). "Cambiar plan" = cerrar
/// el registro abierto (`fechaFinVigencia`) + insertar uno nuevo, una
/// transacción — el plan vigente es siempre `fechaFinVigencia IS NULL`,
/// una consulta trivial, sin clasificar por rango de fechas.
///
/// `fechaFinVigencia` (interna — cuándo esta fila dejó de ser la
/// vigente porque se registró una nueva) es un campo **distinto e
/// independiente** de `fechaFinPermanencia` (contractual — el operador
/// impone un plazo mínimo de permanencia; usado para las alertas de la
/// Etapa 9C, nunca para decidir cuál fila es la vigente).
///
/// Sin gigabytes/minutos/SMS ni detalle comercial — fuera de alcance
/// confirmado por Marlon.
class LineaTelefonicaPlan extends Table with AuditColumns {
  TextColumn get lineaTelefonicaId => text().references(LineaTelefonica, #id, onDelete: KeyAction.restrict)();

  TextColumn get nombre => text()();

  IntColumn get costoMensual => integer()();

  DateTimeColumn get fechaInicioVigencia => dateTime()();

  DateTimeColumn get fechaFinVigencia => dateTime().nullable()();

  DateTimeColumn get fechaFinPermanencia => dateTime().nullable()();

  TextColumn get observaciones => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (costo_mensual >= 0)',
        'CHECK (fecha_fin_vigencia IS NULL OR fecha_fin_vigencia >= fecha_inicio_vigencia)',
        'CHECK (fecha_fin_permanencia IS NULL OR fecha_fin_permanencia >= fecha_inicio_vigencia)',
      ];
}
