-- 1. Выгрузим первые 20 строк с информацией о пользователях и проверим, 
--    что данные соответствуют описанию.
SELECT * 
FROM users 
LIMIT 20;

-- 2. Проверим, что в данных для каждого пользователя нет пропусков.
SELECT *
FROM users 
WHERE churn_date IS NULL OR last_name IS NULL OR churn_date IS NULL
limit 10;
-- Обнаружены пропуски в столбце churn_date
-- churn_date хранит дату отказа от услуг, и отсутствие информации говорит о том, 
-- что клиент продолжает пользоваться услугами оператора.

-- 3. Посичтает процент активных клиентов.
SELECT 
    CAST(count(*) FILTER (WHERE churn_date IS NULL) AS REAL) / count(*) AS active_clients_ratio
FROM users;

-- 4. Необходимо убедиться, что у каждого пользователя только один тарифный план
SELECT 
	user_id
	, count(tariff)
FROM users
WHERE churn_date IS NULL 
GROUP BY user_id 
HAVING count(tariff) > 1 
-- Клиентов с несколькими тарифами нет.

-- 5. Проверим наличие пропусков в таблице calls
SELECT *
FROM calls
WHERE duration = 0 AND call_date IS NULL AND duration IS NULL

-- 6. Проверим наличие аномалий на длительность разговоров
SELECT
    MIN(duration) AS min_duration
    , MAX(duration) AS max_duration
FROM calls;
-- Аномалий не обнаружено. 
-- Минимальная длительность разговора - 30 секунд.
-- Максимальная 10,5 минут.

-- 7. Использование трафика клиента в месяц 
-- 7.1. Посчитаем суммарную длительность разговоров
WITH monthly_duration AS (
SELECT 
    user_id
	, DATE_TRUNC('month', call_date::timestamp)::DATE AS dt_month
    , CEIL(sum(duration)*10) AS month_duration
FROM calls AS c
GROUP BY user_id, DATE_TRUNC('month', call_date::timestamp)::DATE
)
SELECT *
FROM monthly_duration
limit 5;

-- 7.2. Суммарное количество потраченного интернет-трафика
WITH monthly_internet AS (
SELECT 
	user_id
	, DATE_TRUNC('month', session_date ::timestamp)::date AS dt_month
	, ROUND(sum(mb_used)/1024, 2) AS total
FROM internet i 
GROUP BY user_id, DATE_TRUNC('month', session_date ::timestamp)::date
ORDER BY total DESC 
)
SELECT *
FROM monthly_internet
limit 5;

-- 7.3 -- Суммарное количество сообщений в месяц:
WITH monthly_sms AS (
    SELECT 
    	user_id
    	, DATE_TRUNC('month', message_date::timestamp)::date AS dt_month
		, COUNT(message_date) AS month_sms
    FROM messages
    GROUP BY user_id, dt_month
)
SELECT *
FROM monthly_sms
limit 5;

-- 8. Общий 
-- СТЕ. Месячные метрики активности calls
WITH monthly_duration AS (
    SELECT user_id
		, DATE_TRUNC('month', call_date::timestamp)::date AS dt_month
		, CEIL(SUM(duration)) AS month_duration
    FROM calls
    GROUP BY user_id, dt_month
), 
-- СТЕ. Месячные метрики активности internet
monthly_internet AS (
    SELECT user_id
		, DATE_TRUNC('month', session_date::timestamp)::date AS dt_month
		, ROUND(SUM(mb_used), 2) AS month_mb_traffic
    FROM internet
    GROUP BY user_id, dt_month
), 
-- СТЕ. Месячные метрики активности messages
monthly_sms AS (
    SELECT user_id
		, DATE_TRUNC('month', message_date::timestamp)::date AS dt_month
		, COUNT(*) AS month_sms
    FROM messages
    GROUP BY user_id, dt_month
), 
-- СТЕ. Полный список «пользователь – месяц»
user_activity_months AS (
    SELECT user_id, dt_month FROM monthly_duration
    UNION
    SELECT user_id, dt_month FROM monthly_internet
    UNION
    SELECT user_id, dt_month FROM monthly_sms
), 
-- СТЕ. Сводим метрики в одну таблицу
users_stat AS (
    SELECT 
        u.user_id
        , u.dt_month
        , md.month_duration
        , mi.month_mb_traffic
        , mm.month_sms
    FROM user_activity_months AS u
    LEFT JOIN monthly_duration md ON u.user_id = md.user_id AND u.dt_month = md.dt_month
    LEFT JOIN monthly_internet mi ON u.user_id = mi.user_id AND u.dt_month = mi.dt_month
    LEFT JOIN monthly_sms mm ON u.user_id = mm.user_id AND u.dt_month = mm.dt_month
), 
-- СТЕ. Перерасход относительно лимитов тарифа 
user_over_limits AS (
    SELECT
        us.user_id
        , us.dt_month
        , uu.tariff
        , us.month_duration
        , us.month_mb_traffic
        , us.month_sms
        , CASE 
	        WHEN us.month_duration > t.minutes_included      
	        THEN us.month_duration - t.minutes_included      
	        ELSE 0 
	        END AS duration_over
		, CASE
			WHEN us.month_mb_traffic > t.mb_per_month_included
      		THEN ROUND((us.month_mb_traffic - t.mb_per_month_included) / 1024, 2)
      		ELSE 0
  END AS gb_traffic_over
        , CASE 
	        WHEN us.month_sms > t.messages_included     
			THEN  us.month_sms - t.messages_included     
			ELSE 0 
			END AS sms_over
    FROM users_stat us
    LEFT JOIN users uu ON us.user_id = uu.user_id
    JOIN tariffs t ON t.tariff_name = uu.tariff
),
-- СТЕ. Траты клиента за месяц
users_costs AS (
    SELECT  
    	uo.user_id
		, uo.dt_month
		, uo.tariff
		, uo.month_duration
		, uo.month_mb_traffic
		, uo.month_sms
		, t.rub_monthly_fee
		, t.rub_monthly_fee + uo.duration_over * t.rub_per_minute + uo.gb_traffic_over * t.rub_per_gb + uo.sms_over * t.rub_per_message AS total_cost
    FROM user_over_limits uo
    JOIN tariffs t  ON t.tariff_name = uo.tariff
)
-- Средние траты в месяц для каждого тарифа
SELECT tariff 
		, COUNT(DISTINCT user_id) AS total_users
		, ROUND(AVG(total_cost)::numeric, 2) AS avg_total_cost
		, ROUND(AVG(total_cost - rub_monthly_fee), 2) AS avg_overcost
FROM users_costs
-- Берем только активных клиентов:
WHERE user_id IN (SELECT user_id FROM users WHERE churn_date IS NULL)
-- Отбираем клиентов с тратами выше, чем ежемесячный платеж
AND total_cost > rub_monthly_fee 
GROUP BY tariff;

-- 9. Отклонение затрат пользователя от среднего по тарифу (использование оконных функций)
-- СТЕ. Месячные метрики активности calls
WITH monthly_duration AS (
    SELECT user_id
		, DATE_TRUNC('month', call_date::timestamp)::date AS dt_month
		, CEIL(SUM(duration)) AS month_duration
    FROM calls
    GROUP BY user_id, dt_month
), 
-- СТЕ. Месячные метрики активности internet
monthly_internet AS (
    SELECT user_id
		, DATE_TRUNC('month', session_date::timestamp)::date AS dt_month
		, ROUND(SUM(mb_used), 2) AS month_mb_traffic
    FROM internet
    GROUP BY user_id, dt_month
), 
-- СТЕ. Месячные метрики активности messages
monthly_sms AS (
    SELECT user_id
		, DATE_TRUNC('month', message_date::timestamp)::date AS dt_month
		, COUNT(*) AS month_sms
    FROM messages
    GROUP BY user_id, dt_month
), 
-- СТЕ. Полный список «пользователь – месяц»
user_activity_months AS (
    SELECT user_id, dt_month FROM monthly_duration
    UNION
    SELECT user_id, dt_month FROM monthly_internet
    UNION
    SELECT user_id, dt_month FROM monthly_sms
), 
-- СТЕ. Сводим метрики в одну таблицу
users_stat AS (
    SELECT 
        u.user_id
        , u.dt_month
        , md.month_duration
        , mi.month_mb_traffic
        , mm.month_sms
    FROM user_activity_months AS u
    LEFT JOIN monthly_duration md ON u.user_id = md.user_id AND u.dt_month = md.dt_month
    LEFT JOIN monthly_internet mi ON u.user_id = mi.user_id AND u.dt_month = mi.dt_month
    LEFT JOIN monthly_sms mm ON u.user_id = mm.user_id AND u.dt_month = mm.dt_month
), 
-- СТЕ. Перерасход относительно лимитов тарифа 
user_over_limits AS (
    SELECT
        us.user_id
        , us.dt_month
        , uu.tariff
        , us.month_duration
        , us.month_mb_traffic
        , us.month_sms
        , CASE 
	        WHEN us.month_duration > t.minutes_included      
	        THEN us.month_duration - t.minutes_included      
	        ELSE 0 
	        END AS duration_over
		, CASE
			WHEN us.month_mb_traffic > t.mb_per_month_included
      		THEN ROUND((us.month_mb_traffic - t.mb_per_month_included) / 1024, 2)
      		ELSE 0
  END AS gb_traffic_over
        , CASE 
	        WHEN us.month_sms > t.messages_included     
			THEN  us.month_sms - t.messages_included     
			ELSE 0 
			END AS sms_over
    FROM users_stat us
    LEFT JOIN users uu ON us.user_id = uu.user_id
    JOIN tariffs t ON t.tariff_name = uu.tariff
),
-- СТЕ. Траты клиента за месяц
users_costs AS (
    SELECT  
        uo.user_id
        , uo.dt_month
        , uo.tariff
        , uo.month_duration
        , uo.month_mb_traffic
        , uo.month_sms
        , t.rub_monthly_fee
		, t.rub_monthly_fee 
            + uo.duration_over * t.rub_per_minute
            + uo.gb_traffic_over * t.rub_per_gb
            + uo.sms_over * t.rub_per_message AS total_cost
    FROM user_over_limits uo
    JOIN tariffs t  ON t.tariff_name = uo.tariff
),
costs_with_avg AS (
    SELECT
        user_id
        , dt_month
        , tariff
        , total_cost
        , AVG(total_cost) OVER (PARTITION BY tariff, dt_month) AS avg_cost_by_tariff_month
		, total_cost - AVG(total_cost) OVER (PARTITION BY tariff, dt_month) AS deviation_from_avg
    FROM users_costs
)
SELECT
    user_id
    , dt_month
    , tariff
	, total_cost
    , avg_cost_by_tariff_month
    , deviation_from_avg
FROM costs_with_avg
ORDER BY user_id
LIMIT 50;

-- 10.1 Анализ звонков: кто говорит больше/меньше среднего по месяцу
WITH monthly_duration AS (
    SELECT user_id
		, DATE_TRUNC('month', call_date::timestamp)::date AS dt_month
		, CEIL(SUM(duration)) AS month_duration
    FROM calls
    GROUP BY user_id, dt_month
)
SELECT
    user_id,
    dt_month,
    month_duration, -- длительность звонков в месяц
    ROUND(AVG(month_duration) OVER (PARTITION BY dt_month), 2) AS avg_duration_by_month, -- средняя длительность звонков в месяц
    month_duration - ROUND(AVG(month_duration) OVER (PARTITION BY dt_month), 2) AS deviation -- насколько пользователь использовал больше или меньше минут, чем в среднем по всем пользователям за тот же месяц
FROM monthly_duration
ORDER BY user_id
LIMIT 10;

-- 10.2 Анализ интернет-трафика: кто использует больше/меньше МБ
WITH monthly_internet AS (
    SELECT user_id
		, DATE_TRUNC('month', session_date::timestamp)::date AS dt_month
		, ROUND(SUM(mb_used), 2) AS month_mb_traffic			
    FROM internet
    GROUP BY user_id, dt_month
)
SELECT
    user_id,
    dt_month,
    month_mb_traffic, -- интернет-трафик в месяц
    ROUND(AVG(month_mb_traffic) OVER (PARTITION BY dt_month), 2) AS avg_traffic_by_month, -- среднее использование трафика в месяц
    month_mb_traffic - ROUND(AVG(month_mb_traffic) OVER (PARTITION BY dt_month), 2) AS deviation -- насколько пользователь использовал больше или меньше трафика, чем в среднем по всем пользователям за тот же месяц
FROM monthly_internet
ORDER BY user_id
LIMIT 10;

-- 10.3 Анализ смс: кто шлет много сообщений, а кто мало
WITH monthly_sms AS (
    SELECT user_id
		, DATE_TRUNC('month', message_date::timestamp)::date AS dt_month
		, COUNT(*) AS month_sms
    FROM messages
    GROUP BY user_id, dt_month
)
SELECT
    user_id,
    dt_month,
    month_sms, -- cмс в месяц
    ROUND(AVG(month_sms) OVER (PARTITION BY dt_month), 2) AS avg_sms_by_month, -- среднее количество отправленных смс в месяц
    month_sms - ROUND(AVG(month_sms) OVER (PARTITION BY dt_month), 2) AS deviation -- насколько пользователь отправил больше или меньше смс, чем в среднем по всем пользователям за тот же месяц
FROM monthly_sms
ORDER BY user_id
LIMIT 10;

-- 11. Анализ интернет-трафика пользователя в сравнении с прошлым месяцем
SELECT
    user_id,
    DATE_TRUNC('month', session_date::timestamp)::date AS dt_month,
    ROUND(SUM(mb_used), 2) AS month_mb_traffic,
    ROUND(AVG(SUM(mb_used)) OVER (PARTITION BY user_id ORDER BY DATE_TRUNC('month', session_date::timestamp)::date ROWS BETWEEN 1 PRECEDING AND CURRENT ROW), 2) AS rolling_avg,
    SUM(mb_used) - LAG(SUM(mb_used)) OVER (PARTITION BY user_id ORDER BY DATE_TRUNC('month', session_date::timestamp)::date) AS traffic_change
FROM internet
GROUP BY user_id, dt_month
ORDER BY user_id, dt_month;
