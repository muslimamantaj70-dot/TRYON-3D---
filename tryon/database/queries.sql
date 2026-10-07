-- TryOn: негізгі сұраулар мен сценарийлер (SQLite). Әр блок — нақты функционалдық талапқа сәйкес.

-- Q1. Каталог (FR-05): белсенді тауарлар, қоймадағы өлшемдер
SELECT product_id, name, price, category, shop_name, sizes_in_stock FROM v_catalog ORDER BY product_id;

-- Q2. Клиент профилі бойынша ұсынылатын өлшем (FR-07). Мысалы, Данияр (user 6)
SELECT p.name, r.size_label AS recommended
FROM v_recommended_size r JOIN products p ON p.id = r.product_id
WHERE r.user_id = 6 ORDER BY p.id;

-- Q3. Отыру аймақтары: 3D манекеннің түстері (FR-08). Айгерім (5), «Көк свитер», барлық өлшем
SELECT size_label, zone, body_cm, garment_cm, diff_cm, verdict
FROM v_fit_zones WHERE user_id = 5 AND product_id = 2 ORDER BY size_rank, zone;

-- Q4. Бір өлшемнің жалпы үкімі
SELECT size_label, verdict FROM v_size_verdict WHERE user_id = 5 AND product_id = 4 ORDER BY size_rank;

-- Q5. Тапсырыс жасау (FR-10, FR-11): транзакция ішінде, қалдық автоматты азаяды
-- BEGIN;
-- INSERT INTO orders(customer_id, ship_city, ship_street, ship_house, ship_phone) VALUES (5,'Алматы','Абай даңғылы','10','+77010000005');
-- INSERT INTO order_items(order_id, product_size_id, product_name, unit_price, qty) VALUES (<order_id>, <size_id>, '<атауы>', <баға>, 1);
-- COMMIT;

-- Q6. Сатушы панелі: өз тапсырыстары
SELECT order_id, status, customer, product_name, size_label, qty, line_total FROM v_seller_orders WHERE seller_id = 3 ORDER BY order_id;

-- Q7. Қоймада аз қалған өлшемдер (сатушыға ескерту)
SELECT name, size_label, stock_qty FROM v_low_stock WHERE seller_id = 3 ORDER BY stock_qty, name;

-- Q8. Әкімші есебі (FR-16): қайтару көрсеткіштері, өлшемге байланысты қайтарулар
SELECT name, units_delivered, units_returned, size_related_returns,
       CASE WHEN units_delivered = 0 THEN 0 ELSE ROUND(100.0 * units_returned / units_delivered, 1) END AS return_rate_pct
FROM v_return_stats ORDER BY return_rate_pct DESC, name;

-- Q9. Клиенттің хабарламалары (FR-13)
SELECT created_at, kind, message FROM notifications WHERE user_id = 5 ORDER BY id;

-- Q10. Тапсырыс мәртебесінің тарихы
SELECT h.changed_at, h.status FROM order_status_history h WHERE h.order_id = 1 ORDER BY h.id;
