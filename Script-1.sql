-- Часть 1. Исследовательский анализ данных

-- 1.1. Доля платящих пользователей по всем данным:
SELECT
    COUNT(*) AS total_players,
    COUNT(CASE WHEN payer = 1 THEN 1 END) AS paying_players,
    (COUNT(CASE WHEN payer = 1 THEN 1 END) * 100.0 / COUNT(*))::numeric(10,2) AS paying_players_percentage
FROM fantasy.users;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
SELECT
    race_id AS character_race,
    COUNT(CASE WHEN payer = 1 THEN 1 END) AS paying_players,
    COUNT(*) AS total_players,
    (COUNT(CASE WHEN payer = 1 THEN 1 END) * 100.0 / COUNT(*))::numeric(10,2) AS paying_players_percentage
FROM fantasy.users
GROUP BY race_id
ORDER BY paying_players_percentage DESC;

-- Задача 2. Исследование внутриигровых покупок

-- 2.1. Статистические показатели по полю amount:
SELECT
    COUNT(*) AS total_purchases,
    COUNT(amount) AS purchases_with_amount,
    SUM(amount) AS total_amount,
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount,
    AVG(amount)::numeric(10,2) AS avg_amount,
    STDDEV(amount)::numeric(10,2) AS stddev_amount
FROM fantasy.events
WHERE amount IS NOT NULL;

-- 2.2: Медиана стоимости покупок:
SELECT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount)::numeric(10,2) AS median_amount
FROM fantasy.events
WHERE amount IS NOT NULL;

-- 2.3: Популярные эпические предметы:
WITH filtered_purchases AS (
    SELECT 
        item_code,
        seller_id,
        amount
    FROM fantasy.events
    WHERE amount IS NOT NULL 
        AND amount > 0
),
total_stats AS (
    SELECT 
        COUNT(*) AS total_sales,
        COUNT(DISTINCT seller_id) AS total_unique_buyers
    FROM filtered_purchases
),
item_stats AS (
    SELECT 
        item_code,
        COUNT(*) AS item_sales_count,
        COUNT(DISTINCT seller_id) AS item_unique_buyers
    FROM filtered_purchases
    GROUP BY item_code
)
SELECT 
    i.item_code,
    i.item_sales_count,
    (i.item_sales_count * 100.0 / t.total_sales)::numeric(10,2) AS sales_percentage,
    i.item_unique_buyers,
    (i.item_unique_buyers * 100.0 / t.total_unique_buyers)::numeric(10,2) AS buyers_percentage
FROM item_stats i
CROSS JOIN total_stats t
ORDER BY i.item_unique_buyers DESC, i.item_sales_count DESC;

-- Часть 2. Решение ad hoc-задачи
-- Задача: Зависимость активности игроков от расы персонажа
