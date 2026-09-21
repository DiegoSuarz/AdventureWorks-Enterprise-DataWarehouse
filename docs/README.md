# Project Documentation

Welcome to the documentation for the **AdventureWorks Enterprise Data Warehouse** project.

The documentation is organized to separate project-wide architecture, object-level design, source-system analysis, reference material, diagrams, and supporting images.

---

## Documentation Structure

```text
docs/
│
├── architecture/
│   ├── adr/
│   ├── README.md
│   ├── SolutionArchitecture.md
│   ├── dimensional-model.md
│   ├── etl-pattern.md
│   ├── naming-conventions.md
│   ├── scd-strategies.md
│   ├── sql-style-guide.md
│   ├── sql.style-guide.md
│   └── versioning.md
│
├── design/
│   ├── dimensions/
│   │   ├── dim-date.md
│   │   ├── dim-product.md
│   │   ├── dim-customer.md
│   │   ├── dim-territory.md
│   │   ├── dim-salesperson.md
│   │   └── dim-shipmethod.md
│   ├── CodingStandards.md
│   ├── NamingConventions.md
│   └── README.md
│
├── diagrams/
├── images/
├── reference/
│   └── tables-catalog.md
├── source/
└── README.md
```

---

## Architecture

The `architecture/` folder contains project-wide engineering standards and architectural decisions.

Key documents include:

| Document | Description |
|---|---|
| `SolutionArchitecture.md` | Overall warehouse solution architecture |
| `dimensional-model.md` | Dimensional modeling principles |
| `scd-strategies.md` | Slowly Changing Dimension strategies |
| `etl-pattern.md` | Standard ETL architecture and loading patterns |
| `naming-conventions.md` | Project naming standards |
| `sql.style-guide.md` | SQL coding standards |
| `versioning.md` | Versioning and release strategy |
| `adr/` | Architecture Decision Records |

---

## Design

The `design/` folder contains implementation-oriented specifications and engineering standards.

### Dimension Specifications

Current dimensional design specifications:

```text
dw.DimDate
dw.DimProduct
dw.DimCustomer
dw.DimTerritory
dw.DimSalesPerson
dw.DimShipMethod
```

Each specification documents the relevant grain, business key, surrogate key, attribute strategy, ETL behavior, validation rules, and design decisions.

The current dimensional model contains six implemented dimensions.

---

## Source Documentation

The `source/` folder contains source-system analysis and profiling material used to understand AdventureWorks operational entities before warehouse design.

Source documentation supports:

- source-to-target mapping;
- business-key validation;
- relationship analysis;
- nullability and data-quality analysis;
- dimensional design decisions.

---

## Reference Documentation

The `reference/` folder contains consolidated operational and structural references.

The main reference document is:

```text
reference/tables-catalog.md
```

The table catalog documents the current physical warehouse model, including:

```text
6 Dimension Tables
5 Staging Tables
2 Audit Tables
0 Fact Tables
-----------------
13 Total Tables
```

---

## Diagrams and Images

The `diagrams/` and `images/` folders contain visual material used by the project documentation, including architecture and modeling assets.

---

## Current Dimensional Scope

The current implemented dimensional layer is:

```text
dw.DimDate
dw.DimProduct
dw.DimCustomer
dw.DimTerritory
dw.DimSalesPerson
dw.DimShipMethod
```

Current staging objects are:

```text
stg.Product
stg.Customer
stg.Territory
stg.SalesPerson
stg.ShipMethod
```

Operational ETL control is implemented through:

```text
audit.ETLExecutionLog
audit.ETLWatermark
```

`audit.ETLExecutionLog` stores execution history, while
`audit.ETLWatermark` stores the durable control state used by incremental
watermark-driven processes.

The current engineering focus is:

```text
M6 — FactSales & Star Schema Completion
```

The active warehouse expansion target is `dw.FactSales`. Module 6 completes the
analytical star schema before the Power BI layer is built.

---

## Documentation Philosophy

The project documentation uses complementary layers:

### Architecture

Defines **how the project is built** and which engineering standards apply globally.

### Design

Defines **how individual warehouse objects are modeled and implemented**.

### Source

Documents **what exists in the source system** and the profiling evidence used for modeling decisions.

### Reference

Provides **consolidated project-state information**, such as the physical tables catalog.

### ADR

Explains **why important architectural decisions were made**.

---

## Documentation Status

```text
Architecture Documentation : Active
Dimension Specifications   : 6 implemented
Source Documentation        : Active
Reference Catalog           : Active
Current Stable Release      : v1.3.0
Current Module              : Module 6 — FactSales & Star Schema Completion
Next Module                 : Module 7 — Power BI Analytics
Final Module                : Module 8 — Production Hardening & Project Closure
```

Documentation evolves together with the implementation and is considered part of the project deliverables.
