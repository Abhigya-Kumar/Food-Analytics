/* =====================================================================
   ZOMATO SALES ANALYSIS - DATABASE SCHEMA
   =====================================================================
   3 tables: customers (dim), restaurants (dim), orders (fact)
   Compatible with MySQL 8+, PostgreSQL 12+, and SQLite (see notes).

   ER RELATIONSHIP
   ----------------
   customers (1) ----< orders (M) >---- (1) restaurants

   Run this file first, then load data/*.csv into the matching tables,
   then run 02_business_queries.sql for the analysis.
   ===================================================================== */

DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS restaurants;
DROP TABLE IF EXISTS customers;

-- ---------------------------------------------------------------------
-- DIMENSION: customers
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id         INT PRIMARY KEY,
    customer_name        VARCHAR(100)  NOT NULL,
    city                  VARCHAR(50)   NOT NULL,
    signup_date           DATE          NOT NULL,
    is_premium_member     VARCHAR(3)    NOT NULL   -- 'Yes' / 'No'  (Zomato Gold-style membership)
);

-- ---------------------------------------------------------------------
-- DIMENSION: restaurants
-- ---------------------------------------------------------------------
CREATE TABLE restaurants (
    restaurant_id        INT PRIMARY KEY,
    restaurant_name       VARCHAR(150)  NOT NULL,
    city                   VARCHAR(50)   NOT NULL,
    cuisine                VARCHAR(50)   NOT NULL,
    cost_for_two            INT           NOT NULL,  -- INR
    is_veg_only              VARCHAR(3)    NOT NULL, -- 'Yes' / 'No'
    avg_rating                 DECIMAL(2,1)  NOT NULL, -- platform-displayed rating, 1.0-5.0
    onboarded_year               INT           NOT NULL
);

-- ---------------------------------------------------------------------
-- FACT: orders
-- ---------------------------------------------------------------------
CREATE TABLE orders (
    order_id              INT PRIMARY KEY,
    customer_id           INT           NOT NULL,
    restaurant_id         INT           NOT NULL,
    order_datetime         DATETIME      NOT NULL,
    order_value              DECIMAL(10,2) NOT NULL,  -- pre-discount subtotal
    discount_amount            DECIMAL(10,2) NOT NULL,
    delivery_fee                 DECIMAL(10,2) NOT NULL,
    taxes                          DECIMAL(10,2) NOT NULL,
    total_amount                     DECIMAL(10,2) NOT NULL, -- final amount charged (0 if cancelled)
    payment_method                     VARCHAR(30)   NOT NULL,
    delivery_time_mins                   INT           NULL,  -- NULL if not delivered
    customer_rating                        DECIMAL(2,1)  NULL,  -- NULL if not rated / not delivered
    order_status                             VARCHAR(30)   NOT NULL,  -- Delivered / Cancelled by Customer / Cancelled by Restaurant

    CONSTRAINT fk_orders_customer   FOREIGN KEY (customer_id)   REFERENCES customers(customer_id),
    CONSTRAINT fk_orders_restaurant FOREIGN KEY (restaurant_id) REFERENCES restaurants(restaurant_id)
);

-- ---------------------------------------------------------------------
-- INDEXES  (speed up the joins/filters used throughout the analysis)
-- ---------------------------------------------------------------------
CREATE INDEX idx_orders_customer   ON orders(customer_id);
CREATE INDEX idx_orders_restaurant ON orders(restaurant_id);
CREATE INDEX idx_orders_datetime   ON orders(order_datetime);
CREATE INDEX idx_orders_status     ON orders(order_status);
CREATE INDEX idx_restaurants_city  ON restaurants(city);
CREATE INDEX idx_customers_city    ON customers(city);

/* ---------------------------------------------------------------------
   LOADING DATA
   -----------------------------------------------------------------
   MySQL:
     LOAD DATA LOCAL INFILE 'data/zomato_customers.csv'
       INTO TABLE customers FIELDS TERMINATED BY ',' ENCLOSED BY '"'
       LINES TERMINATED BY '\n' IGNORE 1 ROWS;
     -- repeat for restaurants, orders

   PostgreSQL:
     \copy customers   FROM 'data/zomato_customers.csv'   CSV HEADER;
     \copy restaurants FROM 'data/zomato_restaurants.csv' CSV HEADER;
     \copy orders      FROM 'data/zomato_orders.csv'      CSV HEADER;

   SQLite (via CLI):
     .mode csv
     .import --skip 1 data/zomato_customers.csv customers
     .import --skip 1 data/zomato_restaurants.csv restaurants
     .import --skip 1 data/zomato_orders.csv orders
   --------------------------------------------------------------------- */
