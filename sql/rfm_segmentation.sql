const workbook = await FileAttachment("Online Retail.xlsx").xlsx();

const rows = workbook.sheet("Online Retail", {headers: true});

const db = await DuckDBClient.of({online_retail: rows});

FROM online_retail

SELECT
  CustomerID,
  COUNT(DISTINCT InvoiceNo) AS total_invoices,
  SUM(Quantity * UnitPrice) AS total_spend
FROM online_retail
WHERE CustomerID IS NOT NULL
  AND NOT isnan(CustomerID)
  AND CAST(InvoiceNo AS VARCHAR) NOT LIKE 'C%'
GROUP BY CustomerID
ORDER BY total_spend DESC
LIMIT 10

WITH cleaned_transactions AS (
    SELECT
        InvoiceNo,
        Quantity,
        InvoiceDate,
        UnitPrice,
        CustomerID,
        -- Calculate net line revenue
        CASE WHEN Quantity > 0 THEN Quantity * UnitPrice ELSE 0 END AS positive_revenue
    FROM online_retail
    WHERE CustomerID IS NOT NULL
      AND NOT isnan(CustomerID)
      AND CAST(InvoiceNo AS VARCHAR) NOT LIKE 'C%'
      AND UnitPrice > 0
),

customer_rfm_base AS (
    SELECT
        CAST(CustomerID AS VARCHAR) AS customer_id,
        MAX(InvoiceDate) AS last_purchase_date,
        -- Calculate Recency relative to dataset max date (2011-12-09)
        DATE '2011-12-10' - CAST(MAX(InvoiceDate) AS DATE) AS recency_days,
        COUNT(DISTINCT InvoiceNo) AS frequency_count,
        ROUND(SUM(positive_revenue), 2) AS monetary_value
    FROM cleaned_transactions
    GROUP BY CustomerID
),

customer_churn_segmentation AS (
    SELECT
        customer_id,
        last_purchase_date,
        recency_days,
        frequency_count,
        monetary_value,
        -- Churn Risk Flag: 1 if inactive > 90 days, else 0 (BR-01)
        CASE WHEN recency_days > 90 THEN 1 ELSE 0 END AS is_churned_risk,
        -- Monetary Decile ranking (BR-02)
        NTILE(10) OVER (ORDER BY monetary_value DESC) AS monetary_decile
    FROM customer_rfm_base
)

SELECT
    customer_id,
    last_purchase_date,
    recency_days,
    frequency_count,
    monetary_value,
    is_churned_risk,
    monetary_decile,
    CASE
        WHEN monetary_decile = 1 THEN 'Top 10% VIP'
        WHEN is_churned_risk = 1 THEN 'At-Risk / Dormant'
        ELSE 'Active Regular'
    END AS customer_segment
FROM customer_churn_segmentation
ORDER BY monetary_value DESC;

const downloadButton = display(Inputs.button("Download CSV", {
  reduce: () => {
    const csv = d3.csvFormat(Array.from(segments, (d) => ({
      ...d.toJSON(),
      last_purchase_date: new Date(d.last_purchase_date).toISOString()
    })));
    const url = URL.createObjectURL(new Blob([csv], {type: "text/csv"}));
    const a = document.createElement("a");
    a.href = url;
    a.download = "customer_segments.csv";
    a.click();
    URL.revokeObjectURL(url);
  }
}));
