-- ====================================================================
-- PROJECT: E-Commerce Customer Segmentation via RFM Analysis
-- TECH: MySQL Workbench
-- PURPOSE: Data cleaning, transformation, and behavioral tiering
-- ====================================================================

-- 1. DATABASE SETUP & INITIALIZATION
CREATE DATABASE IF NOT EXISTS Retail_Analysis;
USE Retail_Analysis;

CREATE TABLE IF NOT EXISTS transactions (
    InvoiceNo VARCHAR(20),
    StockCode VARCHAR(20),
    Description VARCHAR(255),
    Quantity INT,
    InvoiceDate VARCHAR(50),
    UnitPrice DECIMAL(10, 2),
    CustomerID VARCHAR(50),
    Country VARCHAR(100)
);

-- Audit initial dataset profile (Total Rows: 541,909)
SELECT COUNT(*) FROM transactions;
DESCRIBE transactions;


-- 2. DATA CLEANING & TYPE TRANSFORMATION
SELECT InvoiceDate 
FROM transactions 
WHERE InvoiceDate IS NULL;

-- Safely disable strict update locks for parsing text timestamps
SET SQL_SAFE_UPDATES = 0;

UPDATE transactions 
SET InvoiceDate = STR_TO_DATE(InvoiceDate, "%d-%m-%Y %H:%i");

ALTER TABLE transactions 
MODIFY COLUMN InvoiceDate DATETIME;

-- Check baseline operational date parameters
SELECT 
    MIN(InvoiceDate) AS earliest_date,
    MAX(InvoiceDate) AS latest_date
FROM transactions;


-- 3. CORE RFM SEGMENTATION ENGINE (VIEW DESIGN)
CREATE OR REPLACE VIEW rfm_score_view AS
WITH rfm_base AS (
    -- Extract base aggregation filters per customer id
    SELECT 
        CustomerID,
        ABS(DATEDIFF('2010-12-10', MAX(InvoiceDate))) AS raw_recency,
        COUNT(DISTINCT InvoiceNo) AS raw_frequency,
        ROUND(SUM(Quantity * UnitPrice), 2) AS raw_monetory
    FROM transactions
    WHERE CustomerID IS NOT NULL
      AND CustomerID != " "
      AND UnitPrice > 0
      AND Quantity > 0
    GROUP BY CustomerID
),

rfm_tiles AS (
    -- Distribute metrics across uniform NTILE quintile scales (1-5)
    SELECT 
        CustomerID,
        raw_recency,
        raw_frequency,
        raw_monetory,
        NTILE(5) OVER (ORDER BY raw_recency DESC) AS r_score,
        NTILE(5) OVER (ORDER BY raw_frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY raw_monetory ASC) AS m_score
    FROM rfm_base
)

-- Concatenate distinct numerical scoring layers into an evaluation string
SELECT 
    CustomerID,
    raw_recency,
    raw_frequency,
    raw_monetory,
    r_score,
    f_score,
    m_score,
    CONCAT(r_score, f_score, m_score) AS rfm_cell
FROM rfm_tiles;


-- 4. FINAL PRODUCTION REPORT VIEW (MARKETING CLASSIFICATIONS)
CREATE OR REPLACE VIEW rfm AS
SELECT 
    CustomerID,
    raw_recency,
    raw_frequency,
    raw_monetory,
    r_score,
    f_score,
    m_score,
    rfm_cell,
    CASE 
        -- Champions: Bought recently, buy frequently, spend heavy amounts
        WHEN rfm_cell IN ('555', '554', '545', '544', '455', '454', '445') THEN 'Champions'
        
        -- Loyal Customers: Consistent interaction history across moderate windows
        WHEN rfm_cell IN ('543', '443', '434', '344', '343', '334', '355', '354') THEN 'Loyal Customers'
        
        -- Potential Loyalists: High initial frequency metrics but recent accounts
        WHEN rfm_cell IN ('553', '552', '551', '542', '541', '452', '451', '442', '441') THEN 'Potential Loyalists'
        
        -- New Customers: Fresh interactions presenting low historical frequencies
        WHEN rfm_cell IN ('511', '512', '521', '522', '412', '411', '421', '422') THEN 'New Customers'
        
        -- Promising / Needs Attention: Mid-tier volume profiles sliding into warning tracks
        WHEN rfm_cell IN ('533', '532', '531', '433', '432', '431', '333', '332', '323', '331', '322', '321') THEN 'Needs Attention'
        
        -- At Risk / Can't Lose: Heavy historic volume but completely dark long-term
        WHEN rfm_cell IN ('255', '254', '245', '244', '253', '252', '243', '242', '235', '234', '225', '224', '155', '154', '145', '144') THEN 'At Risk / Cannot Lose'
        
        -- Hibernating: Low total interaction counts trailing off over historical spans
        WHEN rfm_cell IN ('311', '312', '313', '321', '212', '211', '223', '222', '221', '232', '233', '213') THEN 'Hibernating'
        
        -- Lost: Lowest performance flags across every individual calculation layer
        ELSE 'Lost'
    END AS customer_segment
FROM rfm_score_view;

