# Architecture Decision Records (ADR)

## Purpose

This directory contains the **Architecture Decision Records (ADRs)** for the AdventureWorks Enterprise Data Warehouse.

Each ADR documents a significant architectural decision made during the design and evolution of the project.

The purpose of these records is to explain **why** an architectural decision was made, not **how** it was implemented.

Detailed implementation can be found in the corresponding Design Specifications and Architecture documents.

---

## ADR Structure

Every ADR follows the same template:

1. Status
2. Date
3. Context
4. Decision Drivers
5. Decision
6. Alternatives Considered
7. Consequences
8. Related Documents
9. References
10. Decision Owner
11. Review Status

---

## ADR Lifecycle

Architecture decisions progress through the following lifecycle:

```text
Proposed
        ↓
Accepted
        ↓
Implemented
        ↓
Superseded (optional)
        ↓
Deprecated (optional)
```

Most ADRs in this repository are expected to remain in the **Accepted** state.

If a decision changes in the future, a new ADR should supersede the previous one rather than modifying historical records.

---

## Numbering Convention

ADR identifiers are globally unique and sequential.

Example:

```text
ADR-001
ADR-002
ADR-003
...
```

Numbers are never reused.

---

## Current ADRs

| ADR | Description | Status |
|------|-------------|--------|
| ADR-001 | Use Star Schema | Accepted |
| ADR-002 | Use Surrogate Keys | Accepted |
| ADR-003 | Use Slowly Changing Dimensions | Accepted |
| ADR-004 | Use SCD Type 2 for Product | Planned |
| ADR-005 | Use RowHash for Change Detection | Planned |
| ADR-006 | Use Filtered Unique Indexes | Planned |
| ADR-007 | Use Half-Open Validity Intervals | Planned |
| ADR-008 | Separate Customer and Territory | Planned |
| ADR-009 | Layered ETL Architecture | Planned |
| ADR-010 | Git Workflow | Planned |

---

## Relationship with Other Documentation

The repository documentation is organized as follows:

```text
docs/

├── architecture/
│   ├── *.md
│   └── adr/
│
└── design/
```

- **Architecture** documents define project-wide engineering standards.
- **Design Specifications** describe the implementation of individual warehouse objects.
- **ADRs** explain the architectural decisions that shaped those standards.

---

## Guiding Principle

Architecture decisions should be:

- intentional;
- documented;
- reviewable;
- traceable;
- supported by implementation.

An ADR captures the reasoning behind a decision so future contributors can understand **why** the project evolved in a particular direction.

---

## Maintainers

AdventureWorks Enterprise Data Warehouse Architecture Team