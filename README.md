# AdventureWorks Enterprise Data Warehouse

> A production-inspired Enterprise Data Warehouse built from scratch using SQL Server 2022, Kimball dimensional modeling principles, and modern data engineering practices.

## Project Overview

This project designs and implements an Enterprise Data Warehouse using the AdventureWorks2022 transactional database as its source system.

The solution transforms operational sales data into a dimensional model optimized for historical analysis, reporting, and business intelligence.

## Project Goals

* Design a dimensional model following Kimball methodology.
* Build dimension and fact tables using SQL Server 2022.
* Implement auditable and reproducible ETL processes.
* Manage historical changes using Slowly Changing Dimensions.
* Apply data quality and performance optimization practices.
* Integrate the solution with Power BI.
* Orchestrate cloud pipelines using Azure Data Factory.
* Explore an equivalent analytical implementation in Microsoft Fabric.
* Document architectural and technical decisions.

## Technology Stack

| Category              | Technology                   |
| --------------------- | ---------------------------- |
| Source System         | AdventureWorks2022           |
| Data Warehouse        | SQL Server 2022              |
| Query Language        | T-SQL                        |
| Modeling              | Kimball Dimensional Modeling |
| Version Control       | Git and GitHub               |
| Documentation         | Markdown                     |
| Diagrams              | Draw.io                      |
| Business Intelligence | Power BI                     |
| Cloud Orchestration   | Azure Data Factory           |
| Analytics Platform    | Microsoft Fabric             |

## Current Status

* **Version:** `v0.1.0`
* **Phase:** Foundation
* **Current branch:** `feature/repository-foundation`

## Planned Architecture

```text
AdventureWorks2022
        |
        v
   Staging Layer
        |
        v
Enterprise Data Warehouse
        |
        v
  Semantic Model
        |
        v
Power BI / Microsoft Fabric
```

## Repository Structure

```text
docs/          Architecture, design documents, ADRs, and diagrams
database/      SQL Server database objects and initialization scripts
etl/           ETL logic and orchestration assets
tests/         Data quality and validation tests
powerbi/       Power BI semantic models and reports
azure/         Azure Data Factory and cloud resources
fabric/        Microsoft Fabric implementation
sample-data/   Controlled sample datasets when required
```

## Project Roadmap

* `v0.1.0` — Repository foundation
* `v0.2.0` — Database initialization
* `v0.3.0` — Dimensions
* `v0.4.0` — Fact tables
* `v0.5.0` — ETL processes
* `v0.6.0` — Power BI
* `v0.7.0` — Azure Data Factory
* `v0.8.0` — Microsoft Fabric
* `v1.0.0` — Completed portfolio solution

## License

This project is licensed under the MIT License.
