# AdventureWorks Enterprise Data Warehouse

<div align="center">

> Production-oriented Data Warehouse project built from scratch with SQL Server and T-SQL, using dimensional modeling, audited ETL, historical tracking, and professional Git workflows.

<br>

![SQL Server](https://img.shields.io/badge/SQL_Server-CC2927?style=for-the-badge&logo=microsoftsqlserver&logoColor=white)
![T-SQL](https://img.shields.io/badge/T--SQL-025E8C?style=for-the-badge)
![Git](https://img.shields.io/badge/Git-F05032?style=for-the-badge&logo=git&logoColor=white)
![GitHub](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github)
![Power BI](https://img.shields.io/badge/Power_BI-Planned-F2C811?style=for-the-badge&logo=powerbi&logoColor=black)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

</div>

---

# Table of Contents

- [Overview](#overview)
- [Business Problem](#business-problem)
- [Current Architecture](#current-architecture)
- [Implemented Data Model](#implemented-data-model)
- [Engineering Highlights](#engineering-highlights)
- [Technology Stack](#technology-stack)
- [Repository Structure](#repository-structure)
- [Validation Status](#validation-status)
- [Current Progress](#current-progress)
- [Documentation](#documentation)
- [License](#license)

---

# Overview

**AdventureWorks Enterprise Data Warehouse** is a portfolio Data Engineering project that transforms the AdventureWorks OLTP database into a structured analytical platform.

The project is developed as an engineering system rather than a collection of isolated SQL exercises. It applies:

- dimensional modeling;
- staging and warehouse separation;
- audited ETL execution;
- idempotent load patterns;
- Slowly Changing Dimensions;
- SHA2-256 change detection;
- temporal version management;
- validation and reconciliation;
- version-controlled database development.

The current physical model contains **6 dimensions, 5 staging tables, 11 ETL procedures, and 2 audit/control tables**.

---

# Business Problem

Operational databases are optimized for transactional workloads. Analytical reporting requires a different model that provides stable business keys, descriptive dimensions, historical context, traceable transformations, and repeatable data-loading processes.

This project reorganizes AdventureWorks operational data into an analytical architecture designed to support future business intelligence and reporting workloads.

---

# Current Architecture

```text
AdventureWorks2022
        │
        ▼
┌────────────────────────┐
│     Staging Layer      │
│                        │
│ stg.Product            │
│ stg.Customer           │
│ stg.Territory          │
│ stg.SalesPerson        │
│ stg.ShipMethod         │
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│   Dimensional Layer    │
│                        │
│ dw.DimDate             │
│ dw.DimProduct          │
│ dw.DimCustomer         │
│ dw.DimTerritory        │
│ dw.DimSalesPerson      │
│ dw.DimShipMethod       │
└────────────────────────┘

        ETL execution
            │
            ▼
┌────────────────────────┐
│      Audit Layer       │
│                        │
│ audit.ETLExecutionLog  │
│ audit.ETLWatermark     │
└────────────────────────┘

Future analytical layers
        │
        ├── Fact model
        └── Power BI
```

The warehouse uses four principal schemas:

| Schema | Responsibility |
|---|---|
| `stg` | Normalized source snapshots or bounded incremental batch deltas |
| `dw` | Analytical dimensional objects |
| `etl` | Stored procedures that move and transform data |
| `audit` | ETL execution history and persisted incremental-control state |

---

# Implemented Data Model

## Dimensions

| Dimension | Business Key | History Strategy | Current Members |
|---|---|---|---:|
| `dw.DimDate` | `DateKey` | Immutable calendar | 9,496 |
| `dw.DimProduct` | `ProductID` | Type 0 + Type 1 + Type 2 | 504 |
| `dw.DimCustomer` | `CustomerID` | Type 1 | 19,820 |
| `dw.DimTerritory` | `TerritoryID` | Type 0 + Type 1 + Type 2 | 10 |
| `dw.DimSalesPerson` | `BusinessEntityID` | Type 0 + Type 1 + Type 2 | 17 |
| `dw.DimShipMethod` | `ShipMethodID` | Type 0 + Type 1 + Type 2 | 5 |

Controlled SCD validation has intentionally produced historical versions in Product, Territory, SalesPerson, and ShipMethod.

## Staging

Current staging behavior:

```text
stg.Product       : current source snapshot
stg.Customer      : current source snapshot
stg.Territory     : current source snapshot
stg.SalesPerson   : current source snapshot
stg.ShipMethod    : current incremental batch delta
```

Snapshot staging objects hold normalized current source state. `stg.ShipMethod`
holds only the rows selected for the current composite-watermark batch.
Historical dimensional versions remain exclusively in the `dw` layer.

---

# Engineering Highlights

- Layered `stg` → `dw` ETL architecture
- SQL Server surrogate keys
- Business-key-driven dimensional loading
- SCD Type 1 and Type 2 processing
- SHA2-256 `RowHash` change detection
- Half-open temporal validity: `[Start, End)`
- Filtered unique indexes for one current version per business key
- Protection of simultaneous Type 1 + Type 2 changes
- Idempotent ETL behavior
- Composite `(ModifiedDate, BusinessKey)` incremental watermarks
- Persisted HIGH watermark batch boundaries
- No-change batch detection
- Retryable failed batches with exact HIGH-boundary reuse
- Transaction and error handling
- Centralized execution auditing
- Staging-to-current-dimension reconciliation
- Source profiling before dimensional design
- Git feature branches, Pull Requests, and Squash & Merge

---

# Technology Stack

| Category | Technology |
|---|---|
| Database | SQL Server 2022 Developer |
| Query / ETL Language | T-SQL |
| Source Dataset | AdventureWorks2022 |
| Development Environment | Windows 11 + WSL Ubuntu |
| IDE | Visual Studio Code |
| Version Control | Git |
| Repository | GitHub |
| Business Intelligence | Power BI *(planned)* |

---

# Repository Structure

```text
AdventureWorks-Enterprise-DataWarehouse/
│
├── database/
│   ├── 00_initialization/
│   ├── 01_dimensions/
│   ├── 03_staging/
│   ├── 04_procedures/
│   ├── 05_seed/
│   └── audit/
│
├── docs/
│   ├── architecture/
│   ├── design/
│   ├── diagrams/
│   ├── images/
│   ├── reference/
│   └── source/
│
├── powerbi/
├── sample-data/
├── tests/
│
├── CHANGELOG.md
├── README.md
├── LICENSE
└── requirements.txt
```

The repository separates executable database objects from architecture, design, source-analysis, and reference documentation.

---

# Validation Status

Module 5 closure includes dimensional integrity validation together with
the ShipMethod incremental-loading pilot.

```text
Current-version uniqueness       : PASS
Temporal range integrity         : PASS
Historical overlap validation    : PASS
Composite watermark ordering     : PASS
HIGH watermark persistence       : PASS
Failure + exact retry            : PASS
Post-retry no-op                 : PASS
Latest ETL process health        : 11 / 11 Succeeded
```

Current dimensional state:

| Dimension | Total Versions | Business Keys | Current | Historical |
|---|---:|---:|---:|---:|
| `DimCustomer` | 19,820 | 19,820 | 19,820 | 0 |
| `DimProduct` | 506 | 504 | 504 | 2 |
| `DimSalesPerson` | 20 | 17 | 17 | 3 |
| `DimShipMethod` | 8 | 5 | 5 | 3 |
| `DimTerritory` | 13 | 10 | 10 | 3 |

---

# Current Progress

| Module | Status |
|---|:---:|
| M0 — Project Foundation & Environment | ✅ Completed |
| M1 — Source System Analysis | ✅ Completed |
| M2 — Dimensional Modeling | ✅ Completed |
| M3 — Data Warehouse Foundation | ✅ Completed |
| M4 — Dimensional Model Expansion | ✅ Completed |
| M5 — Composite + High Watermark Incremental Loading | ✅ Completed |
| M6 — FactSales & Star Schema Completion | 🟡 Current |
| M7 — Power BI Analytics | ⬜ Planned |
| M8 — Production Hardening & Project Closure | ⬜ Planned |

The latest stable release is **v1.3.0 — Composite + High Watermark Incremental Loading**.
The current engineering focus is **M6 — FactSales & Star Schema Completion**.

---

# Documentation

Project documentation is maintained alongside the implementation.

Key entry points:

- [`docs/README.md`](docs/README.md) — documentation map;
- [`docs/reference/tables-catalog.md`](docs/reference/tables-catalog.md) — current physical table catalog;
- [`docs/design/dimensions/`](docs/design/dimensions/) — dimension design specifications;
- [`docs/architecture/`](docs/architecture/) — architecture and engineering standards;
- [`docs/source/`](docs/source/) — source-system analysis and profiling.

---

# License

This project is licensed under the MIT License.
