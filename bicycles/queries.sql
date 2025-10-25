-- 1
-- MAU
SELECT store_id,
        DATE_TRUNC('month', order_date)::DATE AS month,
        COUNT(DISTINCT customer_id) AS MAU
FROM orders
GROUP BY DATE_TRUNC('month', order_date), store_id
ORDER BY store_id, month

-------------------------------------------------------------------------------------------------------------------------------------------------
-- 2
-- Рассчет AOV, ARPU, ARPPU для каждого магазина за месяц
-- Найдем выручку с каждого заказа
with Orders_revenue_t AS (
  SELECT order_id,
          SUM(quantity * list_price * (1 - discount)) AS order_revenue
  FROM order_items
  GROUP BY order_id 
),
-- Рассчитаем для каждого магазина выручку, количество заказов и активных пользователей за месяц  
Res_t AS (
        SELECT 
        a.store_id,
        DATE_TRUNC('month', a.order_date)::DATE AS month,
        SUM(b.order_revenue) AS revenue,
        COUNT(a.order_id) AS orders_count,
        COUNT(DISTINCT a.customer_id) AS active_users_count

        FROM (SELECT order_id,
                order_date,
                customer_id,
                store_id              
                FROM orders
                WHERE order_status = 4) a -- выбираем только успешно доставленные заказы
        JOIN Orders_revenue_t b
        ON a.order_id = b.order_id
        GROUP BY a.store_id, DATE_TRUNC('month', a.order_date)
        )

-- Присоединим общее количество пользователей в месяц и рассчитаем искомые метрики
SELECT r.store_id,
        r.month,
        r.revenue,
        ROUND(r.revenue::DECIMAL / r.orders_count, 2) AS AOV,
        ROUND(r.revenue::DECIMAL / r.active_users_count, 2) AS ARPPU,
        ROUND(r.revenue::DECIMAL / u.users_count, 2) AS ARPU
        
FROM Res_t r
LEFT JOIN 
        (SELECT store_id,
                DATE_TRUNC('month', order_date)::DATE AS month,
                COUNT(DISTINCT customer_id) AS users_count
        FROM orders
        GROUP BY DATE_TRUNC('month', order_date), store_id
        ORDER BY store_id, month) u
ON r.store_id = u.store_id AND r.month = u.month

-------------------------------------------------------------------------------------------------------------------------------------------------

-- 3
-- cancel_rate
SELECT store_id, 
        DATE_TRUNC('month', order_date)::DATE AS month,
        ROUND(100 * COUNT(order_id) FILTER(WHERE order_status = 3) / COUNT(*)::DECIMAL, 2) AS cancel_rate
FROM orders
GROUP BY DATE_TRUNC('month', order_date), store_id
ORDER BY store_id, month

-------------------------------------------------------------------------------------------------------------------------------------------------
-- 4
-- распределения количества статусов заказов по месяцам

SELECT DATE_TRUNC('month', order_date)::DATE AS month,
       CASE order_status
           WHEN 1 THEN 'Pending'
           WHEN 2 THEN 'Processing'
           WHEN 3 THEN 'Rejected'
           WHEN 4 THEN 'Completed'
        END AS order_status,
       COUNT(*) AS cnt
FROM orders
GROUP BY DATE_TRUNC('month', order_date)::DATE, order_status
ORDER BY month, order_status

-------------------------------------------------------------------------------------------------------------------------------------------------

-- 5
/*Найдем самые продаваемые товары, самые прибыльные товары, а также выручку с различных категорий товаров и бренды, которые в среднем приносят больше денег, чем остальные

Для удобства создадим представление (View) cо следующими столбцами: 
- product_name - название товара
- sold_quantity - количество проданных штук
- product_revenue - выручка с товара
- category_name - категория товара
- brand_name - бренд */

CREATE OR REPLACE VIEW Top_View AS 
  with t1 AS
    (SELECT product_id,
            SUM(quantity) AS sold_quantity,
            SUM(quantity * list_price * (1 - discount)) AS product_revenue
    FROM order_items oi
    WHERE EXISTS(SELECT 1 
                  FROM orders o 
                  WHERE o.order_status = 4
                        AND o.order_id = oi.order_id)
    GROUP BY product_id)
  
  SELECT product_id,
          product_name,
          sold_quantity,
          product_revenue,
          category_name,
          brand_name

  FROM t1 
  LEFT JOIN products 
    USING(product_id)
  LEFT JOIN categories 
    USING(category_id)
  LEFT JOIN brands
    USING(brand_id)
    
-------------------------------------------------------------------------------------------------------------------------------------------------

-- 6
-- 15 самых продаваемых товаров (если кол-во одинаковое, то отбирается в алфавитном порядке)

SELECT product_id, product_name, sold_quantity
FROM Top_View
ORDER BY sold_quantity DESC, product_name
LIMIT 15

-------------------------------------------------------------------------------------------------------------------------------------------------

-- 7
-- Топ 15 товаров по выручке

SELECT CONCAT('id_', product_id, ' ', product_name) AS id_name,
        product_revenue
FROM Top_View
ORDER BY product_revenue DESC
LIMIT 15

-------------------------------------------------------------------------------------------------------------------------------------------------

-- 8
-- товары, которые есть в топе и по выручке и по количеству продаж
(SELECT id_name
FROM
    (SELECT CONCAT('id_', product_id, ' ', product_name) AS id_name,
            product_revenue
    FROM Top_View
    ORDER BY product_revenue DESC
    LIMIT 15) t1)
    
INTERSECT 

(SELECT id_name
FROM 
    (SELECT CONCAT('id_', product_id, ' ', product_name) AS id_name,
            product_name,
            sold_quantity
    FROM Top_View
    ORDER BY sold_quantity DESC, product_name
    LIMIT 15) t2)
    
-------------------------------------------------------------------------------------------------------------------------------------------------
-- 9 
-- Посчитаем выручку с разных категорий

SELECT category_name, ROUND(SUM(product_revenue)) AS category_revenue
FROM Top_View
GROUP BY category_name
ORDER BY 2

-------------------------------------------------------------------------------------------------------------------------------------------------

-- 10
-- Найдем бренды, которые в среднем прносят больше денег, чем остальные

SELECT brand_name
FROM Top_View
GROUP BY brand_name
HAVING SUM(product_revenue) > (SELECT AVG(brand_revenue)
                                FROM 
                                  (SELECT SUM(product_revenue) AS brand_revenue
                                  FROM Top_View 
                                  GROUP BY brand_name) t)

-------------------------------------------------------------------------------------------------------------------------------------------------

-- 11
-- Найдем для каждого менеджера количество подчиненных
/*stuffs содержит следующие столбцы:

- staff_id (первичный ключ)
- first_name
- last_name
- email
- phone
- active
- store_id
- manager_id */

-- найдем работающих на данный момент сотрудников 
WITH active_t AS (
  SELECT staff_id
  FROM staffs
  WHERE active = 1
)

SELECT a.manager_id,
        b.first_name,
        b.last_name,
        COUNT(*) AS subordinates_count
FROM staffs a
LEFT JOIN staffs b
    ON a.manager_id = b.staff_id
WHERE a.manager_id IS NOT NULL
      AND a.manager_id IN (SELECT * FROM active_t)
      AND b.staff_id IN (SELECT * FROM active_t)
GROUP BY a.manager_id, b.first_name, b.last_name
ORDER BY 1

-------------------------------------------------------------------------------------------------------------------------------------------------

-- 12
-- Выведем имя сотрудника и его статус
/*Сотрудник может быть

- менеджером, если у него есть хотябы один подчиненным (manager)
- обычным работником, если подчиненных нет (employee)
- Топ менеджером, если не находится ни у кого в подчинении, то есть manager_id IS NULL (top_manager) */

SELECT staff_id,
        first_name,
        last_name,
        CASE
            WHEN manager_id IS NOT NULL AND staff_id IN (SELECT DISTINCT manager_id FROM staffs) THEN 'manager'
            WHEN manager_id IS NULL THEN 'top_manager'
            ELSE 'employee' 
        END AS status        
FROM staffs
ORDER BY status DESC, staff_id

-------------------------------------------------------------------------------------------------------------------------------------------------

-- 13
-- Найдем через сколько дней должна была состояться предполагаемая доставка и через сколько дней товар был доставлен по факту

SELECT DATE_TRUNC('month', order_date) AS month,
        ROUND(AVG(shipped_date - order_date), 2) AS days_to_shipped,
        ROUND(AVG(required_date - order_date), 2) AS required_days,
        ROUND(AVG(shipped_date - required_date), 2) AS diff
FROM orders
WHERE order_status = 4
GROUP BY DATE_TRUNC('month', order_date)
ORDER BY month

-------------------------------------------------------------------------------------------------------------------------------------------------

-- 14
-- Retention
WITH t1 AS (
SELECT DISTINCT customer_id,
        store_id,
        DATE_TRUNC('quarter', order_date) AS order_quarter,
        MIN(DATE_TRUNC('quarter', order_date)) OVER(PARTITION BY store_id, customer_id) AS first_quarter
FROM orders)

SELECT store_id,
        first_quarter,
        order_quarter,
        'quarter '|| ((EXTRACT('month' FROM AGE(order_quarter, first_quarter)) +
                EXTRACT('year' FROM AGE(order_quarter, first_quarter)) * 12) / 3)::INT::VARCHAR
                        AS quarter_num,
        ROUND(100 * COUNT(customer_id)::DECIMAL /
                MAX(COUNT(customer_id)) OVER(PARTITION BY store_id, first_quarter), 2) AS retention
FROM t1
GROUP BY store_id, first_quarter, order_quarter
ORDER BY store_id, first_quarter, order_quarter, quarter_num

-------------------------------------------------------------------------------------------------------------------------------------------------

-- 15
-- Rolling retention

WITH 
-- Найдем для каждого покупателя квартал когда была совершена покупка и первая покупка
t1 AS (
SELECT DISTINCT customer_id,
        store_id,
        DATE_TRUNC('quarter', order_date) AS order_quarter,
        MIN(DATE_TRUNC('quarter', order_date)) OVER(PARTITION BY store_id, customer_id) AS first_quarter
FROM orders),
-- найдем каким по счету является квартал с момента первой покупки
t2 AS (
        SELECT customer_id,
                store_id,
                first_quarter,
                ((EXTRACT('month' FROM AGE(order_quarter, first_quarter)) +
                EXTRACT('year' FROM AGE(order_quarter, first_quarter)) * 12) / 3)::INT
                        AS quarter_num 
        FROM t1
),

-- создадим cte с номерами кварталов. Если квартал в котором была совершена покупка больше или равен номеру квартала
-- из t3, то мы выводим customer_id человека, который совершал покупку.
-- Сгруппировав по id магазина, кварталу первой покупки и номеру квартала,
-- получим количество уникальных человек, которые совершили покупку в данном или последующем квартале

t3 AS (
SELECT DISTINCT quarter_num
FROM t2
),
res_t AS (
SELECT t2.store_id, t2.first_quarter, t3.quarter_num,
        COUNT (DISTINCT (CASE
                            WHEN t2.quarter_num >= t3.quarter_num THEN t2.customer_id
                            END)) AS cnt
FROM t2, t3 
WHERE t3.quarter_num <= ((EXTRACT('month' FROM AGE((SELECT MAX(order_quarter) FROM t1), t2.first_quarter)) +
                EXTRACT('year' FROM AGE((SELECT MAX(order_quarter) FROM t1), t2.first_quarter)) * 12) / 3)::INT


GROUP BY t2.store_id, t2.first_quarter, t3.quarter_num
)
-- Посчитаем rolling_retention
SELECT store_id, first_quarter, quarter_num,
       ROUND(100 * cnt::DECIMAL / (MAX(cnt) OVER(PARTITION BY store_id, first_quarter)), 2) AS rolling_retention
FROM res_t
ORDER BY store_id, first_quarter, quarter_num

-------------------------------------------------------------------------------------------------------------------------------------------------

-- 16
-- Товары, которые покупают вместе чаще всего

WITH t1 AS (
  SELECT a.product_id a_product,
         b.product_id b_product,
         COUNT(*) as cnt
  FROM order_items a
  JOIN order_items b
  ON a.order_id = b.order_id

  WHERE a.product_id > b.product_id
  GROUP BY a.product_id, b.product_id
)

SELECT p1.product_name AS product1,
        p2.product_name AS product2,
        t1.cnt
FROM t1
LEFT JOIN (SELECT product_id, product_name FROM products) p1
ON t1.a_product = p1.product_id
LEFT JOIN (SELECT product_id, product_name FROM products) p2
ON t1.b_product = p2.product_id

ORDER BY cnt DESC, product1
LIMIT 10

-------------------------------------------------------------------------------------------------------------------------------------------------

-- 17
-- Информация о покупателях

with Orders_revenue_t AS (
  SELECT order_id,
          SUM(quantity * list_price * (1 - discount)) AS order_revenue
  FROM order_items
  GROUP BY order_id 
),
t1 AS (
SELECT store_id, customer_id, 
        COUNT(order_id) AS count_orders,
        SUM(order_revenue) AS revenue_per_user,
        SUM(order_revenue)::DECIMAL / COUNT(order_id) AS avg_order_price
FROM orders o
LEFT JOIN Orders_revenue_t r
USING(order_id)
WHERE order_status = 4
GROUP BY store_id, customer_id)

SELECT store_name,
        first_name ||' '|| last_name AS name,
        phone, email, city,
        count_orders,
        revenue_per_user,
        ROUND(avg_order_price, 2) AS avg_order_price
FROM t1
LEFT JOIN customers c
USING(customer_id)
LEFT JOIN (SELECT store_id, store_name FROM stores) st
USING(store_id)
ORDER BY revenue_per_user














