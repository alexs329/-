-- Задача 1: Время активности объявлений (оптимизированная версия)

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY COALESCE(balcony, 0)) AS balcony_limit
    FROM real_estate.flats
),

-- Найдём id объявлений, которые не содержат выбросы:
filtered_ids AS (
    SELECT 
        f.id
    FROM real_estate.flats f
    CROSS JOIN limits l
    WHERE 
        f.total_area <= l.total_area_limit
        AND f.rooms <= l.rooms_limit
        AND COALESCE(f.balcony, 0) <= l.balcony_limit
        AND f.total_area > 0
),

-- Основной запрос с упрощенными расчетами:
main_data AS (
    SELECT 
        CASE 
            WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'ЛенОбл'
        END AS region_category,
        
        CASE 
            WHEN a.days_exposition IS NULL OR a.days_exposition = 0 THEN 'non category'
            WHEN a.days_exposition BETWEEN 1 AND 30 THEN 'до месяца'
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'до трех месяцев'
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'до полугода'
            WHEN a.days_exposition > 180 THEN 'более полугода'
        END AS activity_category,
        
        a.last_price / NULLIF(f.total_area, 0) AS price_per_m2,
        f.total_area,
        f.rooms
        
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.city c ON f.city_id = c.city_id
    JOIN real_estate.type t ON f.type_id = t.type_id
    JOIN filtered_ids fi ON fi.id = a.id  -- Исправлено: JOIN вместо IN
    
    WHERE EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018
      AND t.type = 'город'
      AND (c.city = 'Санкт-Петербург' OR c.city IN ('Всеволожск', 'Гатчина', 'Выборг'))
)

-- Финальный запрос с основными метрики:
SELECT 
    region_category AS "Регион",
    activity_category AS "Сегмент активности",
    
    COUNT(*) AS "Количество объявлений",
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(PARTITION BY region_category), 2) AS "Доля в регионе, %",
    
    ROUND(AVG(price_per_m2)::numeric, 2) AS "Средняя стоимость кв. метра",
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_per_m2)::numeric, 2) AS "Медиана стоимости кв. метра",
    
    ROUND(AVG(total_area)::numeric, 2) AS "Средняя площадь",
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_area)::numeric, 2) AS "Медиана площади",
    
    ROUND(AVG(rooms)::numeric, 2) AS "Среднее кол-во комнат"
    
FROM main_data
GROUP BY region_category, activity_category
ORDER BY 
    CASE region_category 
        WHEN 'Санкт-Петербург' THEN 1 
        ELSE 2 
    END,
    CASE activity_category
        WHEN 'non category' THEN 1
        WHEN 'до месяца' THEN 2
        WHEN 'до трех месяцев' THEN 3
        WHEN 'до полугода' THEN 4
        WHEN 'более полугода' THEN 5
    END;
-- Задача 2: Сезонность объявлений (оптимизированная версия)

-- Определяем пороги динамически через перцентили
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY COALESCE(balcony, 0)) AS balcony_limit
    FROM real_estate.flats
),

-- Фильтруем данные с динамическими порогами
filtered_data AS (
    SELECT 
        a.id,
        a.first_day_exposition,
        a.days_exposition,
        a.last_price,
        f.total_area,
        f.rooms,
        COALESCE(f.balcony, 0) as balcony,
        c.city,
        t.type,
        
        -- Регион
        CASE 
            WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'ЛенОбл'
        END AS region,
        
        -- Месяц публикации
        EXTRACT(MONTH FROM a.first_day_exposition) AS publication_month,
        
        -- Год публикации
        EXTRACT(YEAR FROM a.first_day_exposition) AS publication_year,
        
        -- Месяц снятия (если объявление снято)
        CASE 
            WHEN a.days_exposition > 0 
            THEN EXTRACT(MONTH FROM a.first_day_exposition + INTERVAL '1 day' * a.days_exposition)
        END AS removal_month,
        
        -- Год снятия (если объявление снято)
        CASE 
            WHEN a.days_exposition > 0 
            THEN EXTRACT(YEAR FROM a.first_day_exposition + INTERVAL '1 day' * a.days_exposition)
        END AS removal_year
        
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.city c ON f.city_id = c.city_id
    JOIN real_estate.type t ON f.type_id = t.type_id
    CROSS JOIN limits l
    
    WHERE EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018
      AND t.type = 'город'
      AND (c.city = 'Санкт-Петербург' OR c.city IN ('Всеволожск', 'Гатчина', 'Выборг'))
      -- Фильтрация по динамическим порогам (убрано f.rooms > 0 для студий)
      AND f.total_area <= l.total_area_limit
      AND f.total_area > 0
      AND f.rooms <= l.rooms_limit
      -- Убрано: AND f.rooms > 0 (чтобы оставить студии)
      AND COALESCE(f.balcony, 0) <= l.balcony_limit
),

-- Данные по публикациям
publication_stats AS (
    SELECT 
        region,
        publication_year,
        publication_month,
        COUNT(*) AS publications_count,
        ROUND(AVG(last_price / NULLIF(total_area, 0))::numeric, 2) AS avg_price_per_m2,
        ROUND(AVG(total_area)::numeric, 2) AS avg_total_area,
        ROUND(AVG(rooms)::numeric, 2) AS avg_rooms,
        ROUND(AVG(CASE WHEN days_exposition > 0 THEN days_exposition END)::numeric, 2) AS avg_time_to_sell
    FROM filtered_data
    GROUP BY region, publication_year, publication_month
),

-- Данные по снятиям
removal_stats AS (
    SELECT 
        region,
        removal_year,
        removal_month,
        COUNT(*) AS removals_count
    FROM filtered_data
    WHERE removal_month IS NOT NULL
    GROUP BY region, removal_year, removal_month
)

-- Финальный запрос с объединением данных по публикациям и снятиям
SELECT 
    COALESCE(p.region, r.region) AS "Регион",
    COALESCE(p.publication_year, r.removal_year) AS "Год",
    COALESCE(p.publication_month, r.removal_month) AS "Месяц",
    
    -- Метрики по публикациям
    COALESCE(p.publications_count, 0) AS "Количество публикаций",
    
    -- Метрики по снятиям
    COALESCE(r.removals_count, 0) AS "Количество снятий",
    ROUND(
        CASE 
            WHEN COALESCE(p.publications_count, 0) > 0 
            THEN COALESCE(r.removals_count, 0) * 100.0 / p.publications_count
            ELSE 0 
        END, 2
    ) AS "Процент снятий, %",
    
    -- Характеристики объектов
    p.avg_price_per_m2 AS "Средняя стоимость кв. метра",
    p.avg_total_area AS "Средняя площадь",
    p.avg_rooms AS "Среднее кол-во комнат",
    p.avg_time_to_sell AS "Среднее время до продажи, дней"
    
FROM publication_stats p
FULL OUTER JOIN removal_stats r 
    ON p.region = r.region 
    AND p.publication_year = r.removal_year 
    AND p.publication_month = r.removal_month
    
WHERE COALESCE(p.publication_year, r.removal_year) BETWEEN 2015 AND 2018
    
ORDER BY 
    COALESCE(p.region, r.region),
    COALESCE(p.publication_year, r.removal_year),
    COALESCE(p.publication_month, r.removal_month);