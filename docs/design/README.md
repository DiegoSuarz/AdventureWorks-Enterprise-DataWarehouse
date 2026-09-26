# Design Specifications

This directory contains the detailed technical specifications for every analytical object implemented in the Enterprise Data Warehouse.

Each specification describes how a warehouse object is designed before or during implementation.

---

## Directory Structure

```text
design/
│
├── dimensions/
│
└── facts/
```

---

## Current Dimensions

| Document | Status |
|----------|--------|
| `dim-date.md` | Implemented |
| `dim-product.md` | Implemented |
| `dim-customer.md` | In Progress |

Future dimensions include:

- `dim-territory.md`
- `dim-salesperson.md`
- `dim-shipmethod.md`

---

## Fact Tables

| Document | Status |
|----------|--------|
| [fact-sales.md](facts/fact-sales.md) | Fact Design and Full Snapshot ETL Validated |
| [fact-sales-incremental.md](facts/fact-sales-incremental.md) | Incremental ETL Validated |
| [fact-sales-data-quality.md](facts/fact-sales-data-quality.md) | Quality and Reconciliation Complete |
| [fact-sales-star-validation.md](facts/fact-sales-star-validation.md) | Analytical Star Validation Complete |

Additional fact tables may be added as the project evolves.

---

## Standard Structure

Every Design Specification follows the same structure:

1. Objective
2. Source
3. Grain
4. Business Key
5. Surrogate Key
6. Columns
7. Business Rules
8. ETL Objects
9. Validation Criteria
10. Design Decisions (ADR Summary)

---

## Relationship with Architecture

Architecture documents define project-wide engineering standards.

Design Specifications apply those standards to individual warehouse objects.

Example:

```text
Architecture

↓

SCD Strategy

↓

Design

↓

DimProduct
```

---

## Documentation Lifecycle

Each warehouse object follows the same lifecycle:

```text
Design

↓

Implementation

↓

Validation

↓

Documentation

↓

Release
```

The documentation evolves together with the implementation.