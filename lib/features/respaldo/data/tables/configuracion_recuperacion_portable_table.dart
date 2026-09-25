import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';

/// Configuración de recuperación portable (Etapa 4D, schemaVersion 93).
///
/// **Nada de lo que hay aquí es secreto.** Es literalmente el mismo
/// bloque que viaja dentro de cada `.risegbkp`: la clave maestra del
/// conjunto (MWK) envuelta por la frase y envuelta por la clave de
/// recuperación. Quien lea esta tabla obtiene lo mismo que quien robe
/// un USB con un respaldo — y sigue necesitando la frase o la clave de
/// recuperación para abrir cualquiera de las dos envolturas.
///
/// Lo que **nunca** se guarda, ni cifrado ni derivado: la frase, la
/// clave de recuperación, sus KEK, la MWK en claro, ninguna DEK y la
/// clave AES de la aplicación.
///
/// **Vive en la base a propósito**, no en un archivo aparte: así viaja
/// dentro del respaldo y PC B puede continuar el conjunto de PC A tras
/// restaurar. Tiene una consecuencia que la pantalla debe explicar —
/// restaurar un respaldo antiguo también devuelve la configuración que
/// estaba vigente ese día.
@DataClassName('ConfiguracionRecuperacionPortableData')
class ConfiguracionRecuperacionPortable extends Table with AuditColumns {
  /// Identifica la familia criptográfica de respaldos: 16 bytes de
  /// CSPRNG en hexadecimal.
  ///
  /// **No** es `AppMetadata.installationId` ni deriva de él. Aquel
  /// identifica técnicamente una instalación; éste identifica un
  /// conjunto de respaldos que comparten MWK y configuración. Tras
  /// restaurar, PC B adopta el `backupSetId` de PC A sin que eso
  /// obligue a afirmar que es la misma instalación.
  TextColumn get backupSetId => text().unique()();

  /// Versión del formato de este bloque, por si las envolturas cambian
  /// de forma en el futuro sin invalidar lo ya escrito.
  IntColumn get formatoVersion => integer().withDefault(const Constant(1))();

  /// La envoltura de la MWK bajo la frase, serializada como el JSON que
  /// se copia tal cual a R3 del contenedor.
  TextColumn get envolturaFrase => text()();

  /// La envoltura de la MWK bajo la clave de recuperación.
  TextColumn get envolturaClaveRecuperacion => text()();

  /// Cuándo se generó la clave de recuperación vigente. Permite decir
  /// "la que imprimiste el 3 de marzo" sin guardar nada de ella.
  DateTimeColumn get claveRecuperacionGeneradaEn => dateTime()();
}
