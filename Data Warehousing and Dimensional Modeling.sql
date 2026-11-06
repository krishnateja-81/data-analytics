
-- creating dimension tale for customer
CREATE OR REPLACE TABLE demo.dim_customer AS
SELECT 1 AS customer_key, 'C001' AS customer_id, 'Asha' AS name, 'Hyderabad' AS city UNION ALL
SELECT 2, 'C002', 'Ravi', 'Pune' UNION ALL
SELECT 3, 'C003', 'Meena', 'Chennai';


-- creating dimension tale for product
CREATE OR REPLACE TABLE demo.dim_product AS
SELECT 10 AS product_key, 'P10' AS product_id, 'Phone X' AS product_name, 'Electronics' AS category UNION ALL
SELECT 11, 'P11', 'Notebook', 'Stationery' UNION ALL
SELECT 12, 'P12', 'Earbuds', 'Electronics' UNION ALL
SELECT 13, 'P13', 'Pen', 'Stationery';

-- creating tale for dates for a year(2026)
CREATE OR REPLACE TABLE demo.dim_date AS
SELECT
  d AS date_key,
  EXTRACT(YEAR FROM d) AS year,
  EXTRACT(MONTH FROM d) AS month,
  FORMAT_DATE('%B', d) AS month_name,
  EXTRACT(QUARTER FROM d) AS quarter,
  EXTRACT(DAYOFWEEK FROM d) IN (1, 7) AS is_weekend
FROM UNNEST(GENERATE_DATE_ARRAY('2026-01-01', '2026-12-31')) AS d;


-- creating facts table
CREATE OR REPLACE TABLE demo.fact_sales AS
SELECT 101 AS order_id, DATE '2026-11-01' AS order_date, 1 AS customer_key, 10 AS product_key, 1 AS quantity, 500 AS line_amount, 900 AS order_total UNION ALL
SELECT 101, DATE '2026-11-01', 1, 11, 2, 100, 900 UNION ALL
SELECT 101, DATE '2026-11-01', 1, 12, 1, 300, 900 UNION ALL
SELECT 102, DATE '2026-11-02', 2, 13, 3,  60,  60 UNION ALL
SELECT 103, DATE '2026-11-03', 3, 10, 1, 500, 800 UNION ALL
SELECT 103, DATE '2026-11-03', 3, 12, 1, 300, 800 UNION ALL
SELECT 104, DATE '2026-11-05', 1, 11, 5, 250, 250;

-- using dimension tables and fact tale
select c.city, p.category , sum(f.line_amount) as revenue 
from demo.fact_sales as f 
join demo.dim_customer c on c.customer_key = f.customer_key
join demo.dim_product p on p.product_key = f.product_key
group by c.city, p.category
order by revenue desc;

-- geting sales by weekend or weekday of a month
select d.month_name, d.is_weekend, sum(f.line_amount) as revenue
from demo.fact_sales as f
join demo.dim_date d on f.order_date = d.date_key
group by d.month_name, d.is_weekend;

select 
sum(line_amount) as la,
sum(order_total) as ot
from demo.fact_sales;

-- Show revenue per product name, highest first.
select p.product_name, sum(f.line_amount) as revenue
from demo.fact_sales as f 
join demo.dim_product p on p.product_key = f.product_key
group by p.product_name
order by revenue desc;

-- Show how many order lines each customer has.
select c.name, count(*) as order_lines
from demo.fact_sales as f 
join demo.dim_customer c on c.customer_key = f.customer_key
group by c.name;

-- Find the customer city with the highest revenue in the Electronics category.
select c.city , sum(f.line_amount) as revenue  
from demo.fact_sales as f
join demo.dim_customer c on c.customer_key = f.customer_key
join demo.dim_product p on p.product_key = f.product_key
where p.category = 'Electronics'
group by  c.city 
-- order by revenue DESC 
qualify rank() over (order by sum(f.line_amount) desc) = 1;
-- limit 1;


-- Show total quantity sold per category 
select p.category, sum(f.quantity) as sold 
from demo.fact_sales as f 
join demo.dim_product p on p.product_key = f.product_key
group by p.category;


-- Slowly changing dimensions (SCD)
CREATE OR REPLACE TABLE demo.dim_customer_scd AS
SELECT 1 AS customer_key, 'C001' AS customer_id, 'Asha' AS name, 'Hyderabad' AS city,
       DATE '2026-01-01' AS valid_from, DATE '9999-12-31' AS valid_to, TRUE AS is_current
UNION ALL
SELECT 2, 'C002', 'Ravi', 'Pune', DATE '2026-01-01', DATE '9999-12-31', TRUE;


-- Asha moves on 2026-11-10. First, close her old row.
-- UPDATE demo.dim_customer_scd
-- SET valid_to = DATE '2026-11-09', is_current = FALSE
-- WHERE customer_id = 'C001' AND is_current;
CREATE OR REPLACE TABLE demo.dim_customer_scd AS
SELECT
  customer_key, customer_id, name, city, valid_from,
  IF(customer_id = 'C001' AND is_current, DATE '2026-11-09', valid_to) AS valid_to,
  IF(customer_id = 'C001' AND is_current, FALSE, is_current) AS is_current
FROM demo.dim_customer_scd
UNION ALL
SELECT 4, 'C001', 'Asha', 'Bangalore', DATE '2026-11-10', DATE '9999-12-31', TRUE;


-- 1. Reset the dimension to its starting state
CREATE OR REPLACE TABLE demo.dim_customer_scd AS
SELECT 1 AS customer_key, 'C001' AS customer_id, 'Asha' AS name, 'Hyderabad' AS city,
       DATE '2026-01-01' AS valid_from, DATE '9999-12-31' AS valid_to, TRUE AS is_current
UNION ALL
SELECT 2, 'C002', 'Ravi', 'Pune', DATE '2026-01-01', DATE '9999-12-31', TRUE;


-- adding and updating data 
CREATE OR REPLACE TABLE demo.stg_customer as
SELECT 'C001' AS customer_id, 'Asha' as name, 'Bangalore' AS city UNION ALL
SELECT 'C002', 'Ravi', 'Pune' UNION ALL
SELECT 'C003', 'Meena', 'Chennai';






-- 3. The SCD Type 2 load, effective 2026-11-10
create or replace table demo.dim_customer_scd as
with load_date as (
  select date '2026-11-10' as d
),
changed as (          
  select s.*
  from demo.stg_customer s
  left join demo.dim_customer_scd t
    on t.customer_id = s.customer_id and t.is_current
  where t.customer_id is null or t.city != s.city
),
existing as (         
  select
    t.customer_key, t.customer_id, t.name, t.city, t.valid_from,
    if(c.customer_id is not null, date_sub(l.d, interval 1 day), t.valid_to) as valid_to,
    if(c.customer_id is not null, false, t.is_current) as is_current
  from demo.dim_customer_scd t
  cross join load_date l
  left join changed c
    on c.customer_id = t.customer_id and t.is_current
),
new_rows as (         
  select
    (select max(customer_key) from demo.dim_customer_scd)
      + row_number() over (order by c.customer_id) as customer_key,
    c.customer_id, c.name, c.city,
    l.d as valid_from, date '9999-12-31' as valid_to, true as is_current
  from changed c
  cross join load_date l
)
select * from existing
union all
select * from new_rows;




