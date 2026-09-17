# Changelog

All notable changes to this project will be documented in this file.

The format is inspired by Keep a Changelog and the project follows Semantic Versioning (SemVer).

---

## [Unreleased]

---

## [v1.2.0] - 2026-09-16

### Added

- Implemented `dw.DimCustomer` with a consolidated analytical customer model for Individual and Store customers.
- Added `stg.Customer`, `etl.LoadCustomerStage`, and `etl.LoadDimCustomer`.
- Implemented `dw.DimTerritory` with Type 1 and Type 2 geographic and commercial classification handling.
- Added `stg.Territory`, `etl.LoadTerritoryStage`, and `etl.LoadDimTerritory`.
- Implemented `dw.DimSalesPerson` by consolidating `Sales.SalesPerson`, `Person.Person`, and `HumanResources.Employee`.
- Added `stg.SalesPerson`, `etl.LoadSalesPersonStage`, and `etl.LoadDimSalesPerson`.
- Implemented `dw.DimShipMethod` with historical tariff tracking for `ShipBase` and `ShipRate`.
- Added `stg.ShipMethod`, `etl.LoadShipMethodStage`, and `etl.LoadDimShipMethod`.
- Added design specifications for Customer, Territory, SalesPerson, and ShipMethod.
- Added AdventureWorks source-table documentation used during source profiling and dimensional design.
- Added WSL-based development environment support for SQL Server connectivity and repository development.

### Changed

- Expanded the dimensional model from Product and Date to six implemented dimensions.
- Standardized Type 0, Type 1, and Type 2 dimensional behavior across the new dimensions.
- Standardized SHA2-256 `RowHash` usage so Type 2 hashes contain only historically relevant attributes.
- Standardized half-open temporal validity using `[EffectiveStartDateTime, EffectiveEndDateTime)`.
- Standardized filtered unique indexes to protect one current version per business key.
- Protected simultaneous Type 1 + Type 2 changes so historical versions retain their original Type 1 values.
- Synchronized dimension design documentation with the implemented database state.
- Expanded the physical tables catalog to cover 6 dimensions, 5 staging tables, and the ETL audit table.
- Updated the project documentation map and repository overview to reflect the current architecture.

### Validated

- Confirmed exactly one current dimensional version per business key across all implemented dimensions.
- Confirmed no invalid temporal ranges or overlapping historical intervals.
- Reconciled every staging snapshot against its corresponding current dimensional state with zero missing or mismatched rows.
- Confirmed controlled Type 1 updates without unintended history creation.
- Confirmed controlled Type 2 changes create new versions with continuous temporal boundaries.
- Confirmed simultaneous Type 1 + Type 2 behavior for historized dimensions.
- Confirmed idempotent repeated loads.
- Confirmed all 10 implemented ETL processes have a latest execution status of `Succeeded`.
- Confirmed current dimensional counts and intentionally retained historical test versions.

### Documentation

- Updated all six dimension design specifications to reflect implementation and validation status.
- Updated `docs/reference/tables-catalog.md` with the complete current physical model.
- Updated `docs/README.md` with the current documentation structure.
- Prepared root `README.md` and release documentation for the dimensional-model expansion milestone.

---

## [v1.1.0] - 2026-08-06

### Added

- Implemented `etl.LoadDimProduct` using Slowly Changing Dimension Type 2 (SCD Type 2).
- Added historical version management for product dimension records.
- Added support for Type 1 and Type 2 attribute handling.
- Added temporal versioning using `EffectiveStartDateTime` and `EffectiveEndDateTime`.
- Added current version tracking using `IsCurrent`.

### Changed

- Refactored `etl.LoadProductStage` to calculate `RowHash` using only SCD Type 2 attributes.

### Fixed

- None.

### Removed

- None.

### Validated

- Initial full load.
- Idempotent execution.
- Type 1 attribute updates.
- Type 2 historical versioning.
- Historical rollback validation.
- Temporal consistency.
- Single current version per business key.
- ETL execution audit logging.
- Historical version integrity.
- Non-overlapping validity periods.

### Documentation

- Added technical design for SCD Type 2 implementation.
- Documented the Product dimension history management workflow.

---

## v1.0.0

### Added

- Repository structure.
- Database initialization.
- Data Warehouse schemas (`dw`, `stg`, `etl`, `audit`).
- `dw.DimDate`.
- `dw.DimProduct`.
- Product staging layer (`stg.Product`).
- ETL audit framework.
- Full-load staging procedure (`etl.LoadProductStage`).
- SHA2-256 `RowHash` generation for change detection.
- Project architecture diagrams.
- Initial project roadmap.
- Project documentation (`README.md`).
- Initial release notes (`CHANGELOG.md`).

### Changed

- None.

### Fixed

- None.

### Removed

- None.

### Validated

- Database initialization.
- Initial staging load.
- Product extraction.
- ETL audit logging.

### Documentation

- Initial project documentation.
- Repository organization.
