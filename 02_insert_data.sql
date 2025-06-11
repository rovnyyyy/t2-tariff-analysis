-- 1. Данные о тарифах
INSERT INTO tariffs (
    tariff_name,
    messages_included,
    mb_per_month_included,
    minutes_included,
    rub_monthly_fee,
    rub_per_gb,
    rub_per_message,
    rub_per_minute
)
VALUES 
    ('Online', 50, 60 * 1024, 100, 750, 100, 3, 1),
    ('Black', 1000, 50 * 1024, 1200, 1000, 50, 1, 0.5);

-- 2. Данные о пользователях 
INSERT INTO users (user_id, age, city, first_name, last_name, reg_date, churn_date, tariff)
SELECT 
    i AS user_id,
    18 + (i % 43) AS age,
    CASE 
        WHEN i % 3 = 0 THEN 'Москва'
        WHEN i % 3 = 1 THEN 'СПб'
        ELSE 'Казань'
    END AS city,
    'User_' || i AS first_name,
    'Test_' || i AS last_name,
    DATE '2021-01-01' + (i % 730) AS reg_date,
    CASE 
        WHEN i <= 190 THEN NULL
        ELSE DATE '2023-12-31' - (i % 100)
    END AS churn_date,
    CASE 
        WHEN i % 3 = 0 THEN 'Black'
        ELSE 'Online'
    END AS tariff
FROM generate_series(1, 200) AS s(i);

-- 3. Данные о звонках
INSERT INTO calls (call_date, duration, user_id)
SELECT
    CURRENT_DATE - (i % 360), -- данные за последний год 
    round((random() * 10 + 0.5)::numeric, 2),
    (random() * 139 + 1)::int
FROM generate_series(1, 3000) AS s(i);

-- 4. Данные о СМС
INSERT INTO messages (message_date, user_id)
SELECT
    CURRENT_DATE - (i % 360),
    u.user_id
FROM (
    SELECT user_id, age
    FROM users
    WHERE user_id IS NOT NULL
    ORDER BY random()
    LIMIT 500  -- Отберём 500 пользователей
) AS u,
generate_series(1, 10) AS s(i)
WHERE (
    (u.age < 25 AND random() < 0.1) OR
    (u.age BETWEEN 25 AND 45 AND random() < 0.3) OR
    (u.age > 45 AND random() < 0.5)
)
LIMIT 1000;

-- 5. Данные о интернет трафике
TRUNCATE TABLE internet;

INSERT INTO internet (session_date, mb_used, user_id)
SELECT
    CURRENT_DATE - (i % 360),
    ROUND(
        CASE
            WHEN random() < 0.1 THEN 0
            WHEN random() < 0.15 THEN (random() * 7000 + 8000)  -- 6-13 Гб, чтобы был небольшой овер
            ELSE random() * 6000                               -- до 6 Гб в остальных сессиях
        END
        ::numeric, 2
    ),
    u.user_id
FROM (
    SELECT user_id
    FROM users
    WHERE random() < 0.8
    ORDER BY random()
    LIMIT 300
) AS u,
generate_series(1, 10) AS s(i);
