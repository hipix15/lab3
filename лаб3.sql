BEGIN;

-- Удаляем тестовые записи от предыдущего запуска, если они остались.
DELETE FROM public.mail_acceptance
WHERE tracking_number IN ('LAB3-NO-ACCEPT-26', 'LAB3-ORPHAN-26');

DELETE FROM public.correspondence
WHERE tracking_number = 'LAB3-NO-ACCEPT-26';


-- 1. Проверить обеспечение ссылочной целостности данных в базе данных.
-- Просмотр первичных и внешних ключей двух таблиц.
SELECT
    conrelid::regclass AS table_name,
    conname AS constraint_name,
    CASE contype
        WHEN 'p' THEN 'PRIMARY KEY'
        WHEN 'f' THEN 'FOREIGN KEY'
    END AS constraint_type,
    pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid IN (
    'public.correspondence'::regclass,
    'public.mail_acceptance'::regclass
)
AND contype IN ('p', 'f')
ORDER BY table_name, constraint_type;


-- При исправной ссылочной целостности запрос вернёт 0 строк.
SELECT
    ma.tracking_number,
    ma.postal_office_code,
    ma.accepted_at
FROM public.mail_acceptance AS ma
LEFT JOIN public.correspondence AS c
    ON c.tracking_number = ma.tracking_number
WHERE c.tracking_number IS NULL;


-- Добавляем зарегистрированную корреспонденцию,
-- которая не поступала ни в одно почтовое отделение.
INSERT INTO public.correspondence (
    tracking_number,
    correspondence_type_code,
    weight_g,
    length_cm,
    width_cm,
    height_cm,
    sender_code,
    stamp_amount
)
VALUES (
    'LAB3-NO-ACCEPT-26',
    1,
    120.00,
    20.00,
    15.00,
    2.00,
    9999,
    50.00
);


-- 2. Нарушить ссылочную целостность данных.
-- Временно удаляем внешний ключ из mail_acceptance
-- на correspondence.
DO $$
DECLARE
    fk RECORD;
BEGIN
    FOR fk IN
        SELECT conname
        FROM pg_constraint
        WHERE conrelid = 'public.mail_acceptance'::regclass
          AND confrelid = 'public.correspondence'::regclass
          AND contype = 'f'
    LOOP
        EXECUTE format(
            'ALTER TABLE public.mail_acceptance DROP CONSTRAINT %I',
            fk.conname
        );
    END LOOP;
END;
$$;


-- Добавляем приём корреспонденции с трек-номером,
-- которого нет в таблице correspondence.
INSERT INTO public.mail_acceptance (
    postal_office_code,
    tracking_number,
    accepted_at,
    declared_value,
    total_shipping_cost,
    paid,
    sent_at
)
VALUES (
    '999999',
    'LAB3-ORPHAN-26',
    LOCALTIMESTAMP,
    0.00,
    100.00,
    FALSE,
    NULL
);


-- 3. Выполнить запрос с левосторонним соединением.
-- Показывает всю зарегистрированную корреспонденцию.
-- Если записи о приёме нет, поля mail_acceptance будут NULL.
SELECT
    c.tracking_number AS correspondence_tracking_number,
    c.correspondence_type_code,
    c.weight_g,
    c.length_cm,
    c.width_cm,
    c.height_cm,
    c.sender_code,
    c.stamp_amount,
    ma.tracking_number AS acceptance_tracking_number,
    ma.postal_office_code,
    ma.accepted_at,
    ma.declared_value,
    ma.total_shipping_cost,
    ma.paid,
    ma.sent_at
FROM public.correspondence AS c
LEFT JOIN public.mail_acceptance AS ma
    ON ma.tracking_number = c.tracking_number
ORDER BY
    c.tracking_number,
    ma.postal_office_code,
    ma.accepted_at;


-- 4. Выполнить запрос с правосторонним соединением.
-- Показывает все записи о приёме.
-- Если корреспонденция не зарегистрирована,
-- поля correspondence будут NULL.
SELECT
    c.tracking_number AS correspondence_tracking_number,
    c.correspondence_type_code,
    c.weight_g,
    c.length_cm,
    c.width_cm,
    c.height_cm,
    c.sender_code,
    c.stamp_amount,
    ma.tracking_number AS acceptance_tracking_number,
    ma.postal_office_code,
    ma.accepted_at,
    ma.declared_value,
    ma.total_shipping_cost,
    ma.paid,
    ma.sent_at
FROM public.correspondence AS c
RIGHT JOIN public.mail_acceptance AS ma
    ON ma.tracking_number = c.tracking_number
ORDER BY
    ma.tracking_number,
    ma.postal_office_code,
    ma.accepted_at;


-- Основной запрос по варианту 26.
-- FULL OUTER JOIN показывает всю корреспонденцию и все записи о её приёме.
-- При отсутствии пары поля соответствующей таблицы будут NULL.
SELECT
    COALESCE(c.tracking_number, ma.tracking_number) AS tracking_number,

    c.tracking_number AS correspondence_tracking_number,
    c.correspondence_type_code,
    c.weight_g,
    c.length_cm,
    c.width_cm,
    c.height_cm,
    c.sender_code,
    c.stamp_amount,

    ma.tracking_number AS acceptance_tracking_number,
    ma.postal_office_code,
    ma.accepted_at,
    ma.declared_value,
    ma.total_shipping_cost,
    ma.paid,
    ma.sent_at
FROM public.correspondence AS c
FULL OUTER JOIN public.mail_acceptance AS ma
    ON ma.tracking_number = c.tracking_number
ORDER BY
    COALESCE(c.tracking_number, ma.tracking_number),
    ma.postal_office_code,
    ma.accepted_at;


-- 5. Выявить записи без соответствия.
-- Здесь будут видны оба тестовых случая:
-- correspondence без приёма и приём незарегистрированной корреспонденции.
SELECT
    CASE
        WHEN c.tracking_number IS NULL
            THEN 'Acceptance without registered correspondence'
        WHEN ma.tracking_number IS NULL
            THEN 'Correspondence without acceptance'
    END AS situation,
    COALESCE(c.tracking_number, ma.tracking_number) AS tracking_number,
    c.tracking_number AS correspondence_tracking_number,
    ma.tracking_number AS acceptance_tracking_number,
    ma.postal_office_code,
    ma.accepted_at
FROM public.correspondence AS c
FULL OUTER JOIN public.mail_acceptance AS ma
    ON ma.tracking_number = c.tracking_number
WHERE c.tracking_number IS NULL
   OR ma.tracking_number IS NULL
ORDER BY
    COALESCE(c.tracking_number, ma.tracking_number),
    ma.postal_office_code,
    ma.accepted_at;


-- Удаляем тестовое нарушение и тестовое отправление.
DELETE FROM public.mail_acceptance
WHERE tracking_number = 'LAB3-ORPHAN-26';

DELETE FROM public.mail_acceptance
WHERE tracking_number = 'LAB3-NO-ACCEPT-26';

DELETE FROM public.correspondence
WHERE tracking_number = 'LAB3-NO-ACCEPT-26';


-- Восстанавливаем ссылочную целостность.
ALTER TABLE public.mail_acceptance
ADD CONSTRAINT fk_mail_acceptance_correspondence
FOREIGN KEY (tracking_number)
REFERENCES public.correspondence (tracking_number)
ON UPDATE CASCADE
ON DELETE CASCADE;


-- Проверяем, что внешний ключ восстановлен.
SELECT
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.mail_acceptance'::regclass
  AND confrelid = 'public.correspondence'::regclass
  AND contype = 'f';


-- Проверяем, что приёмов незарегистрированной корреспонденции не осталось.
-- После восстановления связи результат должен быть 0.
SELECT COUNT(*) AS orphan_acceptance_count
FROM public.mail_acceptance AS ma
LEFT JOIN public.correspondence AS c
    ON c.tracking_number = ma.tracking_number
WHERE c.tracking_number IS NULL;

COMMIT;