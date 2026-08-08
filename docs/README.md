# Project Documentation

Welcome to the documentation for the **AdventureWorks Enterprise Data Warehouse** project.

This documentation is organized into two major areas:

- **Architecture** – Project-wide engineering standards and architectural decisions.
- **Design** – Object-level specifications for dimensions, fact tables, and ETL components.

---

## Documentation Structure

```text
docs/
│
├── architecture/
│
├── design/
│
└── README.md
```

---

## Architecture

The **architecture** folder contains the engineering standards that apply across the entire project.

Current documents:

| Document | Description |
|----------|-------------|
| `dimensional-model.md` | Enterprise dimensional modeling principles |
| `scd-strategies.md` | Slowly Changing Dimension strategies |
| `etl-pattern.md` | Standard ETL architecture |
| `naming-conventions.md` | Naming standards |
| `sql-style-guide.md` | SQL coding standards |
| `versioning.md` | Versioning and release strategy |
| `adr/` | Architecture Decision Records |

---

## Design

The **design** folder contains detailed specifications for individual warehouse objects.

Current structure:

```text
design/
│
├── dimensions/
│
└── facts/
```

Each Design Specification describes:

- Objective
- Grain
- Business Key
- Surrogate Key
- Columns
- Business Rules
- ETL Strategy
- Validation
- Design Decisions

---

## Documentation Philosophy

The project separates documentation into three complementary layers.

### Architecture

Defines **how the project is built**.

### Design

Defines **how each warehouse object is implemented**.

### ADR

Explains **why important architectural decisions were made**.

---

## Documentation Status

Current documentation includes:

- Architecture Standards
- Design Specifications
- Architecture Decision Records (ADR)

Documentation evolves together with the implementation and is considered part of the project deliverables.