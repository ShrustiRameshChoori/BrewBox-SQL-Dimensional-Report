-- =====================================================
-- schema.sql  |  BrewBox Coffee Roasters - Star Schema
-- Engine: MySQL 8.0+   (CTEs + window functions needed)
-- =====================================================
DROP DATABASE IF EXISTS brewbox_dw;
CREATE DATABASE brewbox_dw;
USE brewbox_dw;

-- ---------- DIMENSION TABLES ----------
CREATE TABLE dim_date (
    date_key      INT          PRIMARY KEY,          -- YYYYMMDD (smart key)
    full_date     DATE         NOT NULL UNIQUE,
    year_num      SMALLINT     NOT NULL,
    quarter_num   TINYINT      NOT NULL,
    month_num     TINYINT      NOT NULL,
    month_name    VARCHAR(12)  NOT NULL,
    day_of_month  TINYINT      NOT NULL,
    day_name      VARCHAR(12)  NOT NULL,
    is_weekend    TINYINT      NOT NULL DEFAULT 0
);

CREATE TABLE dim_product (
    product_key   INT          PRIMARY KEY,
    product_id    VARCHAR(10)  NOT NULL UNIQUE,      -- business key
    product_name  VARCHAR(60)  NOT NULL,
    category      VARCHAR(30)  NOT NULL,
    subcategory   VARCHAR(30)  NOT NULL,
    list_price    DECIMAL(10,2) NOT NULL
);

CREATE TABLE dim_customer (
    customer_key  INT          PRIMARY KEY,
    customer_id   VARCHAR(10)  NOT NULL UNIQUE,
    customer_name VARCHAR(60)  NOT NULL,
    segment       VARCHAR(20)  NOT NULL,             -- Corporate / Cafe / Individual
    city          VARCHAR(30)  NOT NULL
);

CREATE TABLE dim_store (
    store_key     INT          PRIMARY KEY,
    store_id      VARCHAR(10)  NOT NULL UNIQUE,
    store_name    VARCHAR(40)  NOT NULL,
    region        VARCHAR(20)  NOT NULL,
    city          VARCHAR(30)  NOT NULL,
    state         VARCHAR(30)  NOT NULL
);

-- ---------- FACT TABLE ----------
CREATE TABLE fact_sales (
    sales_key        INT           PRIMARY KEY,
    date_key         INT           NOT NULL,
    product_key      INT           NOT NULL,
    customer_key     INT           NOT NULL,
    store_key        INT           NOT NULL,
    order_id         VARCHAR(15)   NOT NULL,
    quantity         INT           NOT NULL,
    unit_price       DECIMAL(10,2) NOT NULL,
    discount_amount  DECIMAL(10,2) NOT NULL DEFAULT 0,
    total_amount     DECIMAL(12,2) NOT NULL,
    CONSTRAINT chk_qty   CHECK (quantity > 0),
    CONSTRAINT chk_total CHECK (total_amount >= 0),
    CONSTRAINT fk_fact_date     FOREIGN KEY (date_key)     REFERENCES dim_date(date_key),
    CONSTRAINT fk_fact_product  FOREIGN KEY (product_key)  REFERENCES dim_product(product_key),
    CONSTRAINT fk_fact_customer FOREIGN KEY (customer_key) REFERENCES dim_customer(customer_key),
    CONSTRAINT fk_fact_store    FOREIGN KEY (store_key)    REFERENCES dim_store(store_key)
);

-- ---------- INDEXES ON FOREIGN KEYS ----------
CREATE INDEX idx_fact_date     ON fact_sales(date_key);
CREATE INDEX idx_fact_product  ON fact_sales(product_key);
CREATE INDEX idx_fact_customer ON fact_sales(customer_key);
CREATE INDEX idx_fact_store    ON fact_sales(store_key);
