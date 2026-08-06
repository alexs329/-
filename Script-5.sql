SELECT 'purchases' AS table_name, COUNT(*) AS row_count FROM purchases
UNION ALL SELECT 'events', COUNT(*) FROM events
UNION ALL SELECT 'venues', COUNT(*) FROM venues
UNION ALL SELECT 'city', COUNT(*) FROM city
UNION ALL SELECT 'regions', COUNT(*) FROM regions;

-- 3. КОРРЕКТНОСТЬ ДАННЫХ

-- 3.1 Уникальность идентификаторов (проверка дубликатов)
SELECT 'purchases.order_id' AS pk_name, COUNT(*) - COUNT(DISTINCT order_id) AS duplicates FROM purchases
UNION ALL SELECT 'events.event_id', COUNT(*) - COUNT(DISTINCT event_id) FROM events
UNION ALL SELECT 'venues.venue_id', COUNT(*) - COUNT(DISTINCT venue_id) FROM venues
UNION ALL SELECT 'city.city_id', COUNT(*) - COUNT(DISTINCT city_id) FROM city
UNION ALL SELECT 'regions.region_id', COUNT(*) - COUNT(DISTINCT region_id) FROM regions;

-- 3.2 Пропуски (NULL) в ключевых полях
SELECT 
    'purchases' AS table_name,
    COUNT(*) FILTER (WHERE order_id IS NULL) AS null_pk,
    COUNT(*) FILTER (WHERE event_id IS NULL) AS null_fk,
    COUNT(*) FILTER (WHERE user_id IS NULL) AS null_user,
    COUNT(*) FILTER (WHERE revenue IS NULL) AS null_revenue,
    COUNT(*) FILTER (WHERE total IS NULL) AS null_total,
    COUNT(*) FILTER (WHERE tickets_count IS NULL) AS null_tickets
FROM purchases;

-- 3.3 Корректность категориальных данных (проверка допустимых значений)
SELECT DISTINCT device_type_canonical AS device_types, COUNT(*) AS count FROM purchases GROUP BY device_type_canonical;
SELECT DISTINCT currency_code AS currencies, COUNT(*) AS count FROM purchases GROUP BY currency_code;
SELECT DISTINCT age_limit AS age_limits, COUNT(*) AS count FROM purchases WHERE age_limit IS NOT NULL GROUP BY age_limit ORDER BY age_limit;
SELECT DISTINCT city_name AS cities, COUNT(*) AS count FROM city GROUP BY city_name ORDER BY city_name;
SELECT DISTINCT region_name AS regions, COUNT(*) AS count FROM regions GROUP BY region_name ORDER BY region_name;

-- 4. РАСПРЕДЕЛЕНИЕ ЗАКАЗОВ ПО ОСНОВНЫМ КАТЕГОРИЯМ

-- 4.1 По типам мероприятий (с указанием категорий с малым объемом)
SELECT 
    e.event_type_main,
    COUNT(DISTINCT p.order_id) AS orders_count,
    SUM(p.revenue) AS total_revenue,
    ROUND(COUNT(DISTINCT p.order_id) * 100.0 / SUM(COUNT(DISTINCT p.order_id)) OVER(), 2) AS percent_of_total
FROM purchases p
JOIN events e ON p.event_id = e.event_id
GROUP BY e.event_type_main
ORDER BY orders_count DESC;

-- 4.2 По устройствам
SELECT 
    device_type_canonical,
    COUNT(*) AS orders_count,
    SUM(revenue) AS total_revenue,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percent_of_total
FROM purchases
GROUP BY device_type_canonical
ORDER BY orders_count DESC;

-- 4.3 По валютам
SELECT 
    currency_code,
    COUNT(*) AS orders_count,
    SUM(revenue) AS total_revenue,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percent_of_total
FROM purchases
GROUP BY currency_code
ORDER BY orders_count DESC;

-- 4.4 По регионам
SELECT 
    r.region_name,
    COUNT(DISTINCT p.order_id) AS orders_count,
    SUM(p.revenue) AS total_revenue,
    ROUND(COUNT(DISTINCT p.order_id) * 100.0 / SUM(COUNT(DISTINCT p.order_id)) OVER(), 2) AS percent_of_total
FROM purchases p
JOIN events e ON p.event_id = e.event_id
JOIN city c ON e.city_id = c.city_id
JOIN regions r ON c.region_id = r.region_id
GROUP BY r.region_name
ORDER BY orders_count DESC;

-- 4.5 По сетям кинотеатров (обратить внимание на 'нет')
SELECT 
    cinema_circuit,
    COUNT(*) AS orders_count,
    SUM(revenue) AS total_revenue,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percent_of_total
FROM purchases
GROUP BY cinema_circuit
ORDER BY orders_count DESC;

-- 5. АНОМАЛИИ И ВЫБРОСЫ В ВЫРУЧКЕ

-- 5.1 Статистические показатели revenue
SELECT 
    COUNT(*) AS total_orders,
    COUNT(*) FILTER (WHERE revenue = 0) AS zero_revenue,
    COUNT(*) FILTER (WHERE revenue < 0) AS negative_revenue,
    MIN(revenue) AS min_revenue,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY revenue) AS q1,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY revenue) AS median,
    AVG(revenue) AS avg_revenue,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY revenue) AS q3,
    MAX(revenue) AS max_revenue,
    STDDEV(revenue) AS stddev
FROM purchases
WHERE revenue IS NOT NULL;

-- 5.2 Выбросы (заказы с аномальной выручкой - ТОП-10)
SELECT 
    order_id,
    user_id,
    event_id,
    revenue,
    tickets_count,
    created_dt_msk
FROM purchases
WHERE revenue IS NOT NULL
ORDER BY revenue DESC
LIMIT 10;

-- 5.3 Проверка логических аномалий
SELECT 
    COUNT(*) FILTER (WHERE revenue > total) AS revenue_gt_total,
    COUNT(*) FILTER (WHERE tickets_count <= 0) AS invalid_tickets,
    COUNT(*) FILTER (WHERE total = 0 AND tickets_count > 0) AS free_orders_with_tickets,
    COUNT(*) FILTER (WHERE revenue IS NULL AND total IS NOT NULL) AS null_revenue_but_total_exists
FROM purchases;

-- 6. ПЕРИОД ВРЕМЕНИ И СЕЗОННОСТЬ

-- 6.1 Диапазон дат
SELECT 
    MIN(created_dt_msk) AS first_order_date,
    MAX(created_dt_msk) AS last_order_date,
    (MAX(created_dt_msk) - MIN(created_dt_msk)) AS date_range_days,
    COUNT(DISTINCT DATE_TRUNC('month', created_dt_msk)) AS months_count
FROM purchases
WHERE created_dt_msk IS NOT NULL;

-- 6.2 Помесячная динамика (для выявления сезонности)
SELECT 
    DATE_TRUNC('month', created_dt_msk) AS month,
    COUNT(*) AS orders_count,
    SUM(revenue) AS total_revenue,
    AVG(revenue) AS avg_revenue,
    COUNT(DISTINCT user_id) AS unique_users
FROM purchases
WHERE created_dt_msk IS NOT NULL AND revenue IS NOT NULL
GROUP BY DATE_TRUNC('month', created_dt_msk)
ORDER BY month;

-- 6.3 Сезонность по дням недели
SELECT 
    EXTRACT(DOW FROM created_dt_msk) AS day_number,
    CASE EXTRACT(DOW FROM created_dt_msk)
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END AS day_name,
    COUNT(*) AS orders_count,
    AVG(revenue) AS avg_revenue,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percent_of_week
FROM purchases
WHERE created_dt_msk IS NOT NULL
GROUP BY EXTRACT(DOW FROM created_dt_msk)
ORDER BY day_number;


-- =====================================================
-- ВСЕ ВЫВОДЫ В ОДНОМ ЗАПРОСЕ (БЕЗ ROUND С 2 АРГУМЕНТАМИ)
-- =====================================================

-- 1. ВЫБРОСЫ В ВЫРУЧКЕ
SELECT 'ВЫБРОСЫ В ВЫРУЧКЕ' AS section;

WITH stats AS (
    SELECT 
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY revenue) AS q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY revenue) AS q3
    FROM purchases
    WHERE revenue IS NOT NULL AND revenue > 0
)
SELECT 
    COUNT(*) AS total_orders,
    AVG(revenue) AS avg_revenue,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY revenue) AS median_revenue,
    MIN(revenue) AS min_revenue,
    MAX(revenue) AS max_revenue,
    COUNT(*) FILTER (WHERE revenue > ((SELECT q3 FROM stats) + 3 * ((SELECT q3 FROM stats) - (SELECT q1 FROM stats)))) AS outliers_count,
    (COUNT(*) FILTER (WHERE revenue > ((SELECT q3 FROM stats) + 3 * ((SELECT q3 FROM stats) - (SELECT q1 FROM stats)))) * 100.0 / COUNT(*)) AS outliers_percent
FROM purchases
WHERE revenue IS NOT NULL AND revenue > 0;

-- 2. РАЗНЫЕ ВАЛЮТЫ
SELECT 'РАЗНЫЕ ВАЛЮТЫ' AS section;

SELECT 
    currency_code,
    COUNT(*) AS orders_count,
    (COUNT(*) * 100.0 / SUM(COUNT(*)) OVER()) AS orders_percent,
    SUM(revenue) AS total_revenue,
    (SUM(revenue) * 100.0 / SUM(SUM(revenue)) OVER()) AS revenue_percent
FROM purchases
WHERE revenue IS NOT NULL AND revenue > 0
GROUP BY currency_code
ORDER BY orders_count DESC;

-- 3. КОЛИЧЕСТВО ЗНАЧЕНИЙ В КАТЕГОРИЯХ
SELECT 'КОЛИЧЕСТВО ЗНАЧЕНИЙ В КАТЕГОРИЯХ' AS section;

SELECT 
    'Типы мероприятий' AS category, 
    COUNT(DISTINCT event_type_main) AS unique_values 
FROM events
UNION ALL
SELECT 'Устройства', COUNT(DISTINCT device_type_canonical) FROM purchases
UNION ALL
SELECT 'Валюты', COUNT(DISTINCT currency_code) FROM purchases
UNION ALL
SELECT 'Города', COUNT(DISTINCT city_name) FROM city
UNION ALL
SELECT 'Регионы', COUNT(DISTINCT region_name) FROM regions
UNION ALL
SELECT 'Площадки', COUNT(DISTINCT venue_name) FROM venues
UNION ALL
SELECT 'Билетные операторы', COUNT(DISTINCT service_name) FROM purchases;

-- 4. РАСПРЕДЕЛЕНИЕ ПО ТИПАМ МЕРОПРИЯТИЙ
SELECT 'РАСПРЕДЕЛЕНИЕ ПО ТИПАМ МЕРОПРИЯТИЙ' AS section;

SELECT 
    e.event_type_main,
    COUNT(DISTINCT p.order_id) AS orders_count,
    (COUNT(DISTINCT p.order_id) * 100.0 / SUM(COUNT(DISTINCT p.order_id)) OVER()) AS percent
FROM purchases p
JOIN events e ON p.event_id = e.event_id
GROUP BY e.event_type_main
ORDER BY orders_count DESC;

-- 5. РАСПРЕДЕЛЕНИЕ ПО УСТРОЙСТВАМ
SELECT 'РАСПРЕДЕЛЕНИЕ ПО УСТРОЙСТВАМ' AS section;

SELECT 
    device_type_canonical,
    COUNT(*) AS orders_count,
    (COUNT(*) * 100.0 / SUM(COUNT(*)) OVER()) AS percent
FROM purchases
GROUP BY device_type_canonical
ORDER BY orders_count DESC;

-- 6. ТОП-10 ГОРОДОВ
SELECT 'ТОП-10 ГОРОДОВ' AS section;

SELECT 
    c.city_name,
    COUNT(DISTINCT p.order_id) AS orders_count,
    (COUNT(DISTINCT p.order_id) * 100.0 / SUM(COUNT(DISTINCT p.order_id)) OVER()) AS percent
FROM purchases p
JOIN events e ON p.event_id = e.event_id
JOIN city c ON e.city_id = c.city_id
GROUP BY c.city_name
ORDER BY orders_count DESC
LIMIT 10;

-- 7. РЕДКИЕ КАТЕГОРИИ (типы мероприятий с < 50 заказами)
SELECT 'РЕДКИЕ ТИПЫ МЕРОПРИЯТИЙ (< 50 ЗАКАЗОВ)' AS section;

SELECT 
    e.event_type_main,
    COUNT(DISTINCT p.order_id) AS orders_count
FROM purchases p
JOIN events e ON p.event_id = e.event_id
GROUP BY e.event_type_main
HAVING COUNT(DISTINCT p.order_id) < 50
ORDER BY orders_count ASC;

-- 8. ОПЕРАТОРЫ С < 10 ЗАКАЗАМИ
SELECT 'ОПЕРАТОРЫ С < 10 ЗАКАЗАМИ' AS section;

SELECT 
    service_name,
    COUNT(*) AS orders_count
FROM purchases
GROUP BY service_name
HAVING COUNT(*) < 10
ORDER BY orders_count ASC;

-- 9. ИТОГОВАЯ СВОДКА (все выводы в одной таблице)
SELECT 'ИТОГОВАЯ СВОДКА' AS section;

WITH stats AS (
    SELECT 
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY revenue) AS q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY revenue) AS q3
    FROM purchases
    WHERE revenue IS NOT NULL AND revenue > 0
)
SELECT 
    'Всего заказов' AS metric,
    CAST(COUNT(*) AS VARCHAR) AS value
FROM purchases
UNION ALL
SELECT 
    'Выбросов в выручке (>3*IQR)',
    CAST(COUNT(*) AS VARCHAR)
FROM purchases
WHERE revenue > (SELECT q3 + 3 * (q3 - q1) FROM stats)
UNION ALL
SELECT 
    'Доля выбросов, %',
    CAST((COUNT(*) * 100.0 / (SELECT COUNT(*) FROM purchases WHERE revenue IS NOT NULL AND revenue > 0)) AS VARCHAR)
FROM purchases
WHERE revenue > (SELECT q3 + 3 * (q3 - q1) FROM stats)
UNION ALL
SELECT 
    'Разных валют',
    CAST(COUNT(DISTINCT currency_code) AS VARCHAR)
FROM purchases
UNION ALL
SELECT 
    'Типов мероприятий',
    CAST(COUNT(DISTINCT event_type_main) AS VARCHAR)
FROM events
UNION ALL
SELECT 
    'Типов устройств',
    CAST(COUNT(DISTINCT device_type_canonical) AS VARCHAR)
FROM purchases
UNION ALL
SELECT 
    'Городов с заказами',
    CAST(COUNT(DISTINCT c.city_id) AS VARCHAR)
FROM purchases p
JOIN events e ON p.event_id = e.event_id
JOIN city c ON e.city_id = c.city_id
UNION ALL
SELECT 
    'Операторов с < 10 заказами',
    CAST(COUNT(*) AS VARCHAR)
FROM (SELECT service_name FROM purchases GROUP BY service_name HAVING COUNT(*) < 10) t
UNION ALL
SELECT 
    'Типов мероприятий с < 50 заказами',
    CAST(COUNT(*) AS VARCHAR)
FROM (SELECT e.event_type_main FROM purchases p JOIN events e ON p.event_id = e.event_id GROUP BY e.event_type_main HAVING COUNT(DISTINCT p.order_id) < 50) t;




-- =====================================================
-- КЛЮЧЕВЫЕ МЕТРИКИ ПРОДУКТА
-- =====================================================

-- 1. ОБЩИЕ МЕТРИКИ (глобальные показатели)
SELECT '1. ОБЩИЕ МЕТРИКИ' AS section;

SELECT 
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT user_id) AS total_users,
    SUM(tickets_count) AS total_tickets_sold,
    SUM(revenue) AS total_revenue,
    AVG(revenue) AS avg_revenue_per_order,
    SUM(revenue) / NULLIF(SUM(tickets_count), 0) AS avg_revenue_per_ticket,
    COUNT(DISTINCT order_id) / NULLIF(COUNT(DISTINCT user_id), 0) AS orders_per_user,
    SUM(tickets_count) / NULLIF(COUNT(DISTINCT order_id), 0) AS avg_tickets_per_order
FROM purchases
WHERE revenue IS NOT NULL AND revenue > 0;

-- 2. ДИНАМИКА ПО МЕСЯЦАМ (для дашборда)
SELECT '2. ДИНАМИКА ПО МЕСЯЦАМ' AS section;

SELECT 
    DATE_TRUNC('month', created_dt_msk) AS month,
    COUNT(DISTINCT order_id) AS orders_count,
    COUNT(DISTINCT user_id) AS unique_users,
    SUM(tickets_count) AS tickets_sold,
    SUM(revenue) AS total_revenue,
    AVG(revenue) AS avg_revenue_per_order,
    SUM(revenue) / NULLIF(SUM(tickets_count), 0) AS avg_revenue_per_ticket,
    SUM(SUM(revenue)) OVER (ORDER BY DATE_TRUNC('month', created_dt_msK)) AS cumulative_revenue
FROM purchases
WHERE created_dt_msk IS NOT NULL 
  AND revenue IS NOT NULL 
  AND revenue > 0
GROUP BY DATE_TRUNC('month', created_dt_msk)
ORDER BY month;

-- 3. ВЫРУЧКА ПО ТИПАМ МЕРОПРИЯТИЙ
SELECT '3. ВЫРУЧКА ПО ТИПАМ МЕРОПРИЯТИЙ' AS section;

SELECT 
    e.event_type_main,
    COUNT(DISTINCT p.order_id) AS orders_count,
    SUM(p.tickets_count) AS tickets_sold,
    SUM(p.revenue) AS total_revenue,
    AVG(p.revenue) AS avg_revenue_per_order,
    SUM(p.revenue) * 100.0 / SUM(SUM(p.revenue)) OVER() AS revenue_share_percent,
    SUM(p.tickets_count) * 100.0 / NULLIF(SUM(SUM(p.tickets_count)) OVER(), 0) AS tickets_share_percent
FROM purchases p
JOIN events e ON p.event_id = e.event_id
WHERE p.revenue IS NOT NULL AND p.revenue > 0
GROUP BY e.event_type_main
ORDER BY total_revenue DESC;

-- 4. ВЫРУЧКА ПО УСТРОЙСТВАМ
SELECT '4. ВЫРУЧКА ПО УСТРОЙСТВАМ' AS section;

SELECT 
    device_type_canonical,
    COUNT(DISTINCT order_id) AS orders_count,
    SUM(tickets_count) AS tickets_sold,
    SUM(revenue) AS total_revenue,
    AVG(revenue) AS avg_revenue_per_order,
    SUM(revenue) * 100.0 / SUM(SUM(revenue)) OVER() AS revenue_share_percent,
    SUM(tickets_count) * 100.0 / NULLIF(SUM(SUM(tickets_count)) OVER(), 0) AS tickets_share_percent
FROM purchases
WHERE revenue IS NOT NULL AND revenue > 0
GROUP BY device_type_canonical
ORDER BY total_revenue DESC;

-- 5. ВЫРУЧКА ПО РЕГИОНАМ
SELECT '5. ВЫРУЧКА ПО РЕГИОНАМ' AS section;

SELECT 
    r.region_name,
    COUNT(DISTINCT p.order_id) AS orders_count,
    SUM(p.tickets_count) AS tickets_sold,
    SUM(p.revenue) AS total_revenue,
    SUM(p.revenue) * 100.0 / SUM(SUM(p.revenue)) OVER() AS revenue_share_percent
FROM purchases p
JOIN events e ON p.event_id = e.event_id
JOIN city c ON e.city_id = c.city_id
JOIN regions r ON c.region_id = r.region_id
WHERE p.revenue IS NOT NULL AND p.revenue > 0
GROUP BY r.region_name
ORDER BY total_revenue DESC;

-- 6. ТОП-10 МЕРОПРИЯТИЙ ПО ВЫРУЧКЕ
SELECT '6. ТОП-10 МЕРОПРИЯТИЙ ПО ВЫРУЧКЕ' AS section;

SELECT 
    e.event_name_code,
    e.event_type_main,
    COUNT(DISTINCT p.order_id) AS orders_count,
    SUM(p.tickets_count) AS tickets_sold,
    SUM(p.revenue) AS total_revenue,
    AVG(p.revenue) AS avg_revenue_per_order,
    MIN(p.created_dt_msk) AS first_order_date,
    MAX(p.created_dt_msk) AS last_order_date
FROM purchases p
JOIN events e ON p.event_id = e.event_id
WHERE p.revenue IS NOT NULL AND p.revenue > 0
GROUP BY e.event_name_code, e.event_type_main
ORDER BY total_revenue DESC
LIMIT 10;

-- 7. СРЕДНИЙ ЧЕК ПО ДНЯМ НЕДЕЛИ
SELECT '7. СРЕДНИЙ ЧЕК ПО ДНЯМ НЕДЕЛИ' AS section;

SELECT 
    EXTRACT(DOW FROM created_dt_msk) AS day_number,
    CASE EXTRACT(DOW FROM created_dt_msk)
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END AS day_name,
    COUNT(DISTINCT order_id) AS orders_count,
    SUM(revenue) AS total_revenue,
    AVG(revenue) AS avg_revenue_per_order,
    SUM(tickets_count) AS tickets_sold,
    AVG(tickets_count) AS avg_tickets_per_order
FROM purchases
WHERE created_dt_msk IS NOT NULL 
  AND revenue IS NOT NULL 
  AND revenue > 0
GROUP BY EXTRACT(DOW FROM created_dt_msk)
ORDER BY day_number;

-- 8. РАСПРЕДЕЛЕНИЕ ЗАКАЗОВ ПО РАЗМЕРУ ВЫРУЧКИ (корзины)
SELECT '8. РАСПРЕДЕЛЕНИЕ ЗАКАЗОВ ПО РАЗМЕРУ ВЫРУЧКИ' AS section;

SELECT 
    CASE 
        WHEN revenue < 500 THEN 'до 500'
        WHEN revenue < 1000 THEN '500-1000'
        WHEN revenue < 2000 THEN '1000-2000'
        WHEN revenue < 5000 THEN '2000-5000'
        WHEN revenue < 10000 THEN '5000-10000'
        ELSE 'более 10000'
    END AS revenue_bucket,
    COUNT(DISTINCT order_id) AS orders_count,
    SUM(revenue) AS total_revenue,
    AVG(revenue) AS avg_revenue,
    COUNT(DISTINCT user_id) AS unique_users
FROM purchases
WHERE revenue IS NOT NULL AND revenue > 0
GROUP BY 
    CASE 
        WHEN revenue < 500 THEN 'до 500'
        WHEN revenue < 1000 THEN '500-1000'
        WHEN revenue < 2000 THEN '1000-2000'
        WHEN revenue < 5000 THEN '2000-5000'
        WHEN revenue < 10000 THEN '5000-10000'
        ELSE 'более 10000'
    END
ORDER BY MIN(revenue);

-- 9. ВОВЛЕЧЕННОСТЬ ПОЛЬЗОВАТЕЛЕЙ (количество заказов на пользователя)
SELECT '9. ВОВЛЕЧЕННОСТЬ ПОЛЬЗОВАТЕЛЕЙ' AS section;

SELECT 
    user_orders_count,
    COUNT(DISTINCT user_id) AS users_count,
    SUM(user_orders_count) AS total_orders,
    SUM(user_orders_count) * 100.0 / SUM(SUM(user_orders_count)) OVER() AS orders_share_percent
FROM (
    SELECT 
        user_id,
        COUNT(DISTINCT order_id) AS user_orders_count
    FROM purchases
    WHERE revenue IS NOT NULL AND revenue > 0
    GROUP BY user_id
) t
GROUP BY user_orders_count
ORDER BY user_orders_count
LIMIT 20;

-- 10. ДИНАМИКА КОЛИЧЕСТВА ПОЛЬЗОВАТЕЛЕЙ ПО МЕСЯЦАМ
SELECT '10. НОВЫЕ ПОЛЬЗОВАТЕЛИ ПО МЕСЯЦАМ' AS section;

WITH first_orders AS (
    SELECT 
        user_id,
        MIN(created_dt_msk) AS first_order_date
    FROM purchases
    WHERE revenue IS NOT NULL AND revenue > 0
    GROUP BY user_id
)
SELECT 
    DATE_TRUNC('month', first_order_date) AS month,
    COUNT(DISTINCT user_id) AS new_users
FROM first_orders
GROUP BY DATE_TRUNC('month', first_order_date)
ORDER BY month;

-- 11. ДНЕВНАЯ АКТИВНОСТЬ (продажи по часам)
SELECT '11. ПРОДАЖИ ПО ЧАСАМ' AS section;

SELECT 
    EXTRACT(HOUR FROM created_ts_msk) AS hour,
    COUNT(DISTINCT order_id) AS orders_count,
    SUM(revenue) AS total_revenue,
    AVG(revenue) AS avg_revenue,
    SUM(tickets_count) AS tickets_sold
FROM purchases
WHERE created_ts_msk IS NOT NULL 
  AND revenue IS NOT NULL 
  AND revenue > 0
GROUP BY EXTRACT(HOUR FROM created_ts_msk)
ORDER BY hour;

-- 12. ИТОГОВАЯ СВОДКА МЕТРИК
SELECT '12. ИТОГОВАЯ СВОДКА КЛЮЧЕВЫХ МЕТРИК' AS section;

SELECT 
    'Общая выручка' AS metric,
    CAST(SUM(revenue) AS VARCHAR) AS value
FROM purchases
WHERE revenue IS NOT NULL AND revenue > 0
UNION ALL
SELECT 
    'Количество заказов',
    CAST(COUNT(DISTINCT order_id) AS VARCHAR)
FROM purchases
UNION ALL
SELECT 
    'Количество пользователей',
    CAST(COUNT(DISTINCT user_id) AS VARCHAR)
FROM purchases
UNION ALL
SELECT 
    'Продано билетов',
    CAST(SUM(tickets_count) AS VARCHAR)
FROM purchases
WHERE revenue IS NOT NULL AND revenue > 0
UNION ALL
SELECT 
    'Средний чек',
    CAST(AVG(revenue) AS VARCHAR)
FROM purchases
WHERE revenue IS NOT NULL AND revenue > 0
UNION ALL
SELECT 
    'Среднее кол-во билетов в заказе',
    CAST(AVG(tickets_count) AS VARCHAR)
FROM purchases
WHERE revenue IS NOT NULL AND revenue > 0
UNION ALL
SELECT 
    'Максимальный чек',
    CAST(MAX(revenue) AS VARCHAR)
FROM purchases
WHERE revenue IS NOT NULL AND revenue > 0
UNION ALL
SELECT 
    'Минимальный чек',
    CAST(MIN(revenue) AS VARCHAR)
FROM purchases
WHERE revenue IS NOT NULL AND revenue > 0;