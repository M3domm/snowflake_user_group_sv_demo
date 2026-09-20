/* ============================================================================
   Snowflake Semantic Views
   ============================================================================
   What this script builds, end to end:
     1. A role hierarchy following Snowflake's access-control best practices
        (USERADMIN / SECURITYADMIN / SYSADMIN, custom functional roles rolled
        up under SYSADMIN, ACCOUNTADMIN untouched after initial role grants).
     2. A fact table and three dimensions, loaded with realistic dummy data
        (6 regions, 60 products, 500 customers, 20,000 sales line items).
     3. A Semantic View on top of those tables with table/column comments,
        synonyms, sample values / enums, metrics, a derived metric, and a
        verified query.
     4. Row Access Policy (RLS) on the fact table and Column-level masking
        (CLS) on the customer dimension, applied to the underlying tables, 
        never on the semantic view itself, because semantic views don't support policies directly.
     5. Three consumer roles that only ever get SELECT on the semantic view
        (never on the base tables), to show that Cortex Analyst / BI queries
        against the semantic view still inherit RLS/CLS from below.
   ============================================================================ */


/* ============================================================================
   PART 1 — ROLES
   ============================================================================ */

USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS SVDEMO_ENGINEER_ROLE
  COMMENT = 'Owns the demo database/schema objects: tables, dummy data, and the semantic view.';

CREATE ROLE IF NOT EXISTS SVDEMO_GOVERNANCE_ROLE
  COMMENT = 'Owns and maintains the row access policy and masking policies (segregated from the object owner).';

CREATE ROLE IF NOT EXISTS SVDEMO_ANALYST_EMEA_ROLE
  COMMENT = 'Consumer role. Sees EMEA rows only (RLS) and masked customer email/phone (CLS).';

CREATE ROLE IF NOT EXISTS SVDEMO_ANALYST_AMER_ROLE
  COMMENT = 'Consumer role. Sees AMER rows only (RLS) and masked customer email/phone (CLS).';

CREATE ROLE IF NOT EXISTS SVDEMO_LEADER_ROLE
  COMMENT = 'Consumer role. Sees all regions and unmasked customer email/phone.';

-- Hand the new roles to SECURITYADMIN so it can build the hierarchy and grant privileges.
GRANT ROLE SVDEMO_ENGINEER_ROLE     TO ROLE SECURITYADMIN;
GRANT ROLE SVDEMO_GOVERNANCE_ROLE   TO ROLE SECURITYADMIN;
GRANT ROLE SVDEMO_ANALYST_EMEA_ROLE TO ROLE SECURITYADMIN;
GRANT ROLE SVDEMO_ANALYST_AMER_ROLE TO ROLE SECURITYADMIN;
GRANT ROLE SVDEMO_LEADER_ROLE       TO ROLE SECURITYADMIN;

USE ROLE SECURITYADMIN;

GRANT ROLE SVDEMO_ENGINEER_ROLE     TO ROLE SYSADMIN;
GRANT ROLE SVDEMO_GOVERNANCE_ROLE   TO ROLE SYSADMIN;
GRANT ROLE SVDEMO_ANALYST_EMEA_ROLE TO ROLE SYSADMIN;
GRANT ROLE SVDEMO_ANALYST_AMER_ROLE TO ROLE SYSADMIN;
GRANT ROLE SVDEMO_LEADER_ROLE       TO ROLE SYSADMIN;

-- Run SELECT CURRENT_USER(); once and replace <YOUR_USERNAME> below with the literal result.
GRANT ROLE SVDEMO_ENGINEER_ROLE     TO USER <YOUR_USERNAME>;
GRANT ROLE SVDEMO_GOVERNANCE_ROLE   TO USER <YOUR_USERNAME>;
GRANT ROLE SVDEMO_ANALYST_EMEA_ROLE TO USER <YOUR_USERNAME>;
GRANT ROLE SVDEMO_ANALYST_AMER_ROLE TO USER <YOUR_USERNAME>;
GRANT ROLE SVDEMO_LEADER_ROLE       TO USER <YOUR_USERNAME>;



/* ============================================================================
   PART 2 — WAREHOUSE, DATABASE, SCHEMA
   ============================================================================ */

USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS SVDEMO_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND   = 60
  AUTO_RESUME    = TRUE
  INITIALLY_SUSPENDED = TRUE
  ;

CREATE DATABASE IF NOT EXISTS SVDEMO_DB;

CREATE SCHEMA IF NOT EXISTS SVDEMO_DB.SALES;


GRANT USAGE ON WAREHOUSE SVDEMO_WH TO ROLE SVDEMO_ENGINEER_ROLE;
GRANT USAGE ON WAREHOUSE SVDEMO_WH TO ROLE SVDEMO_GOVERNANCE_ROLE;
GRANT USAGE ON WAREHOUSE SVDEMO_WH TO ROLE SVDEMO_ANALYST_EMEA_ROLE;
GRANT USAGE ON WAREHOUSE SVDEMO_WH TO ROLE SVDEMO_ANALYST_AMER_ROLE;
GRANT USAGE ON WAREHOUSE SVDEMO_WH TO ROLE SVDEMO_LEADER_ROLE;

GRANT USAGE ON DATABASE SVDEMO_DB TO ROLE SVDEMO_ENGINEER_ROLE;
GRANT USAGE ON DATABASE SVDEMO_DB TO ROLE SVDEMO_GOVERNANCE_ROLE;
GRANT USAGE ON DATABASE SVDEMO_DB TO ROLE SVDEMO_ANALYST_EMEA_ROLE;
GRANT USAGE ON DATABASE SVDEMO_DB TO ROLE SVDEMO_ANALYST_AMER_ROLE;
GRANT USAGE ON DATABASE SVDEMO_DB TO ROLE SVDEMO_LEADER_ROLE;

GRANT USAGE ON SCHEMA SVDEMO_DB.SALES TO ROLE SVDEMO_ENGINEER_ROLE;
GRANT USAGE ON SCHEMA SVDEMO_DB.SALES TO ROLE SVDEMO_GOVERNANCE_ROLE;
GRANT USAGE ON SCHEMA SVDEMO_DB.SALES TO ROLE SVDEMO_ANALYST_EMEA_ROLE;
GRANT USAGE ON SCHEMA SVDEMO_DB.SALES TO ROLE SVDEMO_ANALYST_AMER_ROLE;
GRANT USAGE ON SCHEMA SVDEMO_DB.SALES TO ROLE SVDEMO_LEADER_ROLE;


GRANT CREATE TABLE, CREATE VIEW, CREATE SEMANTIC VIEW
  ON SCHEMA SVDEMO_DB.SALES TO ROLE SVDEMO_ENGINEER_ROLE;

GRANT CREATE TABLE, CREATE ROW ACCESS POLICY, CREATE MASKING POLICY
  ON SCHEMA SVDEMO_DB.SALES TO ROLE SVDEMO_GOVERNANCE_ROLE;


/* ============================================================================
   PART 3 — FACT TABLE + THREE DIMENSIONS, WITH DUMMY DATA
   Owned by SVDEMO_ENGINEER_ROLE. Star schema: FCT_SALES joins to DIM_CUSTOMER,
   DIM_PRODUCT, and DIM_REGION: a simple, single-domain model
   ============================================================================ */

USE ROLE SVDEMO_ENGINEER_ROLE;
USE WAREHOUSE SVDEMO_WH;
USE DATABASE SVDEMO_DB;
USE SCHEMA SALES;

-- ---------------------------------------------------------------------------
-- DIM_REGION — 6 rows
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_REGION (
  REGION_ID             NUMBER(4,0)   NOT NULL,
  REGION_NAME           VARCHAR(20)   NOT NULL,
  REGION_MANAGER_EMAIL  VARCHAR(150)
)
COMMENT = 'Sales regions. Small reference dimension used both for reporting and to scope row access.';

INSERT INTO DIM_REGION (REGION_ID, REGION_NAME, REGION_MANAGER_EMAIL) VALUES
  (1, 'EMEA',  'emea.lead@example.com'),
  (2, 'AMER',  'amer.lead@example.com'),
  (3, 'APAC',  'apac.lead@example.com'),
  (4, 'LATAM', 'latam.lead@example.com'),
  (5, 'MEA',   'mea.lead@example.com'),
  (6, 'ANZ',   'anz.lead@example.com');

-- ---------------------------------------------------------------------------
-- DIM_PRODUCT — 60 rows
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_PRODUCT (
  PRODUCT_ID        NUMBER(10,0)    NOT NULL,
  PRODUCT_NAME       VARCHAR(100)   NOT NULL,
  CATEGORY           VARCHAR(30)    NOT NULL,
  SUBCATEGORY        VARCHAR(30)    NOT NULL,
  UNIT_COST          NUMBER(10,2)   NOT NULL,
  BASE_UNIT_PRICE    NUMBER(10,2)   NOT NULL
)
COMMENT = 'Product catalog: one row per SKU, with category/subcategory, unit cost, and list price.';

INSERT INTO DIM_PRODUCT (PRODUCT_ID, PRODUCT_NAME, CATEGORY, SUBCATEGORY, UNIT_COST, BASE_UNIT_PRICE)
WITH cat AS (
  SELECT ROW_NUMBER() OVER (ORDER BY 1) - 1 AS cat_id, COLUMN1 AS category, COLUMN2 AS subcategory
  FROM VALUES
    ('Footwear',    'Running'),
    ('Footwear',    'Training'),
    ('Footwear',    'Casual'),
    ('Apparel',     'Outerwear'),
    ('Apparel',     'Tops'),
    ('Apparel',     'Bottoms'),
    ('Accessories', 'Bags'),
    ('Accessories', 'Headwear'),
    ('Accessories', 'Eyewear'),
    ('Equipment',   'Racquets'),
    ('Equipment',   'Balls'),
    ('Equipment',   'Nets')
),
g AS (
  SELECT SEQ4() AS rn FROM TABLE(GENERATOR(ROWCOUNT => 60))
),
base AS (
  SELECT
    g.rn + 1                                        AS product_id,
    c.subcategory || ' Pro ' || TO_CHAR(g.rn + 1)    AS product_name,
    c.category,
    c.subcategory,
    ROUND(UNIFORM(8, 60, RANDOM()), 2)               AS unit_cost
  FROM g
  JOIN cat c ON c.cat_id = MOD(g.rn, 12)
)
SELECT
  product_id,
  product_name,
  category,
  subcategory,
  unit_cost,
  ROUND(unit_cost * UNIFORM(140, 220, RANDOM()) / 100.0, 2) AS base_unit_price
FROM base;

-- ---------------------------------------------------------------------------
-- DIM_CUSTOMER — 500 rows. EMAIL/PHONE will be masked later (CLS).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_CUSTOMER (
  CUSTOMER_ID        NUMBER(10,0)    NOT NULL,
  CUSTOMER_NAME      VARCHAR(100)    NOT NULL,
  EMAIL              VARCHAR(150),
  PHONE              VARCHAR(20),
  CUSTOMER_SEGMENT   VARCHAR(20),
  COUNTRY            VARCHAR(50),
  SIGNUP_DATE        DATE
)
COMMENT = 'Customers: one row per account, with contact details, segment, and country. EMAIL and PHONE carry column masking policies.';

INSERT INTO DIM_CUSTOMER (CUSTOMER_ID, CUSTOMER_NAME, EMAIL, PHONE, CUSTOMER_SEGMENT, COUNTRY, SIGNUP_DATE)
WITH first_names AS (
  SELECT ROW_NUMBER() OVER (ORDER BY 1) - 1 AS idx, COLUMN1 AS fname
  FROM VALUES
    ('Ava'),('Liam'),('Noah'),('Emma'),('Sofia'),('Lucas'),('Mia'),('Ethan'),('Zoe'),('Leon'),
    ('Nina'),('Omar'),('Layla'),('Marco'),('Elena'),('Jonas'),('Priya'),('Kenji'),('Fatima'),
    ('Diego'),('Ingrid'),('Youssef'),('Chiara'),('Hana'),('Viktor')
),
last_names AS (
  SELECT ROW_NUMBER() OVER (ORDER BY 1) - 1 AS idx, COLUMN1 AS lname
  FROM VALUES
    ('Novak'),('Kramer'),('Silva'),('Nguyen'),('Kovac'),('Rossi'),('Muller'),('Andersen'),
    ('Haddad'),('Petrov'),('Nakamura'),('Costa'),('Meyer'),('Khan'),('Larsen'),('Fischer'),
    ('Popov'),('Dubois'),('Abara'),('Lindqvist'),('Weber'),('Santos'),('Horvat'),('Berger'),
    ('Toure'),('Jansen'),('Osei'),('Ricci'),('Bauer'),('Salem')
),
countries AS (
  SELECT ROW_NUMBER() OVER (ORDER BY 1) - 1 AS idx, COLUMN1 AS country
  FROM VALUES
    ('Slovenia'),('Germany'),('United States'),('Brazil'),('Japan'),
    ('United Arab Emirates'),('South Africa'),('Australia'),('Croatia'),('France')
),
segments AS (
  SELECT ROW_NUMBER() OVER (ORDER BY 1) - 1 AS idx, COLUMN1 AS seg
  FROM VALUES ('CONSUMER'),('SMB'),('ENTERPRISE')
),
g AS (
  SELECT SEQ4() AS rn FROM TABLE(GENERATOR(ROWCOUNT => 500))
)
SELECT
  g.rn + 1                                                                       AS customer_id,
  f.fname || ' ' || l.lname                                                      AS customer_name,
  LOWER(f.fname) || '.' || LOWER(l.lname) || (g.rn + 1) || '@example.com'        AS email,
  '+386-' || LPAD(UNIFORM(100, 999, RANDOM())::VARCHAR, 3, '0')
          || '-' || LPAD(UNIFORM(1000, 9999, RANDOM())::VARCHAR, 4, '0')         AS phone,
  s.seg                                                                          AS customer_segment,
  c.country                                                                      AS country,
  DATEADD(day, -UNIFORM(0, 1460, RANDOM()), CURRENT_DATE())                      AS signup_date
FROM g
JOIN first_names f ON f.idx = MOD(g.rn, 25)
JOIN last_names  l ON l.idx = MOD(g.rn * 7 + 3, 30)
JOIN countries   c ON c.idx = MOD(g.rn * 3 + 1, 10)
JOIN segments    s ON s.idx = MOD(g.rn, 3);

-- ---------------------------------------------------------------------------
-- FCT_SALES — 20,000 rows. Grain: one row per line-item sale.
-- REGION_ID is the column RLS will be applied to.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE FCT_SALES (
  SALE_ID        NUMBER(38,0)   NOT NULL,
  SALE_DATE      DATE           NOT NULL,
  CUSTOMER_ID    NUMBER(10,0)   NOT NULL,
  PRODUCT_ID     NUMBER(10,0)   NOT NULL,
  REGION_ID      NUMBER(4,0)    NOT NULL,
  QUANTITY       NUMBER(6,0)    NOT NULL,
  UNIT_PRICE     NUMBER(10,2)   NOT NULL,
  DISCOUNT_PCT   NUMBER(5,2)    NOT NULL,
  SALES_AMOUNT   NUMBER(14,2)   NOT NULL,
  COST_AMOUNT    NUMBER(14,2)   NOT NULL
)
COMMENT = 'Sales fact table. Grain: one row per line-item sale. Row access policy scopes rows by REGION_ID.';

INSERT INTO FCT_SALES (SALE_ID, SALE_DATE, CUSTOMER_ID, PRODUCT_ID, REGION_ID, QUANTITY, UNIT_PRICE, DISCOUNT_PCT, SALES_AMOUNT, COST_AMOUNT)
WITH base AS (
  SELECT
    SEQ4() + 1                                                        AS sale_id,
    DATEADD(day, UNIFORM(0, 729, RANDOM()), '2024-01-01'::DATE)       AS sale_date,
    UNIFORM(1, 500, RANDOM())                                         AS customer_id,
    UNIFORM(1, 60, RANDOM())                                          AS product_id,
    UNIFORM(1, 6, RANDOM())                                           AS region_id,
    UNIFORM(1, 15, RANDOM())                                          AS quantity,
    UNIFORM(70, 130, RANDOM()) / 100.0                                AS price_variance,
    UNIFORM(0, 25, RANDOM())                                          AS discount_pct
  FROM TABLE(GENERATOR(ROWCOUNT => 20000))
)
SELECT
  b.sale_id,
  b.sale_date,
  b.customer_id,
  b.product_id,
  b.region_id,
  b.quantity,
  ROUND(p.base_unit_price * b.price_variance, 2)                                                               AS unit_price,
  b.discount_pct,
  ROUND(b.quantity * ROUND(p.base_unit_price * b.price_variance, 2) * (1 - b.discount_pct / 100.0), 2)         AS sales_amount,
  ROUND(b.quantity * p.unit_cost, 2)                                                                           AS cost_amount
FROM base b
JOIN DIM_PRODUCT p ON p.product_id = b.product_id;

-- Sanity checks — row counts should read 6 / 60 / 500 / 20000.
SELECT 'DIM_REGION' AS tbl, COUNT(*) AS row_count FROM DIM_REGION
UNION ALL SELECT 'DIM_PRODUCT', COUNT(*) FROM DIM_PRODUCT
UNION ALL SELECT 'DIM_CUSTOMER', COUNT(*) FROM DIM_CUSTOMER
UNION ALL SELECT 'FCT_SALES', COUNT(*) FROM FCT_SALES;


/* ============================================================================
   PART 4 — SEMANTIC VIEW
   Owned by SVDEMO_ENGINEER_ROLE (creator needs CREATE SEMANTIC VIEW on the
   schema plus SELECT on every underlying table, both already granted/owned
   above).
   ============================================================================ */

CREATE OR REPLACE SEMANTIC VIEW SVDEMO_DB.SALES.SV_SALES_PERFORMANCE

  TABLES (
    sales AS FCT_SALES
      PRIMARY KEY (SALE_ID)
      WITH SYNONYMS ('transactions', 'orders', 'sales transactions')
      COMMENT = 'Grain: one row per line-item sale. Quantities, prices, discounts, and the computed sales/cost amounts for every transaction, across all regions.',
    customers AS DIM_CUSTOMER
      PRIMARY KEY (CUSTOMER_ID)
      WITH SYNONYMS ('clients', 'buyers', 'accounts')
      COMMENT = 'One row per customer: name, contact details, segment, and country. Email and phone are protected by column masking policies on the underlying table.',
    products AS DIM_PRODUCT
      PRIMARY KEY (PRODUCT_ID)
      WITH SYNONYMS ('items', 'SKUs', 'catalog')
      COMMENT = 'Product catalog: one row per SKU, with category, subcategory, unit cost, and list price.',
    regions AS DIM_REGION
      PRIMARY KEY (REGION_ID)
      WITH SYNONYMS ('territories', 'sales regions')
      COMMENT = 'Sales regions used to segment revenue and, on the fact table, to scope row-level access for regional analyst roles.'
  )

  RELATIONSHIPS (
    sales_to_customers AS sales (CUSTOMER_ID) REFERENCES customers,
    sales_to_products  AS sales (PRODUCT_ID) REFERENCES products,
    sales_to_regions   AS sales (REGION_ID) REFERENCES regions
  )

  FACTS (
    sales.quantity AS QUANTITY
      COMMENT = 'Number of units sold in this line item.'
      SAMPLE_VALUES ('1', '3', '8', '15'),
    sales.unit_price AS UNIT_PRICE
      COMMENT = 'List price per unit at the time of sale, in USD, before discount.'
      SAMPLE_VALUES ('24.50', '89.00', '142.75'),
    sales.discount_pct AS DISCOUNT_PCT
      COMMENT = 'Discount percentage applied to this line item, ranging from 0 to 25.'
      SAMPLE_VALUES ('0', '10', '25'),
    sales.sales_amount AS SALES_AMOUNT
      COMMENT = 'Net revenue for this line item after discount: quantity * unit_price * (1 - discount_pct / 100).'
      SAMPLE_VALUES ('45.90', '712.00', '2140.35'),
    sales.cost_amount AS COST_AMOUNT
      COMMENT = 'Total cost of goods sold for this line item: quantity * product unit cost.'
      SAMPLE_VALUES ('30.00', '410.00', '1500.00')
  )

  DIMENSIONS (
    sales.sale_date AS SALE_DATE
      COMMENT = 'Calendar date the sale was transacted.'
      SAMPLE_VALUES ('2024-03-14', '2025-07-02'),
    sales.sale_year AS YEAR(SALE_DATE)
      COMMENT = 'Calendar year the sale was transacted.'
      SAMPLE_VALUES ('2024', '2025')
      IS_ENUM,
    sales.sale_month AS DATE_TRUNC('month', SALE_DATE)
      COMMENT = 'First day of the calendar month the sale was transacted; use this to group sales by month.',
    customers.customer_name AS CUSTOMER_NAME
      WITH SYNONYMS ('client name', 'buyer name')
      COMMENT = 'Full name of the customer who made the purchase.',
    customers.email AS EMAIL
      COMMENT = 'Customer email address. Masked for every role except SVDEMO_LEADER_ROLE by a masking policy on the underlying table — the mask is enforced even when queried through this semantic view.',
    customers.phone AS PHONE
      COMMENT = 'Customer phone number. Masked for every role except SVDEMO_LEADER_ROLE by a masking policy on the underlying table.',
    customers.customer_segment AS CUSTOMER_SEGMENT
      WITH SYNONYMS ('customer tier', 'account type')
      COMMENT = 'Business segment of the customer.'
      SAMPLE_VALUES ('CONSUMER', 'SMB', 'ENTERPRISE')
      IS_ENUM,
    customers.country AS COUNTRY
      COMMENT = 'Country of residence of the customer.',
    products.product_name AS PRODUCT_NAME
      COMMENT = 'Marketing name of the product.',
    products.category AS CATEGORY
      WITH SYNONYMS ('product category', 'product line')
      COMMENT = 'Top-level product category.'
      SAMPLE_VALUES ('Footwear', 'Apparel', 'Accessories', 'Equipment')
      IS_ENUM,
    products.subcategory AS SUBCATEGORY
      COMMENT = 'Second-level product grouping within a category.',
    regions.region_name AS REGION_NAME
      WITH SYNONYMS ('territory', 'sales region')
      COMMENT = 'Sales region in which the transaction was recorded. Older internal reports also call this the "territory code."'
      SAMPLE_VALUES ('EMEA', 'AMER', 'APAC', 'LATAM', 'MEA', 'ANZ')
      IS_ENUM
  )

  METRICS (
    sales.total_sales_amount AS SUM(sales.sales_amount)
      WITH SYNONYMS ('total revenue', 'net sales')
      COMMENT = 'Sum of net sales revenue after discount, across the selected rows.',
    sales.total_cost_amount AS SUM(sales.cost_amount)
      COMMENT = 'Sum of cost of goods sold across the selected rows.',
    sales.total_units_sold AS SUM(sales.quantity)
      WITH SYNONYMS ('units sold', 'volume')
      COMMENT = 'Total number of units sold across the selected rows.',
    sales.order_count AS COUNT(SALE_ID)
      WITH SYNONYMS ('number of orders', 'transaction count')
      COMMENT = 'Count of distinct line-item transactions across the selected rows.',
    sales.average_order_value AS AVG(sales.sales_amount)
      COMMENT = 'Average net sales amount per line-item transaction.',
    gross_margin_amount AS sales.total_sales_amount - sales.total_cost_amount
      WITH SYNONYMS ('gross profit')
      COMMENT = 'Derived metric: total sales revenue minus total cost of goods sold.',
    gross_margin_pct AS DIV0(gross_margin_amount, sales.total_sales_amount) * 100
      COMMENT = 'Derived metric: gross margin amount as a percentage of total sales revenue.'
  )

  COMMENT = 'Sales performance semantic view: line-item sales joined to customer, product, and region dimensions. Row access policy scopes rows by region; masking policies protect customer email and phone. Both are defined on the underlying tables and are enforced automatically when this view is queried.'

  AI_VERIFIED_QUERIES (
    total_sales_by_region_2024 AS (
      QUESTION 'What was the total sales amount by region in 2024?'
      VERIFIED_AT 1767225600
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = matic)'
      SQL 'SELECT
             r.region_name,
             SUM(s.sales_amount) AS total_sales_amount
           FROM fct_sales AS s
           JOIN dim_region AS r ON s.region_id = r.region_id
           WHERE YEAR(s.sale_date) = 2024
           GROUP BY r.region_name
           ORDER BY total_sales_amount DESC'
    )
  );

-- Explore the object you just built.
SHOW SEMANTIC VIEWS IN SCHEMA SVDEMO_DB.SALES;
DESCRIBE SEMANTIC VIEW SVDEMO_DB.SALES.SV_SALES_PERFORMANCE;
SHOW SEMANTIC METRICS IN SVDEMO_DB.SALES.SV_SALES_PERFORMANCE;

-- A quick functional check before RLS/CLS go on: everyone will see all regions and unmasked contact details at this point, because SVDEMO_ENGINEER_ROLE owns the tables outright and no policies exist yet.
SELECT * FROM SEMANTIC_VIEW(
  SVDEMO_DB.SALES.SV_SALES_PERFORMANCE
  DIMENSIONS regions.region_name
  METRICS sales.total_sales_amount, sales.order_count
)
ORDER BY total_sales_amount DESC;


/* ============================================================================
   PART 5 — GRANT SELECT ON THE SEMANTIC VIEW ONLY (owner's rights)
   Semantic views run with owner's rights: a role only needs SELECT on the
   semantic view object itself, exactly like a standard view. It does not
   need any privilege on FCT_SALES, DIM_CUSTOMER, DIM_PRODUCT, or DIM_REGION.
   Deliberately, the three consumer roles below get nothing on the base
   tables, which is the whole point of the next parts.
   ============================================================================ */

USE ROLE SECURITYADMIN;

GRANT SELECT ON SEMANTIC VIEW SVDEMO_DB.SALES.SV_SALES_PERFORMANCE TO ROLE SVDEMO_ANALYST_EMEA_ROLE;
GRANT SELECT ON SEMANTIC VIEW SVDEMO_DB.SALES.SV_SALES_PERFORMANCE TO ROLE SVDEMO_ANALYST_AMER_ROLE;
GRANT SELECT ON SEMANTIC VIEW SVDEMO_DB.SALES.SV_SALES_PERFORMANCE TO ROLE SVDEMO_LEADER_ROLE;

-- Proof: consumer roles hold SELECT on the semantic view...
SHOW GRANTS ON SEMANTIC VIEW SVDEMO_DB.SALES.SV_SALES_PERFORMANCE;
-- ...and nothing at all on the underlying fact table.
SHOW GRANTS ON TABLE SVDEMO_DB.SALES.FCT_SALES;


/* ============================================================================
   PART 6 — ROW ACCESS POLICY (RLS) ON THE FACT TABLE
   Governance role creates and owns the policy and its mapping table (a
   segregation-of-duties pattern: the object owner and the policy owner are
   different roles). It grants APPLY on the policy to the engineer role,
   which can then attach the policy to the table. This mirrors Snowflake's
   documented "hybrid governance" pattern for row access policies.
   ============================================================================ */

USE ROLE SVDEMO_GOVERNANCE_ROLE;
USE WAREHOUSE SVDEMO_WH;
USE DATABASE SVDEMO_DB;
USE SCHEMA SALES;

-- Mapping table: which role is allowed to see which region (by REGION_ID). SVDEMO_LEADER_ROLE deliberately has no row here, it's handled as a full-access exception in the policy body below.
CREATE OR REPLACE TABLE ROLE_REGION_MAP (
  ROLE_NAME    VARCHAR(100) NOT NULL,
  REGION_ID    NUMBER(4,0)  NOT NULL
)
COMMENT = 'Governance mapping table: which role may see which sales region (by REGION_ID). Read only by the row access policy, evaluated with the policy owner''s rights.';

INSERT INTO ROLE_REGION_MAP (ROLE_NAME, REGION_ID) VALUES
  ('SVDEMO_ANALYST_EMEA_ROLE', 1),  -- EMEA
  ('SVDEMO_ANALYST_AMER_ROLE', 2);  -- AMER

-- Row access policy: full access for the leader role, otherwise looked up directly via the mapping table — no dependency on DIM_REGION or any table SVDEMO_GOVERNANCE_ROLE doesn't itself own.
CREATE OR REPLACE ROW ACCESS POLICY RAP_SALES_BY_REGION
AS (REGION_ID_ARG NUMBER) RETURNS BOOLEAN ->
  CURRENT_ROLE() = 'SVDEMO_LEADER_ROLE'
  OR EXISTS (
       SELECT 1
       FROM ROLE_REGION_MAP m
       WHERE m.ROLE_NAME = CURRENT_ROLE()
         AND m.REGION_ID = REGION_ID_ARG
     )
COMMENT = 'Restricts FCT_SALES rows to the region(s) mapped to the querying role; SVDEMO_LEADER_ROLE sees every region.';

-- Governance role owns the policy, so it can grant APPLY on it directly to the table-owning role.
GRANT APPLY ON ROW ACCESS POLICY RAP_SALES_BY_REGION TO ROLE SVDEMO_ENGINEER_ROLE;

-- The table owner attaches the policy. (Needs OWNERSHIP on FCT_SALES, which it already has, plus the APPLY grant just given above.)
USE ROLE SVDEMO_ENGINEER_ROLE;

ALTER TABLE SVDEMO_DB.SALES.FCT_SALES
  ADD ROW ACCESS POLICY SVDEMO_DB.SALES.RAP_SALES_BY_REGION ON (REGION_ID);


/* ============================================================================
   PART 7 — COLUMN MASKING POLICIES (CLS) ON THE CUSTOMER DIMENSION
   Same governance pattern as Part 6: SVDEMO_GOVERNANCE_ROLE creates and owns
   the masking policies, grants APPLY to SVDEMO_ENGINEER_ROLE, which attaches
   them to DIM_CUSTOMER.EMAIL and DIM_CUSTOMER.PHONE.
   ============================================================================ */

USE ROLE SVDEMO_GOVERNANCE_ROLE;

CREATE OR REPLACE MASKING POLICY MSK_EMAIL
AS (VAL VARCHAR) RETURNS VARCHAR ->
  CASE
    WHEN CURRENT_ROLE() = 'SVDEMO_LEADER_ROLE' THEN VAL
    ELSE CONCAT('***MASKED***@', SPLIT_PART(VAL, '@', 2))
  END
COMMENT = 'Shows full email only to SVDEMO_LEADER_ROLE; masks the local part for every other role.';

CREATE OR REPLACE MASKING POLICY MSK_PHONE
AS (VAL VARCHAR) RETURNS VARCHAR ->
  CASE
    WHEN CURRENT_ROLE() = 'SVDEMO_LEADER_ROLE' THEN VAL
    ELSE CONCAT('***-***-', RIGHT(VAL, 4))
  END
COMMENT = 'Shows full phone number only to SVDEMO_LEADER_ROLE; masks all but the last 4 digits for every other role.';

GRANT APPLY ON MASKING POLICY MSK_EMAIL TO ROLE SVDEMO_ENGINEER_ROLE;
GRANT APPLY ON MASKING POLICY MSK_PHONE TO ROLE SVDEMO_ENGINEER_ROLE;

USE ROLE SVDEMO_ENGINEER_ROLE;

ALTER TABLE SVDEMO_DB.SALES.DIM_CUSTOMER MODIFY COLUMN EMAIL SET MASKING POLICY SVDEMO_DB.SALES.MSK_EMAIL;
ALTER TABLE SVDEMO_DB.SALES.DIM_CUSTOMER MODIFY COLUMN PHONE SET MASKING POLICY SVDEMO_DB.SALES.MSK_PHONE;


/* ============================================================================
   PART 8 — THE DEMO: same query, three roles, three governed answers
   No grants change from here on. Only the active role changes.
   ============================================================================ */

-- ---- As the EMEA analyst -----------------------------------------------
USE ROLE SVDEMO_ANALYST_EMEA_ROLE;
USE WAREHOUSE SVDEMO_WH;

-- Works: SELECT on the semantic view is all that's required.
SELECT * FROM SEMANTIC_VIEW(
  SVDEMO_DB.SALES.SV_SALES_PERFORMANCE
  DIMENSIONS regions.region_name, customers.customer_name, customers.email, customers.phone
  METRICS sales.total_sales_amount, sales.order_count
)
ORDER BY total_sales_amount DESC
LIMIT 20;
-- Expect: REGION_NAME is always EMEA (row access policy), and EMAIL/PHONE are masked (column masking policy) — even though this role never touched FCT_SALES or DIM_CUSTOMER directly.

-- Fails: no privilege on the base table at all. Uncomment to show live.
-- SELECT * FROM SVDEMO_DB.SALES.FCT_SALES LIMIT 10;

-- ---- As the AMER analyst -----------------------------------------------
USE ROLE SVDEMO_ANALYST_AMER_ROLE;

SELECT * FROM SEMANTIC_VIEW(
  SVDEMO_DB.SALES.SV_SALES_PERFORMANCE
  DIMENSIONS regions.region_name, customers.customer_name, customers.email, customers.phone
  METRICS sales.total_sales_amount, sales.order_count
)
ORDER BY total_sales_amount DESC
LIMIT 20;
-- Expect: REGION_NAME is always AMER; EMAIL/PHONE still masked.

-- ---- As the data leader --------------------------------------------------
USE ROLE SVDEMO_LEADER_ROLE;

SELECT * FROM SEMANTIC_VIEW(
  SVDEMO_DB.SALES.SV_SALES_PERFORMANCE
  DIMENSIONS regions.region_name, customers.customer_name, customers.email, customers.phone
  METRICS sales.total_sales_amount, sales.order_count
)
ORDER BY total_sales_amount DESC
LIMIT 20;
-- Expect: all 6 regions appear, and EMAIL/PHONE are shown in full.


/* ============================================================================
   PART 9 — Example Business Question for Cortex Analyst
   ============================================================================ */

-- 1. Which product category generates the most gross margin?
-- 2. How did sales trend month over month across 2024–2025?
-- 3. Which customer segment has the highest average order value?
-- 4. What are the top 10 products by units sold?
-- 5. How does gross margin percentage vary by region?
