# Architecture Documentation

This directory contains the architectural standards used throughout the AdventureWorks Enterprise Data Warehouse.

These documents define the engineering principles that guide the design and implementation of the project.

---

## Architecture Documents

| Document | Purpose |
|----------|---------|
| `dimensional-model.md` | Dimensional modeling standards |
| `scd-strategies.md` | Historical data management |
| `etl-pattern.md` | ETL architecture |
| `naming-conventions.md` | Naming standards |
| `sql-style-guide.md` | SQL coding standards |
| `versioning.md` | Release management |
| `adr/` | Architecture Decision Records |

---

## Scope

These standards apply to:

- Database objects
- ETL procedures
- Documentation
- Source control
- Project organization

Every implementation within the repository should comply with these standards.

---

## Relationship with Design Specifications

Architecture documents define the general engineering principles.

Design Specifications describe the implementation of specific warehouse objects.

For example:

```text
Architecture

↓

How should SCD work?

↓

Design

↓

How does DimProduct implement SCD?
```

---

## Architecture Philosophy

The project follows these principles:

- Consistency
- Simplicity
- Maintainability
- Scalability
- Traceability
- Documentation-first engineering

---

## Related Documentation

```text
docs/design/

docs/architecture/adr/
```