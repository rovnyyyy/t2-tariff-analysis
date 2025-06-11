CREATE TABLE tariffs (
    tariff_name character VARYING PRIMARY KEY,
    messages_included INTEGER,
    mb_per_month_included INTEGER,
    minutes_included INTEGER,
    rub_monthly_fee INTEGER,
    rub_per_gb NUMERIC,
    rub_per_message NUMERIC,
    rub_per_minute NUMERIC
);

DROP TABLE IF EXISTS users CASCADE;

CREATE TABLE users (
    user_id     INT PRIMARY KEY,
    age         INT,
    city        VARCHAR(50),
    first_name  VARCHAR(50),
    last_name   VARCHAR(50),
    reg_date    DATE,
    churn_date  DATE,
    tariff      VARCHAR(50)
);

CREATE TABLE calls (
    id SERIAL PRIMARY KEY,
    call_date DATE,
    duration NUMERIC,
    user_id INTEGER
);

CREATE TABLE internet (
    id SERIAL PRIMARY KEY,
    session_date DATE,
    mb_used NUMERIC,
    user_id INTEGER REFERENCES users(user_id)
);

CREATE TABLE messages (
    id SERIAL PRIMARY KEY,
    message_date DATE,
    user_id INTEGER
);
