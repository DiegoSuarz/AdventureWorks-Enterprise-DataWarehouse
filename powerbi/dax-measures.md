# DAX Measure Catalog

## 1. Scope

This catalog records the ten measures used in the guided implementation.
It is a documented reference, not an automated export from the PBIX.

Home table: _Measures.
Each definition below is a separate measure, not a single executable script.

## 2. Sales Amounts

### Gross Sales

Sales value before line discounts. Excludes tax and freight.

```dax
Gross Sales =
SUM(FactSales[GrossAmount])
```

### Discount Amount

Total line discount amount.

```dax
Discount Amount =
SUM(FactSales[DiscountAmount])
```

### Net Sales

Sales value after line discounts. Excludes tax and freight.

```dax
Net Sales =
SUM(FactSales[NetSalesAmount])
```

## 3. Volume

### Sales Order Lines

Number of fact rows in the current filter context.

```dax
Sales Order Lines =
COUNTROWS(FactSales)
```

### Sales Orders

Distinct orders represented by the selected fact rows.

```dax
Sales Orders =
DISTINCTCOUNT(FactSales[SalesOrderID])
```

An order can contain products from multiple categories. Do not sum
category-level distinct order counts to obtain the overall order count.

### Units Sold

Total quantity across the selected order lines.

```dax
Units Sold =
SUM(FactSales[OrderQuantity])
```

## 4. Ratios

### Average Order Value

Net sales divided by distinct orders in the current filter context.

```dax
Average Order Value =
DIVIDE([Net Sales], [Sales Orders])
```

When filtered by product, the numerator includes only the selected products.
The denominator counts orders containing those selected fact rows.
The result is therefore selected-product net sales per represented order,
not the full basket value of those orders.

### Effective Discount Rate

Gross-sales-weighted discount rate.

```dax
Effective Discount Rate =
DIVIDE([Discount Amount], [Gross Sales])
```

This is not an arithmetic average of individual line discount rates.
DIVIDE returns BLANK when the denominator is zero or BLANK because
no alternative result is specified.

Format this measure as a percentage. Do not multiply its DAX result by 100.

## 5. Alternative Date Roles

### Net Sales by Ship Date

Uses the selected calendar period against ShipDateKey.

```dax
Net Sales by Ship Date =
CALCULATE(
    [Net Sales],
    USERELATIONSHIP(FactSales[ShipDateKey], DimDate[DateKey])
)
```

### Net Sales by Due Date

Uses the selected calendar period against DueDateKey.

```dax
Net Sales by Due Date =
CALCULATE(
    [Net Sales],
    USERELATIONSHIP(FactSales[DueDateKey], DimDate[DateKey])
)
```

CALCULATE evaluates a measure in a modified filter context.
USERELATIONSHIP selects an existing relationship for that calculation.

For these measures, the selected alternative date relationship takes
precedence over the active OrderDate relationship between the same tables.
It does not permanently change the model relationships.

Other filters, such as territory and customer, continue to apply.

## 6. Display Conventions

| Measures | Display |
|---|---|
| Sales Order Lines, Sales Orders, Units Sold | Integer with thousands separator |
| Sales amounts | Two decimals for analytical presentation |
| Average Order Value | Two decimals |
| Effective Discount Rate | Percentage with two decimals |
| Reconciliation amounts | Four decimals where needed to compare SQL |

Overview cards can abbreviate amounts to millions. Validation visuals
must show sufficient precision to detect the expected differences.

Display formatting does not change the underlying calculation.
No currency symbol is asserted by this catalog.

## 7. Recorded Filtered Validation

Context: Order Month 2014-03 and Territory Canada.

| Measure | Observed result |
|---|---:|
| Sales Order Lines | 1428 |
| Sales Orders | 314 |
| Units Sold | 3542 |
| Gross Sales | 892441.1185 |
| Discount Amount | 2711.5533 |
| Net Sales | 889729.5652 |
| Average Order Value, four decimals | 2833.5336 |
| Effective Discount Rate, percentage | 0.3038% |

Using the same calendar month and territory with alternative date roles:

| Date role | Net Sales |
|---|---:|
| Order Date | 889729.5652 |
| Ship Date | 474945.1172 |
| Due Date | 474334.0472 |

These totals differ because each date role selects a different set of
order lines. They are not expected to reconcile with one another.

## 8. Related Documentation

- [Report guide](README.md)
- [Semantic model](semantic-model.md)
