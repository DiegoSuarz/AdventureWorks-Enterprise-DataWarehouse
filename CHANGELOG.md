# Changelog

All notable changes to this project will be documented in this file.

The format is inspired by Keep a Changelog and the project follows Semantic Versioning (SemVer).

---

## [Unreleased]

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