# Versioning Strategy

## 1. Purpose

This document defines the versioning strategy used throughout the AdventureWorks Enterprise Data Warehouse.

The objective is to provide a consistent release process, ensure traceability of changes, and establish predictable version management across source code, documentation, database objects, and GitHub releases.

The project follows:

- Semantic Versioning (SemVer)
- Conventional Commits
- Squash & Merge workflow
- Git Tags
- GitHub Releases
- CHANGELOG-driven documentation

---

# 2. Semantic Versioning

The project follows Semantic Versioning (SemVer):

```text
MAJOR.MINOR.PATCH
```

Example:

```text
v1.2.0
```

Where:

- **MAJOR** → Breaking architectural changes.
- **MINOR** → New functionality while maintaining backward compatibility.
- **PATCH** → Bug fixes, documentation improvements, or minor refinements.

---

# 3. Version Increment Rules

## MAJOR

Increment when:

- introducing breaking database changes;
- redesigning the dimensional model;
- changing ETL architecture;
- incompatible schema modifications.

Example:

```text
v2.0.0
```

---

## MINOR

Increment when adding new functionality.

Examples:

- new dimensions;
- new fact tables;
- new ETL procedures;
- new architecture modules;
- new documentation sections.

Examples:

```text
v1.1.0

v1.2.0

v1.3.0
```

---

## PATCH

Increment when:

- fixing SQL bugs;
- improving documentation;
- refactoring without functional changes;
- correcting ETL logic;
- improving tests.

Examples:

```text
v1.2.1

v1.2.2
```

---

# 4. Release Workflow

Every release follows the same lifecycle.

```text
Feature Branch

↓

Development

↓

Validation

↓

Documentation

↓

Commit

↓

Pull Request

↓

Code Review

↓

Squash & Merge

↓

Delete Feature Branch

↓

Update CHANGELOG

↓

Git Tag

↓

GitHub Release
```

No release should skip any stage.

---

# 5. Branch Strategy

Main branch:

```text
main
```

Feature branches:

```text
feature/<feature-name>
```

Examples:

```text
feature/product-dimension-scd

feature/customer-dimension

feature/fact-sales
```

Release preparation:

```text
chore/release-v1.2.0
```

Hotfixes:

```text
hotfix/<description>
```

---

# 6. Pull Requests

Every feature must be merged through a Pull Request.

The Pull Request should include:

- implementation summary;
- validation summary;
- affected documentation;
- target release.

Typical title:

```text
feat: implement Customer dimension
```

---

# 7. Merge Strategy

The project uses:

```text
Squash and Merge
```

Reasons:

- clean commit history;
- one commit per feature;
- easier release tracking;
- simplified Git log.

Feature branches are deleted after merging.

---

# 8. Git Tags

Every stable release receives a Git tag.

Pattern:

```text
v1.0.0

v1.1.0

v1.2.0
```

Tags always reference commits on the `main` branch.

---

# 9. GitHub Releases

Each release is published through GitHub Releases.

Release title:

```text
v1.2.0 – Dimensional Model Expansion
```

Release notes summarize:

- implemented features;
- architectural decisions;
- validation status;
- documentation updates.

---

# 10. CHANGELOG

Every release updates `CHANGELOG.md`.

The project follows the **Keep a Changelog** structure.

Example:

```markdown
## [Unreleased]

### Added

...

### Changed

...

### Fixed

...

### Validated

...
```

When a release is created:

```text
Unreleased

↓

Versioned Release

↓

New Unreleased Section
```

---

# 11. Documentation Synchronization

Before creating a release, verify that the following documents are up to date:

- README
- CHANGELOG
- Design Specifications
- Architecture Documents

No release should be published with outdated documentation.

---

# 12. Release Checklist

Before creating a release:

- Feature implementation completed.
- Validation completed.
- Tests executed.
- Documentation updated.
- CHANGELOG updated.
- Pull Request merged.
- Feature branch deleted.
- Repository synchronized.
- Git tag created.
- GitHub Release published.

---

# 13. Documentation Versioning

Architecture documents evolve independently of application releases.

Minor documentation improvements do not require a new software version unless they accompany functional changes.

---

# 14. Design Specification Lifecycle

Every significant warehouse object follows this lifecycle:

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

Design Specifications should be completed before implementation whenever practical.

---

# 15. Repository Milestones

The project is organized into functional milestones.

Example roadmap:

| Version | Milestone |
|---------|-----------|
| v1.0.0 | Database Foundation |
| v1.1.0 | Product Dimension History Management |
| v1.2.0 | Dimensional Model Expansion |
| v1.3.0 | FactSales |
| v1.4.0 | Incremental Loading |
| v1.5.0 | CDC Integration |
| v2.0.0 | Azure Data Factory Integration |

Future milestones may evolve as the project grows.

---

# 16. Release Philosophy

A release should represent a coherent, stable, and validated milestone.

Releases are not created merely because code was written.

A release is published only when:

- functionality is complete;
- validation is successful;
- documentation is synchronized;
- repository history is clean.

---

# 17. Repository Integrity

The following principles are always maintained:

1. One feature per Pull Request.
2. One Squash Commit per merged feature.
3. One Git Tag per release.
4. One GitHub Release per tag.
5. One synchronized CHANGELOG entry per release.
6. Documentation evolves together with the implementation.

---

# 18. Related Documentation

Architecture:

```text
docs/architecture/
```

Design Specifications:

```text
docs/design/
```

Project History:

```text
CHANGELOG.md
```

Project Overview:

```text
README.md
```

---

# 19. Architecture Status

```text
Architecture: Approved
Versioning Strategy: Semantic Versioning (SemVer)
Merge Strategy: Squash & Merge
Release Strategy: Git Tags + GitHub Releases
Current Release: v1.1.0
Next Planned Release: v1.2.0
```