# 7.5.3 — Prueba manual de cambios hasta Power BI

Estado: prueba ejecutada satisfactoriamente en desarrollo. Se verificaron
la inserción incremental, los valores de Power BI antes y después de actualizar,
y la restauración final en SQL Server y Power BI. Estos scripts corresponden al
entorno de desarrollo AdventureWorks2022 / AdventureWorks_EDW del proyecto.

## Qué demuestra

Una nueva línea del pedido 75123 debe pasar del origen a `dw.FactSales` mediante
el ETL incremental. Power BI, en modo Import, conserva su copia anterior hasta
que se actualiza. Comparamos esos momentos y finalmente restauramos los datos.

Un **checkpoint** es un estado guardado para comprobar y recuperar una prueba.
Aquí son tablas persistentes `audit.PBI753_*`, que sobreviven al cierre de la
conexión. No sustituyen un respaldo de base de datos.

El **watermark** registra hasta dónde procesó el ETL. La fecha de modificación
de la nueva línea se establece un segundo después del LOW de Detail para que
sea detectable, conservando la fecha comercial del pedido (2014-06-30).

## Condiciones

- Ejecutar los archivos completos, por separado y en orden, usando la conexión
  administrativa autorizada `Diego_Srz\dg_su`. No usar la conexión ordinaria de
  `mssql`, que en la comprobación anterior no tenía permisos sobre el origen.
- Mantener el entorno sin otras cargas ETL ni modificaciones de origen o
  dimensiones entre PREPARE y RESTORE. Se restaurarán watermarks y staging.
  El bloqueo del orquestador protege cada script, no las pausas entre ellos.
- Disponer de espacio para las copias de FactSales, Header y Detail.
- No editar ni eliminar manualmente las tablas `audit.PBI753_*`.

## Pasos

1. En Power BI, abrir la página Validation y quitar filtros y selecciones.
   Registrar los totales completos, sin abreviarlos a millones.
2. En el editor SQL con la conexión administrativa, abrir `01_Prepare.sql`
   y ejecutarlo completo. Debe mostrar `PREPARED`, el identificador generado,
   los totales previos y los esperados. La nueva línea está solo en el origen;
   el ETL todavía no se ha ejecutado. Guardar esta salida.
3. Ejecutar una sola vez `02_Load.sql`. Debe mostrar `LOADED` y una ejecución
   Succeeded con RowsRead=1, RowsInserted=1, RowsUpdated=0 y RowsRejected=0.
   Guardar el ExecutionID y los totales SQL.
4. Antes de actualizar Power BI, observar que sus valores siguen siendo los
   anteriores. Registrar esa evidencia.
5. Actualizar los datos en Power BI Desktop, esperar a que termine y comparar
   con la tabla siguiente. Guardar una captura con valores completos. No basta
   con volver a seleccionar un visual: debe actualizarse el modelo importado.
6. Ejecutar `03_Restore.sql` completo. Debe mostrar `RESTORED`, OpenTransactions=0
   y los totales originales. El script verifica la restauración antes de
   confirmar la transacción y eliminar las tablas de checkpoint.
7. Actualizar otra vez Power BI y comprobar que regresó a los totales originales.
   Guardar el reporte y registrar la evidencia de restauración.

No ejecutar los tres archivos automáticamente en un bucle: las pausas permiten
observar el estado de Power BI antes y después de actualizar.

## Valores esperados sin filtros

| Métrica | Antes y después de restaurar | Después de LOAD y actualización |
|---|---:|---:|
| Sales Order Lines | 121317 | 121318 |
| Sales Orders | 31465 | 31465 |
| Units Sold | 274914 | 274915 |
| Gross Sales | 110373889.3134 | 110373898.3034 |
| Discount Amount | 527507.8884 | 527507.8884 |
| Net Sales | 109846381.4250 | 109846390.4150 |

El número de pedidos no cambia porque la línea pertenece a un pedido existente.
Con el filtro de fecha de pedido 2014-06 y todos los territorios, Net Sales
debería pasar de 49005.8400 a 49014.8300. Restaurar los filtros al terminar.
El nuevo SalesOrderDetailID lo genera SQL Server; no debe fijarse manualmente.

## Aislamiento y restauración

Siguiendo el enfoque del test 010, PREPARE y RESTORE deshabilitan temporalmente
`Sales.iduSalesOrderDetail` dentro de una transacción corta y lo habilitan antes
del COMMIT. Así se evitan cambios secundarios en TransactionHistory,
Demographics y los totales de cabecera. Si ocurre un error capturado, se revierte
la transacción.

Por ello, mientras exista la línea de prueba, el SubTotal del pedido no incorpora
sus 8.99: es una prueba técnica aislada del flujo Detail, no una operación de venta
completa. No usar este procedimiento para insertar ventas reales.

El ETL actual no propaga eliminaciones físicas. RESTORE elimina explícitamente
la línea de prueba del origen y de FactSales, y restaura los dos watermarks y el
staging delta. Las filas originales deben coincidir con sus copias; si aparecen
cambios ajenos, el script se detiene en lugar de sobrescribirlos.

Se conservan los registros de auditoría ETL y el valor de identidad consumido.
La restauración de datos no significa borrar la historia de la ejecución.

## Si se interrumpe la prueba

- Si PREPARE terminó correctamente y se cancela la prueba antes de LOAD, ejecutar
  RESTORE; también admite el estado Prepared.
- Si LOAD falla, guardar el error y ejecutar RESTORE para intentar la limpieza
  protegida. No repetir LOAD ni ejecutar otro ETL: RESTORE solo admite como
  máximo un intento del orquestador posterior a PREPARE.
- Si se pierde la conexión durante LOAD, esperar a que termine o se cierre esa
  sesión antes de restaurar. Una conexión nueva puede consultar el checkpoint.
- Si RESTORE rechaza el estado, conservar sus tablas y compartir el mensaje.
  No desactivar sus comprobaciones. Una ejecución interrumpida puede dejar un
  registro de auditoría InProgress que debe revisarse por separado.
- Los errores de permisos o de estructura requieren revisar la conexión y el
  estado; el análisis sintáctico no verifica permisos ni objetos en SQL Server.

Consulta de diagnóstico sin modificar datos:

```sql
USE AdventureWorks_EDW;
SELECT * FROM audit.PBI753_Control;
SELECT ProcessName, Status, LowModifiedDate, LowBusinessKey,
       HighModifiedDate, HighBusinessKey, CurrentExecutionID
FROM audit.ETLWatermark
WHERE ProcessName IN
    (N'etl.LoadFactSalesIncremental.Header', N'etl.LoadFactSalesIncremental.Detail');
```

## Evidencia de ejecución

Prueba completada durante la sesión del 30 de septiembre de 2026
(hora de Lima).

| Elemento | Resultado observado |
|---|---|
| SalesOrderID | 75123 |
| SalesOrderDetailID generado | 121322 |
| ModifiedDate de la línea de prueba | 2014-06-30 00:00:01.000 |
| ExecutionID del orquestador | 115 |
| Status | Succeeded |
| RowsRead | 1 |
| RowsInserted | 1 |
| RowsUpdated | 0 |
| RowsRejected | 0 |
| ErrorMessage | NULL |
| Restauración | RESTORED |
| OpenTransactions después de restaurar | 0 |

Se confirmó la siguiente secuencia:

1. PREPARE insertó la nueva línea en el origen sin ejecutar el ETL.
2. LOAD incorporó exactamente una línea a FactSales.
3. Power BI conservó los valores anteriores antes de actualizar.
4. Después de Refresh, Power BI coincidió con los totales SQL de la columna
   «Después de LOAD y actualización» de la tabla anterior.
5. RESTORE eliminó la línea de prueba y verificó los datos originales.
6. Un último Refresh devolvió Power BI a los totales iniciales.

Los resultados SQL y las capturas de Power BI se revisaron durante la sesión
guiada. Las capturas todavía no están incorporadas al repositorio.

Los identificadores anteriores corresponden a esta ejecución; no deben usarse
como valores fijos para futuras pruebas.
