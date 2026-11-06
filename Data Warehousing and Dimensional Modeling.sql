-- creating dimension tale for customer
create or replace table demo.dim_customer as
select 1 as customer_key, 'C001' as customer_id, 'Asha' as name, 'Hyderabad' as city union all
select 2, 'C002', 'Ravi', 'Pune' union all
select 3, 'C003', 'Meena', 'Chennai';


-- creating dimension tale for product
create or replace table demo.dim_product as
select 10 as product_key, 'P10' as product_id, 'Phone X' as product_name, 'Electronics' as category union all
select 11, 'P11', 'Notebook', 'Stationery' union all
select 12, 'P12', 'Earbuds', 'Electronics' union all
select 13, 'P13', 'Pen', 'Stationery';

-- creating tale for dates for a year(2026)
create or replace table demo.dim_date as
select
  d as date_key,
  extract(year from d) as year,
  extract(month from d) as month,
  format_date('%B', d) as month_name,
  extract(quarter from d) as quarter,
  extract(dayofweek from d) in (1, 7) as is_weekend
from unnest(generate_date_array('2026-01-01', '2026-12-31')) as d;


-- creating facts table
create or replace table demo.fact_sales as
select 101 as order_id, date '2026-11-01' as order_date, 1 as customer_key, 10 as product_key, 1 as quantity, 500 as line_amount, 900 as order_total union all
select 101, date '2026-11-01', 1, 11, 2, 100, 900 union all
select 101, date '2026-11-01', 1, 12, 1, 300, 900 union all
select 102, date '2026-11-02', 2, 13, 3,  60,  60 union all
select 103, date '2026-11-03', 3, 10, 1, 500, 800 union all
select 103, date '2026-11-03', 3, 12, 1, 300, 800 union all
select 104, date '2026-11-05', 1, 11, 5, 250, 250;

-- using dimension tables and fact tale
select c.city, p.category, sum(f.line_amount) as revenue
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
select c.city, sum(f.line_amount) as revenue
from demo.fact_sales as f
join demo.dim_customer c on c.customer_key = f.customer_key
join demo.dim_product p on p.product_key = f.product_key
where p.category = 'Electronics'
group by c.city
-- order by revenue desc
qualify rank() over (order by sum(f.line_amount) desc) = 1;
-- limit 1;


-- Show total quantity sold per category
select p.category, sum(f.quantity) as sold
from demo.fact_sales as f
join demo.dim_product p on p.product_key = f.product_key
group by p.category;


-- Slowly changing dimensions (SCD)
create or replace table demo.dim_customer_scd as
select 1 as customer_key, 'C001' as customer_id, 'Asha' as name, 'Hyderabad' as city,
       date '2026-01-01' as valid_from, date '9999-12-31' as valid_to, true as is_current
union all
select 2, 'C002', 'Ravi', 'Pune', date '2026-01-01', date '9999-12-31', true;


-- Asha moves on 2026-11-10. First, close her old row.
-- update demo.dim_customer_scd
-- set valid_to = date '2026-11-09', is_current = false
-- where customer_id = 'C001' and is_current;
create or replace table demo.dim_customer_scd as
select
  customer_key, customer_id, name, city, valid_from,
  if(customer_id = 'C001' and is_current, date '2026-11-09', valid_to) as valid_to,
  if(customer_id = 'C001' and is_current, false, is_current) as is_current
from demo.dim_customer_scd
union all
select 4, 'C001', 'Asha', 'Bangalore', date '2026-11-10', date '9999-12-31', true;


-- 1. Reset the dimension to its starting state
create or replace table demo.dim_customer_scd as
select 1 as customer_key, 'C001' as customer_id, 'Asha' as name, 'Hyderabad' as city,
       date '2026-01-01' as valid_from, date '9999-12-31' as valid_to, true as is_current
union all
select 2, 'C002', 'Ravi', 'Pune', date '2026-01-01', date '9999-12-31', true;


-- adding and updating data
create or replace table demo.stg_customer as
select 'C001' as customer_id, 'Asha' as name, 'Bangalore' as city union all
select 'C002', 'Ravi', 'Pune' union all
select 'C003', 'Meena', 'Chennai';






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


-- Connecting facts to the right version

with sales as (
  select 'C001' as customer_id, date '2026-10-15' as order_date, 100 as amount union all
  select 'C001', date '2026-11-12', 200 union all
  select 'C003', date '2026-11-12',  50 union all
  select 'C003', date '2026-11-16',  70
)
select c.city, sum(s.amount) as revenue
from sales s
join demo.dim_customer_scd c on c.customer_id = s.customer_id
and s.order_date between c.valid_from and c.valid_to
group by c.city;

-- 1. Raw sales as they arrive (only business keys, no surrogate keys yet)
create or replace table demo.stg_sales as
select 1 as sale_id, 'C001' as customer_id, date '2026-10-15' as order_date, 100 as amount union all
select 2, 'C001', date '2026-11-12', 200 union all
select 3, 'C003', date '2026-11-12',  50 union all
select 4, 'C003', date '2026-11-16',  70 union all
select 5, 'C002', date '2026-11-13',  90;


-- 2. Build the fact table, looking up the correct dimension version once
create or replace table demo.fact_sales_scd as
select
  s.sale_id,
  s.order_date,
  d.customer_key,
  s.amount
from demo.stg_sales s
join demo.dim_customer_scd d
  on d.customer_id = s.customer_id
 and s.order_date between d.valid_from and d.valid_to;

 -- 3. Now reports use a simple key join, and history is still correct
select d.city, sum(f.amount) as revenue
from demo.fact_sales_scd f
join demo.dim_customer_scd d on d.customer_key = f.customer_key
group by d.city
order by revenue desc;