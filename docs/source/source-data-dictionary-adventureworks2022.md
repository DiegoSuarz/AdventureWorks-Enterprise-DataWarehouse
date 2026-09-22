# Diccionario de datos fuente — AdventureWorks2022

## 1. Propósito

Este documento describe las tablas de `AdventureWorks2022` utilizadas como fuente para el proyecto `AdventureWorks_EDW`. Su objetivo es conservar el contexto funcional y técnico de los datos antes de transformarlos mediante ETL hacia las capas `stg` y `dw`.

La documentación sirve para:

- entender qué representa cada tabla dentro del sistema OLTP;
- identificar claves, relaciones y granularidad;
- decidir qué columnas pasan al modelo dimensional;
- distinguir atributos analíticos, técnicos, operativos y de auditoría;
- justificar las transformaciones aplicadas durante la carga.

> Los tipos indicados corresponden al esquema estándar de AdventureWorks2022 en SQL Server. Deben validarse contra la instancia concreta antes de automatizar el catálogo.

## 2. Contexto de arquitectura

```text
AdventureWorks2022 (OLTP)
        ↓ extracción
stg (datos preparados y trazables)
        ↓ transformación dimensional
dw (dimensiones y hechos)
        ↓ consumo
Power BI / consultas analíticas
```

El modelo dimensional se construye con esquema estrella. Las tablas de ventas se comportan como fuentes de hechos y las tablas descriptivas como fuentes de dimensiones.

## 3. Resumen de tablas

| Tabla fuente | Función OLTP | Granularidad | Destino previsto |
|---|---|---|---|
| `Production.Product` | Catálogo de productos | Un registro por producto | `dw.DimProduct` |
| `Person.Person` | Identidad y nombre de personas | Una persona por registro | `dw.DimCustomer` / dimensiones auxiliares |
| `Sales.Customer` | Cliente comercial | Un cliente por registro | `dw.DimCustomer` |
| `Sales.SalesTerritory` | Territorio comercial | Un territorio por registro | `dw.DimTerritory` |
| `Sales.SalesOrderHeader` | Cabecera de pedido | Un pedido por registro | `dw.FactSales` |
| `Sales.SalesOrderDetail` | Líneas de pedido | Una línea de producto por pedido | `dw.FactSales` |

## 4. Clasificación de columnas

| Clasificación | Uso en el Data Warehouse |
|---|---|
| Clave de negocio | Identifica el registro en el sistema fuente; se conserva para trazabilidad y cargas incrementales. |
| Atributo analítico | Se utiliza para filtrar, agrupar, segmentar o describir datos. |
| Medida | Valor numérico que puede agregarse o analizarse en una tabla de hechos. |
| Relación | Identificador que conecta la tabla con otra entidad fuente. |
| Técnico/auditoría | Ayuda a detectar cambios, reconstruir cargas o rastrear el origen. |
| Operativo | Es importante para el proceso OLTP, pero no necesariamente aporta valor al primer modelo analítico. |
| No recomendado inicialmente | Se excluye del modelo inicial por ser semiestructurado, redundante, de baja utilidad analítica o por requerir una decisión posterior. |

---

## 5. `Production.Product`

### Propósito y contexto

Representa el catálogo maestro de productos vendidos o fabricados. Es la fuente principal de `dw.DimProduct`, dimensión que implementa historial mediante SCD Tipo 2. Su granularidad es un registro por producto.

### Campos

| Campo | Tipo | Clave | Uso DW | Descripción y decisión |
|---|---|---|---|---|
| `ProductID` | `int` | PK / negocio | Incluir | Identificador estable del producto; se conserva como clave de negocio. |
| `Name` | `nvarchar(50)` | — | Incluir | Nombre comercial; atributo descriptivo principal. |
| `ProductNumber` | `nvarchar(25)` | — | Incluir | Código visible del producto. |
| `MakeFlag` | `bit` | — | Incluir | Indica si se fabrica internamente. |
| `FinishedGoodsFlag` | `bit` | — | Incluir | Indica si puede venderse como producto terminado. |
| `Color` | `nvarchar(15)` | — | Incluir | Atributo útil para segmentación. |
| `SafetyStockLevel` | `smallint` | — | Opcional | Nivel de stock de seguridad; útil para inventario, no esencial para ventas. |
| `ReorderPoint` | `smallint` | — | Opcional | Punto de reposición; pertenece principalmente a análisis de inventario. |
| `StandardCost` | `money` | — | Incluir | Costo estándar; puede apoyar margen y rentabilidad. |
| `ListPrice` | `money` | — | Incluir | Precio de lista vigente en la fuente. |
| `Size` | `nvarchar(5)` | — | Opcional | Tamaño comercial; incluir si el negocio lo analiza. |
| `SizeUnitMeasureCode` | `nchar(3)` | FK | Opcional | Unidad del tamaño; requiere catálogo de unidades. |
| `WeightUnitMeasureCode` | `nchar(3)` | FK | Opcional | Unidad del peso; requiere catálogo de unidades. |
| `Weight` | `decimal(8,2)` | — | Opcional | Peso físico; útil en logística. |
| `DaysToManufacture` | `int` | — | Opcional | Tiempo de fabricación; no es prioritario para ventas. |
| `ProductLine` | `nchar(2)` | — | Incluir | Línea de producto; segmentación comercial. |
| `Class` | `nchar(2)` | — | Incluir | Clasificación del producto. |
| `Style` | `nchar(2)` | — | Incluir | Estilo del producto. |
| `ProductSubcategoryID` | `int` | FK | Incluir después | Permite incorporar subcategoría y categoría mediante dimensiones o transformación. |
| `ProductModelID` | `int` | FK | Opcional | Modelo técnico del producto; depende del alcance analítico. |
| `SellStartDate` | `datetime` | — | Incluir | Fecha de inicio de venta; útil para vigencia e historial. |
| `SellEndDate` | `datetime` | — | Incluir | Fecha de fin de venta, cuando existe. |
| `DiscontinuedDate` | `datetime` | — | Incluir | Fecha de descontinuación. |
| `rowguid` | `uniqueidentifier` | — | Excluir del modelo analítico | Identificador técnico de replicación; conservar solo si se requiere trazabilidad. |
| `ModifiedDate` | `datetime` | — | Incluir en staging | Marca de modificación; fundamental para watermark, auditoría y CDC. |

### Decisión dimensional

La dimensión debe conservar `ProductID` como clave de negocio y generar `ProductKey` como clave sustituta. Los atributos descriptivos se comparan mediante `RowHash`; cuando cambia un atributo controlado, se cierra la versión anterior y se inserta una nueva fila SCD Tipo 2.

---

## 6. `Person.Person`

### Propósito y contexto

Contiene datos personales reutilizados por varias entidades del sistema. Se relaciona con `Sales.Customer` mediante `BusinessEntityID = PersonID`. No todos sus registros son clientes; por eso no debe tratarse automáticamente como una dimensión de clientes.

| Campo | Tipo | Clave | Uso DW | Descripción y decisión |
|---|---|---|---|---|
| `BusinessEntityID` | `int` | PK / negocio | Incluir | Identificador de la persona; permite relacionarla con el cliente. |
| `PersonType` | `nchar(2)` | — | Incluir | Tipo de persona, por ejemplo individuo o contacto. |
| `NameStyle` | `bit` | — | Opcional | Indica formato especial del nombre; baja prioridad analítica. |
| `Title` | `nvarchar(8)` | — | Incluir | Tratamiento o título. |
| `FirstName` | `nvarchar(50)` | — | Incluir | Nombre. |
| `MiddleName` | `nvarchar(50)` | — | Incluir | Segundo nombre. |
| `LastName` | `nvarchar(50)` | — | Incluir | Apellido. |
| `Suffix` | `nvarchar(10)` | — | Incluir | Sufijo del nombre, cuando existe. |
| `EmailPromotion` | `int` | — | Opcional | Preferencia relacionada con promociones por correo. |
| `AdditionalContactInfo` | `xml` | — | Excluir inicialmente | Información semiestructurada; requiere parsing y no es necesaria para el primer modelo. |
| `Demographics` | `xml` | — | Excluir inicialmente | Datos demográficos semiestructurados; reservar para una futura dimensión enriquecida. |
| `rowguid` | `uniqueidentifier` | — | Excluir | Identificador técnico de replicación. |
| `ModifiedDate` | `datetime` | — | Incluir en staging | Soporta trazabilidad, watermark y CDC. |

### Decisión dimensional

Se recomienda usar los campos de nombre como parte de `DimCustomer`, pero filtrar la entidad según la relación existente en `Sales.Customer`. Los XML no se incorporan al modelo inicial; pueden conservarse en staging si existe un requerimiento de gobierno o auditoría.

---

## 7. `Sales.Customer`

### Propósito y contexto

Representa la relación comercial con el cliente. Es la fuente central de `dw.DimCustomer`. Un cliente puede ser una persona (`PersonID`) o una tienda (`StoreID`), por lo que el diseño debe contemplar ambos tipos.

| Campo | Tipo | Clave | Uso DW | Descripción y decisión |
|---|---|---|---|---|
| `CustomerID` | `int` | PK / negocio | Incluir | Identificador del cliente; clave de negocio de `DimCustomer`. |
| `PersonID` | `int` | FK nullable | Incluir | Relación con datos personales en `Person.Person`. |
| `StoreID` | `int` | FK nullable | Incluir después | Relación con una tienda; necesaria para clientes corporativos o comerciales. |
| `TerritoryID` | `int` | FK | Incluir | Permite asociar el cliente con un territorio de ventas. |
| `AccountNumber` | `varchar(10)` | — | Incluir | Número de cuenta comercial visible. |
| `rowguid` | `uniqueidentifier` | — | Excluir | Identificador técnico de replicación. |
| `ModifiedDate` | `datetime` | — | Incluir en staging | Marca de modificación para cargas incrementales y CDC. |

### Decisión dimensional

`CustomerID`, `TerritoryID`, `AccountNumber` y los datos descriptivos provenientes de `Person.Person` alimentan `DimCustomer`. `PersonID` y `StoreID` pueden conservarse como claves de trazabilidad, aunque no necesariamente se exponen al usuario final.

---

## 8. `Sales.SalesTerritory`

### Propósito y contexto

Contiene la estructura geográfica y comercial utilizada para asignar ventas y clientes. Su granularidad es un registro por territorio.

| Campo | Tipo | Clave | Uso DW | Descripción y decisión |
|---|---|---|---|---|
| `TerritoryID` | `int` | PK / negocio | Incluir | Identificador del territorio. |
| `Name` | `nvarchar(50)` | — | Incluir | Nombre del territorio. |
| `CountryRegionCode` | `nvarchar(3)` | FK lógica | Incluir | Código de país o región. |
| `Group` | `nvarchar(50)` | — | Incluir | Agrupación geográfica o comercial. |
| `SalesYTD` | `money` | — | Opcional | Acumulado operativo de ventas del año; puede duplicar medidas calculadas desde hechos. |
| `SalesLastYear` | `money` | — | Opcional | Acumulado operativo del año anterior. |
| `CostYTD` | `money` | — | Opcional | Costo acumulado operativo del año. |
| `CostLastYear` | `money` | — | Opcional | Costo acumulado del año anterior. |
| `rowguid` | `uniqueidentifier` | — | Excluir | Identificador técnico de replicación. |
| `ModifiedDate` | `datetime` | — | Incluir en staging | Trazabilidad y detección de cambios. |

### Decisión dimensional

`TerritoryID`, `Name`, `CountryRegionCode` y `Group` son atributos de `DimTerritory` o pueden desnormalizarse en `DimCustomer` según el diseño final. Los acumulados `SalesYTD`, `SalesLastYear`, `CostYTD` y `CostLastYear` no deben reemplazar las medidas calculadas en la tabla de hechos; se mantienen como referencia operativa opcional.

---

## 9. `Sales.SalesOrderHeader`

### Propósito y contexto

Contiene la cabecera de cada pedido de venta. Su granularidad es un registro por pedido. Aporta fechas, cliente, territorio, estado y totales documentales.

| Campo | Tipo | Clave | Uso DW | Descripción y decisión |
|---|---|---|---|---|
| `SalesOrderID` | `int` | PK / negocio | Incluir | Identificador del pedido. |
| `RevisionNumber` | `tinyint` | — | Incluir en staging | Versión de la cabecera; útil para detectar revisiones. |
| `OrderDate` | `datetime` | — | Incluir | Fecha del pedido; relación con `DimDate`. |
| `DueDate` | `datetime` | — | Incluir | Fecha comprometida de entrega. |
| `ShipDate` | `datetime` | — | Incluir | Fecha real de envío. |
| `Status` | `tinyint` | — | Incluir | Estado del pedido: 1 = In process, 2 = Approved, 3 = Backordered, 4 = Rejected, 5 = Shipped, 6 = Cancelled. El snapshot actual contiene únicamente `5 = Shipped`. |
| `OnlineOrderFlag` | `bit` | — | Incluir | Canal del pedido: `0` = pedido gestionado por vendedor; `1` = pedido realizado online por el cliente. |
| `SalesOrderNumber` | `nvarchar(25)` | — | Incluir | Número documental visible. |
| `PurchaseOrderNumber` | `nvarchar(25)` nullable | — | Opcional | Orden de compra del cliente. |
| `AccountNumber` | `nvarchar(15)` nullable | — | Opcional | Cuenta comercial del pedido. |
| `CustomerID` | `int` | FK | Incluir | Relación con `DimCustomer`. |
| `SalesPersonID` | `int` nullable | FK | Incluir | Relación con `DimSalesPerson`. El `NULL` es válido para pedidos online en el snapshot actual. |
| `TerritoryID` | `int` nullable | FK | Incluir | Relación con territorio. |
| `BillToAddressID` | `int` | FK | Futuro | Dirección de facturación; requiere dimensión de ubicación. |
| `ShipToAddressID` | `int` | FK | Futuro | Dirección de entrega. |
| `ShipMethodID` | `int` | FK | Incluir | Relación con `DimShipMethod`. |
| `CreditCardID` | `int` nullable | FK | Excluir | Identificador sensible/operativo; no se requiere para análisis comercial inicial. |
| `CreditCardApprovalCode` | `varchar(15)` nullable | — | Excluir | Dato operativo y potencialmente sensible. |
| `CurrencyRateID` | `int` nullable | FK | Futuro | Tipo de cambio aplicado. |
| `SubTotal` | `money` | — | Incluir | Importe antes de impuestos y transporte. |
| `TaxAmt` | `money` | — | Incluir | Impuesto aplicado. |
| `Freight` | `money` | — | Incluir | Flete o transporte. |
| `TotalDue` | `money` | — | Incluir | Total documental del pedido. |
| `Comment` | `nvarchar(128)` nullable | — | Opcional | Comentario libre; baja estandarización. |
| `rowguid` | `uniqueidentifier` | — | Excluir | Identificador técnico de replicación. |
| `ModifiedDate` | `datetime` | — | Incluir en staging | Candidato para detección incremental y trazabilidad. En el snapshot actual coincide con `ShipDate` y presenta numerosos empates, por lo que no constituye por sí solo una posición incremental determinista. |

### Decisión para hechos

La cabecera aporta fechas, contexto dimensional y atributos transaccionales de nivel pedido. `SubTotal`, `TaxAmt`, `Freight` y `TotalDue` tienen grain de pedido y no deben repetirse directamente en una tabla de hechos con grain de línea. En el snapshot actual, `TotalDue = SubTotal + TaxAmt + Freight` para los 31,465 pedidos y `SubTotal` reconcilia con `SUM(SalesOrderDetail.LineTotal)` al normalizar ambos importes a cuatro decimales.

---

## 10. `Sales.SalesOrderDetail`

### Propósito y contexto

Contiene las líneas de detalle incluidas en cada pedido. Su granularidad es una fila por línea de detalle de pedido; es la fuente transaccional principal de `dw.FactSales`. El identificador físico del grain es la clave compuesta (`SalesOrderID`, `SalesOrderDetailID`).

| Campo | Tipo | Clave | Uso DW | Descripción y decisión |
|---|---|---|---|---|
| `SalesOrderID` | `int` | PK (1/2) / FK | Incluir | Identifica el pedido padre y forma parte de la clave primaria compuesta. |
| `SalesOrderDetailID` | `int` | PK (2/2) | Incluir | Identificador de la línea dentro de la clave primaria compuesta. |
| `CarrierTrackingNumber` | `nvarchar(25)` nullable | — | Opcional | Seguimiento logístico; no es prioritario para ventas. |
| `OrderQty` | `smallint` | — | Incluir como medida | Cantidad vendida. |
| `ProductID` | `int` | FK | Incluir | Relación con `DimProduct`. |
| `SpecialOfferID` | `int` | FK | Incluir después | Permite analizar promociones; requiere fuente adicional. |
| `UnitPrice` | `money` | — | Incluir como medida | Precio unitario antes del descuento. |
| `UnitPriceDiscount` | `money` | — | Incluir como medida | Tasa o fracción de descuento aplicada al precio unitario. En el snapshot observado varía entre `0.0000` y `0.4000`. |
| `LineTotal` | `numeric(38,6)` calculada | — | Incluir | Importe neto calculado de la línea. Se validó en las 121,317 filas como `OrderQty * UnitPrice * (1 - UnitPriceDiscount)`. |
| `rowguid` | `uniqueidentifier` | — | Excluir | Identificador técnico de replicación. |
| `ModifiedDate` | `datetime` | — | Incluir en staging | Candidato para detección incremental y trazabilidad. En el snapshot actual coincide con `OrderDate` y presenta numerosos empates, por lo que requiere un desempate determinista para incrementalidad. |

### Medidas derivadas recomendadas

```sql
GrossAmount      = OrderQty * UnitPrice
DiscountAmount   = OrderQty * UnitPrice * UnitPriceDiscount
NetSalesAmount   = GrossAmount - DiscountAmount
```

El grain de `FactSales` debe declararse explícitamente como: **una fila por línea de detalle de pedido**. Esto evita asumir que (`SalesOrderID`, `ProductID`) define el grain y evita repetir `SubTotal`, `TaxAmt`, `Freight` o `TotalDue` de la cabecera en cada línea.

### Hallazgos de profiling relevantes para `FactSales`

- `SalesOrderHeader`: 31,465 pedidos.
- `SalesOrderDetail`: 121,317 líneas y 31,465 pedidos representados.
- No existen líneas huérfanas respecto de `SalesOrderHeader`.
- Los 3,806 pedidos gestionados por vendedor tienen `SalesPersonID` y `PurchaseOrderNumber`; los 27,659 pedidos online tienen ambos valores en `NULL`.
- Todos los pedidos del snapshot actual están en `Status = 5 (Shipped)` y tienen `ShipDate`.
- `OrderDate <= ShipDate <= DueDate` se cumple en los 31,465 pedidos.
- `LineTotal` reconcilia con la fórmula de net sales en las 121,317 líneas.
- `SUM(LineTotal)` reconcilia con `SalesOrderHeader.SubTotal` al comparar a cuatro decimales.
- No se observaron cantidades, precios ni totales de línea no positivos.
- `ModifiedDate` tiene comportamiento efectivo diario (`00:00:00.000`) y numerosos empates en ambas fuentes.
- La cobertura de business keys utilizada por ventas es completa para Product, Customer, Territory, SalesPerson y ShipMethod; no se encontraron referencias huérfanas.
- `dw.DimDate` cubre todas las fechas utilizadas por `OrderDate`, `ShipDate` y `DueDate`; no se encontraron fechas nulas ni fechas sin correspondencia dimensional.

---

## 11. Relaciones relevantes

| Relación | Propósito |
|---|---|
| `Sales.Customer.PersonID → Person.Person.BusinessEntityID` | Obtiene el nombre y datos personales del cliente. |
| `Sales.Customer.TerritoryID → Sales.SalesTerritory.TerritoryID` | Asocia clientes con territorios. |
| `Sales.SalesOrderHeader.CustomerID → Sales.Customer.CustomerID` | Relaciona pedidos con clientes. |
| `Sales.SalesOrderHeader.TerritoryID → Sales.SalesTerritory.TerritoryID` | Relaciona pedidos con territorios. |
| `Sales.SalesOrderHeader.SalesPersonID → Sales.SalesPerson.BusinessEntityID` | Relaciona pedidos gestionados por vendedor con `DimSalesPerson`; puede ser `NULL` para ventas online. |
| `Sales.SalesOrderHeader.ShipMethodID → Purchasing.ShipMethod.ShipMethodID` | Relaciona pedidos con métodos de envío. |
| `Sales.SalesOrderDetail.SalesOrderID → Sales.SalesOrderHeader.SalesOrderID` | Relaciona líneas con cabeceras. |
| `Sales.SalesOrderDetail.ProductID → Production.Product.ProductID` | Relaciona líneas con productos. |

## 12. Columnas técnicas que no deben perderse en staging

Aunque algunas columnas no lleguen al modelo dimensional, se recomienda conservar en staging:

- claves de negocio originales;
- `ModifiedDate`;
- `rowguid`, si se requiere conciliación con la fuente;
- fecha y hora de extracción (`ExtractedAt`);
- identificador de ejecución ETL (`ExecutionID`);
- hash de la fila cuando se utilice detección de cambios.

La capa `stg` debe permitir reconstruir qué se extrajo, cuándo se extrajo y desde qué registro fuente se generó cada fila del DW.

## 13. Reglas de modelado aplicadas

1. Las claves de negocio de AdventureWorks2022 no se utilizan como claves primarias finales de las dimensiones.
2. Las dimensiones generan claves sustitutas, por ejemplo `ProductKey` y `CustomerKey`.
3. Las fechas se relacionan con `dw.DimDate` mediante claves enteras como `DateKey`.
4. Los atributos descriptivos de producto se gestionan con SCD Tipo 2 cuando el cambio debe conservar historial.
5. Las medidas de ventas se toman principalmente del detalle; los totales de cabecera se usan con cuidado para evitar duplicidad.
6. Los datos sensibles de pago quedan fuera del modelo analítico inicial.
7. Los campos XML y comentarios libres se excluyen inicialmente por su baja estandarización.
8. Las columnas `ModifiedDate` son importantes para cargas incrementales y CDC, aunque no sean atributos de negocio.

## 14. Pendientes de ampliación

- Incorporar `Production.ProductSubcategory` y `Production.ProductCategory` para completar la jerarquía del producto.
- Incorporar tablas de direcciones si se requiere análisis geográfico detallado.
- Incorporar `Sales.SpecialOffer` para analizar promociones.
- Definir formalmente `dw.FactSales` y su estrategia para medidas de cabecera.
- Validar tipos, nulabilidad y relaciones contra la instancia real mediante el catálogo de SQL Server.
- Comparar cargas full, watermark y CDC utilizando `ModifiedDate` y las tablas habilitadas para Change Data Capture.

## 15. Consulta de validación del catálogo

```sql
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    c.column_id AS ColumnID,
    c.name AS ColumnName,
    ty.name AS DataType,
    c.max_length AS MaxLength,
    c.precision,
    c.scale,
    c.is_nullable AS IsNullable,
    c.is_computed AS IsComputed
FROM AdventureWorks2022.sys.tables AS t
INNER JOIN AdventureWorks2022.sys.schemas AS s
    ON s.schema_id = t.schema_id
INNER JOIN AdventureWorks2022.sys.columns AS c
    ON c.object_id = t.object_id
INNER JOIN AdventureWorks2022.sys.types AS ty
    ON ty.user_type_id = c.user_type_id
WHERE
    (s.name = N'Production' AND t.name = N'Product')
 OR (s.name = N'Person' AND t.name = N'Person')
 OR (s.name = N'Sales' AND t.name IN
    (N'Customer', N'SalesTerritory', N'SalesOrderHeader', N'SalesOrderDetail'))
ORDER BY
    s.name,
    t.name,
    c.column_id;
```

## 16. Control de cambios

| Versión | Fecha | Cambio |
|---|---|---|
| 1.0 | 2026-08-08 | Creación del diccionario de datos de las seis tablas fuente iniciales. |
