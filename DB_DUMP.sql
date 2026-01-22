--
-- PostgreSQL database dump
--

-- Dumped from database version 17.2
-- Dumped by pg_dump version 17.2

-- Started on 2026-01-22 18:27:32

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 5066 (class 1262 OID 16991)
-- Name: school_hr_db; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE school_hr_db WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'Russian_Russia.1251';


ALTER DATABASE school_hr_db OWNER TO postgres;

\connect school_hr_db

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 5067 (class 0 OID 0)
-- Dependencies: 5066
-- Name: DATABASE school_hr_db; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON DATABASE school_hr_db IS 'Микросервис для кадрового учета сотрудников онлайн-школы';


--
-- TOC entry 259 (class 1255 OID 17130)
-- Name: add_new_teacher(character varying, character varying, character varying, date, character varying, jsonb, jsonb, jsonb, jsonb); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.add_new_teacher(IN p_first_name character varying, IN p_last_name character varying, IN p_middle_name character varying, IN p_birth_date date, IN p_gender character varying, IN p_emails jsonb, IN p_phone_numbers jsonb, IN p_subjects jsonb, IN p_education jsonb)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_employee_id INTEGER;
    v_subject JSONB;
    v_edu JSONB;
BEGIN
    -- Вставка в employees
    INSERT INTO employees (
        first_name, last_name, middle_name, birth_date, gender,
        emails, phone_numbers, is_teacher, employee_type
    ) VALUES (
        p_first_name, p_last_name, p_middle_name, p_birth_date, p_gender,
        p_emails, p_phone_numbers, true, 'teacher'
    ) RETURNING id INTO v_employee_id;
    
    -- Добавление предметов
    FOR v_subject IN SELECT * FROM jsonb_array_elements(p_subjects)
    LOOP
        INSERT INTO teacher_subjects (
            employee_id, subject_name, age_group, qualification_level
        ) VALUES (
            v_employee_id,
            v_subject->>'subject',
            v_subject->>'age_group',
            COALESCE(v_subject->>'qualification', 'beginner')
        );
    END LOOP;
    
    -- Добавление образования
    FOR v_edu IN SELECT * FROM jsonb_array_elements(p_education)
    LOOP
        INSERT INTO education (
            employee_id, institution_name, specialty, graduation_year,
            education_type
        ) VALUES (
            v_employee_id,
            v_edu->>'institution',
            v_edu->>'specialty',
            (v_edu->>'year')::INTEGER,
            'higher_bachelor' -- предполагаем высшее, можно параметризовать
        );
    END LOOP;
    
    COMMIT;
END;
$$;


ALTER PROCEDURE public.add_new_teacher(IN p_first_name character varying, IN p_last_name character varying, IN p_middle_name character varying, IN p_birth_date date, IN p_gender character varying, IN p_emails jsonb, IN p_phone_numbers jsonb, IN p_subjects jsonb, IN p_education jsonb) OWNER TO postgres;

--
-- TOC entry 260 (class 1255 OID 17142)
-- Name: audit_trigger_function(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.audit_trigger_function() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO audit_log (table_name, record_id, action, old_data, changed_by)
        VALUES (TG_TABLE_NAME, OLD.id, 'DELETE', row_to_json(OLD), current_user);
        RETURN OLD;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO audit_log (table_name, record_id, action, old_data, new_data, changed_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'UPDATE', row_to_json(OLD), row_to_json(NEW), current_user);
        RETURN NEW;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'INSERT', row_to_json(NEW), current_user);
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.audit_trigger_function() OWNER TO postgres;

--
-- TOC entry 261 (class 1255 OID 17942)
-- Name: auto_register_user(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.auto_register_user() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    current_pg_user TEXT;
    emp_id INTEGER;
    username_parts TEXT[];
    teacher_prefix TEXT;
    first_name_rus TEXT;
BEGIN
    current_pg_user := current_user;
    
    -- Пробуем найти в таблице соответствия
    SELECT employee_id INTO emp_id
    FROM teacher_user_mapping
    WHERE pg_username = current_pg_user;
    
    -- Если нашли - возвращаем
    IF emp_id IS NOT NULL THEN
        PERFORM set_config('app.current_user_id', emp_id::text, false);
        RETURN emp_id;
    END IF;
    
    -- Если не нашли, пытаемся автоматически определить
    -- Ожидаем формат: teacher_ivan, teacher_dima, hr_anna
    username_parts := string_to_array(current_pg_user, '_');
    
    IF array_length(username_parts, 1) >= 2 THEN
        teacher_prefix := username_parts[1];
        
        -- Если это учитель (teacher_*)
        IF teacher_prefix = 'teacher' THEN
            -- Преобразуем имя из латинского в русское (простой вариант)
            CASE username_parts[2]
                WHEN 'ivan' THEN first_name_rus := 'Иван';
                WHEN 'maria' THEN first_name_rus := 'Мария';
                WHEN 'alexey' THEN first_name_rus := 'Алексей';
                WHEN 'dima' THEN first_name_rus := 'Дмитрий';
                WHEN 'olga' THEN first_name_rus := 'Ольга';
                WHEN 'serg' THEN first_name_rus := 'Сергей';
                ELSE first_name_rus := initcap(username_parts[2]);
            END CASE;
            
            -- Ищем сотрудника по имени
            SELECT id INTO emp_id
            FROM employees
            WHERE is_teacher = true 
              AND lower(first_name) = lower(first_name_rus)
            LIMIT 1;
            
            -- Если не нашли, создаем нового учителя
            IF emp_id IS NULL THEN
                INSERT INTO employees (
                    first_name, last_name, is_teacher, employee_type
                ) VALUES (
                    first_name_rus, 
                    'Новый',  -- Временная фамилия
                    true, 
                    'teacher'
                ) RETURNING id INTO emp_id;
                
                RAISE NOTICE 'Автоматически создан новый учитель: % (ID: %)', first_name_rus, emp_id;
            END IF;
            
            -- Регистрируем в таблице соответствия
            INSERT INTO teacher_user_mapping (pg_username, employee_id)
            VALUES (current_pg_user, emp_id)
            ON CONFLICT (pg_username) DO UPDATE SET 
                employee_id = EXCLUDED.employee_id,
                updated_at = CURRENT_TIMESTAMP;
            
            PERFORM set_config('app.current_user_id', emp_id::text, false);
            RETURN emp_id;
        END IF;
    END IF;
    
    -- Если не удалось определить, возвращаем NULL или 1 для тестирования
    IF current_pg_user = 'postgres' THEN
        PERFORM set_config('app.current_user_id', '1', false);
        RETURN 1;
    END IF;
    
    RAISE WARNING 'Не удалось определить employee_id для пользователя: %', current_pg_user;
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.auto_register_user() OWNER TO postgres;

--
-- TOC entry 262 (class 1255 OID 17959)
-- Name: create_teacher_with_mapping(text, text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_teacher_with_mapping(p_pg_username text, p_first_name text, p_last_name text DEFAULT 'Учитель'::text, p_email text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    new_employee_id INTEGER;
BEGIN
    -- Создаем запись в employees
    INSERT INTO employees (
        first_name, 
        last_name, 
        is_teacher, 
        employee_type,
        emails,
        created_at,
        updated_at
    ) VALUES (
        p_first_name,
        p_last_name,
        true,
        'teacher',
        CASE WHEN p_email IS NOT NULL THEN 
            jsonb_build_array(jsonb_build_object('type', 'work', 'address', p_email))
        ELSE '[]'::jsonb END,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    ) RETURNING id INTO new_employee_id;
    
    -- Привязываем к пользователю PostgreSQL
    INSERT INTO teacher_user_mapping (pg_username, employee_id)
    VALUES (p_pg_username, new_employee_id)
    ON CONFLICT (pg_username) DO UPDATE SET 
        employee_id = EXCLUDED.employee_id,
        updated_at = CURRENT_TIMESTAMP;
    
    RETURN new_employee_id;
END;
$$;


ALTER FUNCTION public.create_teacher_with_mapping(p_pg_username text, p_first_name text, p_last_name text, p_email text) OWNER TO postgres;

--
-- TOC entry 241 (class 1255 OID 17364)
-- Name: get_current_user_employee_id(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_current_user_employee_id() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    user_email VARCHAR;
    emp_id INTEGER;
BEGIN
    user_email := current_user || '@school.ru';
    
    SELECT id INTO emp_id
    FROM employees 
    WHERE emails::text LIKE '%' || user_email || '%';
    
    RETURN emp_id;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;


ALTER FUNCTION public.get_current_user_employee_id() OWNER TO postgres;

--
-- TOC entry 258 (class 1255 OID 17431)
-- Name: get_current_user_id(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_current_user_id() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    found_id INTEGER;
    current_pg_user TEXT;
    username_parts TEXT[];
    first_name_from_username TEXT;
BEGIN
    current_pg_user := current_user;
    
    -- 1. Ищем в таблице сопоставления
    SELECT employee_id INTO found_id
    FROM teacher_user_mapping
    WHERE pg_username = current_pg_user;
    
    -- 2. Если нашли - возвращаем
    IF found_id IS NOT NULL THEN
        PERFORM set_config('app.current_user_id', found_id::text, false);
        RAISE NOTICE 'Пользователь % найден в таблице, employee_id: %', current_pg_user, found_id;
        RETURN found_id;
    END IF;
END;
$$;


ALTER FUNCTION public.get_current_user_id() OWNER TO postgres;

--
-- TOC entry 256 (class 1255 OID 17127)
-- Name: get_teacher_profile(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_teacher_profile(p_teacher_id integer) RETURNS TABLE(teacher_id integer, full_name text, contact_email text, subjects jsonb, education jsonb, experience_years integer)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        e.id,
        CONCAT(e.last_name, ' ', e.first_name, ' ', COALESCE(e.middle_name, ''))::TEXT,
        (SELECT email->>'address' 
         FROM jsonb_array_elements(e.emails) email 
         WHERE email->>'type' = 'work' 
         LIMIT 1)::TEXT,
        (SELECT jsonb_agg(
            jsonb_build_object(
                'subject', ts.subject_name,
                'age_group', ts.age_group,
                'qualification', ts.qualification_level
            )
        ) FROM teacher_subjects ts 
        WHERE ts.employee_id = e.id AND ts.is_active = true),
        (SELECT jsonb_agg(
            jsonb_build_object(
                'institution', ed.institution_name,
                'specialty', ed.specialty,
                'year', ed.graduation_year,
                'type', ed.education_type
            )
        ) FROM education ed WHERE ed.employee_id = e.id),
        EXTRACT(YEAR FROM age(CURRENT_DATE, e.hire_date))::INTEGER
    FROM employees e
    WHERE e.id = p_teacher_id 
      AND e.is_teacher = true 
      AND e.is_active = true;
END;
$$;


ALTER FUNCTION public.get_teacher_profile(p_teacher_id integer) OWNER TO postgres;

--
-- TOC entry 243 (class 1255 OID 17426)
-- Name: log_employee_changes(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.log_employee_changes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        INSERT INTO audit_log (table_name, record_id, action, old_data, new_data, changed_by)
        VALUES (
            TG_TABLE_NAME,
            COALESCE(NEW.id, OLD.id),
            TG_OP,
            row_to_json(OLD),
            row_to_json(NEW),
            current_user
        );
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO audit_log (table_name, record_id, action, old_data, changed_by)
        VALUES (
            TG_TABLE_NAME,
            OLD.id,
            TG_OP,
            row_to_json(OLD),
            current_user
        );
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by)
        VALUES (
            TG_TABLE_NAME,
            NEW.id,
            TG_OP,
            row_to_json(NEW),
            current_user
        );
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.log_employee_changes() OWNER TO postgres;

--
-- TOC entry 244 (class 1255 OID 17960)
-- Name: map_user_to_existing_employee(text, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.map_user_to_existing_employee(p_pg_username text, p_employee_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Проверяем, существует ли сотрудник
    IF NOT EXISTS (SELECT 1 FROM employees WHERE id = p_employee_id) THEN
        RAISE EXCEPTION 'Сотрудник с ID % не существует', p_employee_id;
    END IF;
    
    -- Проверяем, является ли сотрудник учителем
    IF NOT EXISTS (SELECT 1 FROM employees WHERE id = p_employee_id AND is_teacher = true) THEN
        RAISE WARNING 'Сотрудник с ID % не является учителем', p_employee_id;
    END IF;
    
    -- Создаем/обновляем сопоставление
    INSERT INTO teacher_user_mapping (pg_username, employee_id)
    VALUES (p_pg_username, p_employee_id)
    ON CONFLICT (pg_username) DO UPDATE SET 
        employee_id = EXCLUDED.employee_id,
        updated_at = CURRENT_TIMESTAMP;
    
    RETURN TRUE;
END;
$$;


ALTER FUNCTION public.map_user_to_existing_employee(p_pg_username text, p_employee_id integer) OWNER TO postgres;

--
-- TOC entry 257 (class 1255 OID 17128)
-- Name: search_teachers(character varying, character varying, integer, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.search_teachers(p_subject character varying DEFAULT NULL::character varying, p_age_group character varying DEFAULT NULL::character varying, p_min_experience integer DEFAULT 0, p_min_qualification character varying DEFAULT NULL::character varying) RETURNS TABLE(teacher_id integer, teacher_name text, subject character varying, age_group character varying, qualification character varying, experience_years integer, education_info text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        e.id,
        CONCAT(e.last_name, ' ', e.first_name)::TEXT,
        ts.subject_name,
        ts.age_group,
        ts.qualification_level,
        ts.years_experience,
        (SELECT ed.specialty || ' (' || ed.institution_name || ', ' || ed.graduation_year || ')'
         FROM education ed 
         WHERE ed.employee_id = e.id 
         AND ed.education_type LIKE 'higher%'
         ORDER BY ed.graduation_year DESC 
         LIMIT 1)::TEXT
    FROM employees e
    JOIN teacher_subjects ts ON e.id = ts.employee_id
    WHERE e.is_teacher = true 
      AND e.is_active = true
      AND ts.is_active = true
      AND (p_subject IS NULL OR ts.subject_name ILIKE '%' || p_subject || '%')
      AND (p_age_group IS NULL OR ts.age_group = p_age_group)
      AND ts.years_experience >= p_min_experience
      AND (p_min_qualification IS NULL OR 
           CASE ts.qualification_level
               WHEN 'expert' THEN 4
               WHEN 'advanced' THEN 3
               WHEN 'intermediate' THEN 2
               WHEN 'beginner' THEN 1
               ELSE 0
           END >= CASE p_min_qualification
               WHEN 'expert' THEN 4
               WHEN 'advanced' THEN 3
               WHEN 'intermediate' THEN 2
               WHEN 'beginner' THEN 1
               ELSE 0
           END)
    ORDER BY ts.qualification_level DESC, ts.years_experience DESC;
END;
$$;


ALTER FUNCTION public.search_teachers(p_subject character varying, p_age_group character varying, p_min_experience integer, p_min_qualification character varying) OWNER TO postgres;

--
-- TOC entry 5072 (class 0 OID 0)
-- Dependencies: 257
-- Name: FUNCTION search_teachers(p_subject character varying, p_age_group character varying, p_min_experience integer, p_min_qualification character varying); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.search_teachers(p_subject character varying, p_age_group character varying, p_min_experience integer, p_min_qualification character varying) IS 'Функция которая будет позволять клиентам фирмы искать нужного им учителя';


--
-- TOC entry 242 (class 1255 OID 17365)
-- Name: set_current_user_id(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.set_current_user_id(user_id integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    PERFORM set_config('app.current_user_id', user_id::text, false);
END;
$$;


ALTER FUNCTION public.set_current_user_id(user_id integer) OWNER TO postgres;

--
-- TOC entry 240 (class 1255 OID 17081)
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_updated_at_column() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 228 (class 1259 OID 17202)
-- Name: age_groups; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.age_groups (
    id integer NOT NULL,
    code character varying(50) NOT NULL,
    name character varying(100) NOT NULL,
    min_age integer,
    max_age integer,
    school_grade character varying(50),
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.age_groups OWNER TO postgres;

--
-- TOC entry 5074 (class 0 OID 0)
-- Dependencies: 228
-- Name: TABLE age_groups; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.age_groups IS 'Справочник возрастных групп';


--
-- TOC entry 227 (class 1259 OID 17201)
-- Name: age_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.age_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.age_groups_id_seq OWNER TO postgres;

--
-- TOC entry 5076 (class 0 OID 0)
-- Dependencies: 227
-- Name: age_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.age_groups_id_seq OWNED BY public.age_groups.id;


--
-- TOC entry 218 (class 1259 OID 17002)
-- Name: employees; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.employees (
    id integer NOT NULL,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    middle_name character varying(100),
    birth_date date NOT NULL,
    gender character varying(10),
    address_country character varying(100),
    address_city character varying(100),
    phone_numbers jsonb DEFAULT '[]'::jsonb,
    emails jsonb DEFAULT '[]'::jsonb,
    social_media jsonb DEFAULT '[]'::jsonb,
    hire_date date DEFAULT CURRENT_DATE,
    termination_date date,
    is_active boolean DEFAULT true,
    is_teacher boolean DEFAULT false,
    employee_type character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT age_check CHECK ((EXTRACT(year FROM age((birth_date)::timestamp with time zone)) >= (18)::numeric)),
    CONSTRAINT employees_employee_type_check CHECK (((employee_type)::text = ANY ((ARRAY['teacher'::character varying, 'administrator'::character varying, 'support'::character varying, 'manager'::character varying])::text[]))),
    CONSTRAINT employees_gender_check CHECK (((gender)::text = ANY ((ARRAY['male'::character varying, 'female'::character varying, 'other'::character varying])::text[]))),
    CONSTRAINT valid_emails CHECK ((jsonb_typeof(emails) = 'array'::text)),
    CONSTRAINT valid_phone_numbers CHECK ((jsonb_typeof(phone_numbers) = 'array'::text))
);


ALTER TABLE public.employees OWNER TO postgres;

--
-- TOC entry 5078 (class 0 OID 0)
-- Dependencies: 218
-- Name: TABLE employees; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.employees IS 'Основная таблица сотрудников';


--
-- TOC entry 5079 (class 0 OID 0)
-- Dependencies: 218
-- Name: COLUMN employees.phone_numbers; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.employees.phone_numbers IS 'Массив телефонов: [{"type": "mobile", "number": "+7..."}, ...]';


--
-- TOC entry 5080 (class 0 OID 0)
-- Dependencies: 218
-- Name: COLUMN employees.emails; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.employees.emails IS 'Массив email: [{"type": "work", "address": "..."}, ...]';


--
-- TOC entry 5081 (class 0 OID 0)
-- Dependencies: 218
-- Name: COLUMN employees.social_media; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.employees.social_media IS 'Соцсети: [{"platform": "vk", "url": "..."}, ...]';


--
-- TOC entry 232 (class 1259 OID 17244)
-- Name: school_programs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.school_programs (
    id integer NOT NULL,
    employee_id integer NOT NULL,
    subject_id integer,
    age_group_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    certificate_name character varying(255),
    certificate_year integer,
    certificate_hours integer
);


ALTER TABLE public.school_programs OWNER TO postgres;

--
-- TOC entry 5083 (class 0 OID 0)
-- Dependencies: 232
-- Name: TABLE school_programs; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.school_programs IS 'Предметы и возрастные группы преподавателей';


--
-- TOC entry 226 (class 1259 OID 17189)
-- Name: subjects; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.subjects (
    id integer NOT NULL,
    code character varying(50) NOT NULL,
    name_ru character varying(100) NOT NULL,
    name_en character varying(100),
    category character varying(100),
    description text,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.subjects OWNER TO postgres;

--
-- TOC entry 5085 (class 0 OID 0)
-- Dependencies: 226
-- Name: TABLE subjects; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.subjects IS 'Справочник учебных предметов';


--
-- TOC entry 235 (class 1259 OID 17404)
-- Name: api_teachers_for_scheduling; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.api_teachers_for_scheduling AS
 SELECT id AS teacher_id,
    first_name,
    last_name,
    middle_name,
    ( SELECT json_agg(json_build_object('subject_id', sp.subject_id, 'subject_name', s.name_ru, 'age_group_id', sp.age_group_id, 'age_group_name', ag.name, 'certificate',
                CASE
                    WHEN (sp.certificate_name IS NOT NULL) THEN json_build_object('name', sp.certificate_name, 'year', sp.certificate_year, 'hours', sp.certificate_hours)
                    ELSE NULL::json
                END)) AS json_agg
           FROM ((public.school_programs sp
             LEFT JOIN public.subjects s ON ((sp.subject_id = s.id)))
             LEFT JOIN public.age_groups ag ON ((sp.age_group_id = ag.id)))
          WHERE (sp.employee_id = e.id)
          GROUP BY sp.employee_id) AS teaching_qualifications,
    ( SELECT json_agg((email.value ->> 'address'::text)) AS json_agg
           FROM jsonb_array_elements(e.emails) email(value)
          WHERE ((email.value ->> 'type'::text) = 'work'::text)
         LIMIT 1) AS work_email
   FROM public.employees e
  WHERE ((is_teacher = true) AND (is_active = true))
  ORDER BY last_name, first_name;


ALTER VIEW public.api_teachers_for_scheduling OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 17132)
-- Name: audit_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audit_log (
    id bigint NOT NULL,
    table_name character varying(100),
    record_id integer,
    action character varying(10),
    old_data jsonb,
    new_data jsonb,
    changed_by character varying(100),
    changed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT audit_log_action_check CHECK (((action)::text = ANY ((ARRAY['INSERT'::character varying, 'UPDATE'::character varying, 'DELETE'::character varying])::text[])))
);


ALTER TABLE public.audit_log OWNER TO postgres;

--
-- TOC entry 5088 (class 0 OID 0)
-- Dependencies: 220
-- Name: TABLE audit_log; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.audit_log IS 'Таблица для аудита изменений';


--
-- TOC entry 219 (class 1259 OID 17131)
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.audit_log_id_seq OWNER TO postgres;

--
-- TOC entry 5090 (class 0 OID 0)
-- Dependencies: 219
-- Name: audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.audit_log_id_seq OWNED BY public.audit_log.id;


--
-- TOC entry 230 (class 1259 OID 17216)
-- Name: education; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.education (
    id integer NOT NULL,
    employee_id integer NOT NULL,
    institution_name character varying(255) NOT NULL,
    institution_country character varying(100) DEFAULT 'Россия'::character varying,
    institution_city character varying(100),
    diploma_number character varying(100),
    diploma_series character varying(50),
    diploma_issue_date date,
    education_type_id integer,
    qualification_id integer,
    specialty character varying(255) NOT NULL,
    start_date date,
    end_date date,
    graduation_year integer NOT NULL,
    final_grade character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.education OWNER TO postgres;

--
-- TOC entry 5092 (class 0 OID 0)
-- Dependencies: 230
-- Name: TABLE education; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.education IS 'Образование и повышение квалификации сотрудников';


--
-- TOC entry 229 (class 1259 OID 17215)
-- Name: education_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.education_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.education_id_seq OWNER TO postgres;

--
-- TOC entry 5094 (class 0 OID 0)
-- Dependencies: 229
-- Name: education_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.education_id_seq OWNED BY public.education.id;


--
-- TOC entry 222 (class 1259 OID 17163)
-- Name: education_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.education_types (
    id integer NOT NULL,
    code character varying(50) NOT NULL,
    name_ru character varying(100) NOT NULL,
    name_en character varying(100),
    duration_months integer,
    is_higher_education boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.education_types OWNER TO postgres;

--
-- TOC entry 5096 (class 0 OID 0)
-- Dependencies: 222
-- Name: TABLE education_types; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.education_types IS 'Справочник типов образования';


--
-- TOC entry 5097 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN education_types.code; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.education_types.code IS 'Внутренний код типа (например: higher_master)';


--
-- TOC entry 221 (class 1259 OID 17162)
-- Name: education_types_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.education_types_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.education_types_id_seq OWNER TO postgres;

--
-- TOC entry 5099 (class 0 OID 0)
-- Dependencies: 221
-- Name: education_types_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.education_types_id_seq OWNED BY public.education_types.id;


--
-- TOC entry 217 (class 1259 OID 17001)
-- Name: employees_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.employees_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employees_id_seq OWNER TO postgres;

--
-- TOC entry 5101 (class 0 OID 0)
-- Dependencies: 217
-- Name: employees_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.employees_id_seq OWNED BY public.employees.id;


--
-- TOC entry 233 (class 1259 OID 17390)
-- Name: hr_employee_dashboard; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.hr_employee_dashboard AS
 SELECT id,
    ((((first_name)::text || ' '::text) || (last_name)::text) ||
        CASE
            WHEN (middle_name IS NOT NULL) THEN (' '::text || (middle_name)::text)
            ELSE ''::text
        END) AS full_name,
    birth_date,
    EXTRACT(year FROM age((birth_date)::timestamp with time zone)) AS age,
    gender,
    address_city,
    phone_numbers,
    emails,
    hire_date,
    termination_date,
    is_active,
    is_teacher,
    employee_type,
    ( SELECT count(*) AS count
           FROM public.education ed
          WHERE (ed.employee_id = e.id)) AS education_count,
    ( SELECT count(*) AS count
           FROM public.school_programs sp
          WHERE (sp.employee_id = e.id)) AS programs_count,
        CASE
            WHEN (is_teacher = true) THEN 'Преподаватель'::text
            WHEN ((employee_type)::text = 'administrator'::text) THEN 'Администратор'::text
            WHEN ((employee_type)::text = 'support'::text) THEN 'Техподдержка'::text
            ELSE 'Сотрудник'::text
        END AS role_display,
    created_at,
    updated_at
   FROM public.employees e
  ORDER BY is_active DESC, last_name, first_name;


ALTER VIEW public.hr_employee_dashboard OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 17419)
-- Name: public_teacher_profiles; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.public_teacher_profiles AS
 SELECT id,
    first_name,
    last_name,
    middle_name,
    gender,
    address_city,
    ( SELECT json_agg(json_build_object('institution', ed.institution_name, 'specialty', ed.specialty, 'year', ed.graduation_year)) AS json_agg
           FROM ( SELECT ed2.institution_name,
                    ed2.specialty,
                    ed2.graduation_year
                   FROM public.education ed2
                  WHERE ((ed2.employee_id = e.id) AND (ed2.diploma_issue_date IS NOT NULL))
                  ORDER BY ed2.graduation_year DESC
                 LIMIT 3) ed) AS education,
    ( SELECT json_agg(json_build_object('subject', s.name_ru, 'age_group', ag.name, 'certificate',
                CASE
                    WHEN (sp.certificate_name IS NOT NULL) THEN json_build_object('name', sp.certificate_name, 'year', sp.certificate_year)
                    ELSE NULL::json
                END)) AS json_agg
           FROM ((public.school_programs sp
             LEFT JOIN public.subjects s ON ((sp.subject_id = s.id)))
             LEFT JOIN public.age_groups ag ON ((sp.age_group_id = ag.id)))
          WHERE (sp.employee_id = e.id)) AS subjects_info,
    created_at
   FROM public.employees e
  WHERE ((is_teacher = true) AND (is_active = true))
  ORDER BY last_name, first_name;


ALTER VIEW public.public_teacher_profiles OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 17176)
-- Name: qualifications; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.qualifications (
    id integer NOT NULL,
    name_ru character varying(200) NOT NULL,
    name_en character varying(200),
    category character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.qualifications OWNER TO postgres;

--
-- TOC entry 5105 (class 0 OID 0)
-- Dependencies: 224
-- Name: TABLE qualifications; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.qualifications IS 'Справочник квалификаций/профессий';


--
-- TOC entry 223 (class 1259 OID 17175)
-- Name: qualifications_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.qualifications_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.qualifications_id_seq OWNER TO postgres;

--
-- TOC entry 5107 (class 0 OID 0)
-- Dependencies: 223
-- Name: qualifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.qualifications_id_seq OWNED BY public.qualifications.id;


--
-- TOC entry 225 (class 1259 OID 17188)
-- Name: subjects_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.subjects_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.subjects_id_seq OWNER TO postgres;

--
-- TOC entry 5109 (class 0 OID 0)
-- Dependencies: 225
-- Name: subjects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.subjects_id_seq OWNED BY public.subjects.id;


--
-- TOC entry 234 (class 1259 OID 17395)
-- Name: table_columns_info; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.table_columns_info AS
 SELECT table_name,
    column_name,
    data_type,
    is_nullable,
    column_default
   FROM information_schema.columns
  WHERE ((table_schema)::name = 'public'::name)
  ORDER BY table_name, ordinal_position;


ALTER VIEW public.table_columns_info OWNER TO postgres;

--
-- TOC entry 238 (class 1259 OID 17443)
-- Name: teacher_personal_dashboard; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.teacher_personal_dashboard AS
 SELECT id,
    first_name,
    last_name,
    middle_name,
    birth_date,
    gender,
    address_city,
    phone_numbers,
    emails,
    social_media,
    hire_date,
    COALESCE(( SELECT json_agg(json_build_object('id', ed_data.id, 'institution', ed_data.institution_name, 'city', ed_data.institution_city, 'specialty', ed_data.specialty, 'year', ed_data.graduation_year, 'diploma_number', ed_data.diploma_number, 'type', ed_data.name_ru)) AS json_agg
           FROM ( SELECT ed.id,
                    COALESCE(ed.institution_name, 'Не указано'::character varying) AS institution_name,
                    COALESCE(ed.institution_city, 'Не указан'::character varying) AS institution_city,
                    COALESCE(ed.specialty, 'Не указана'::character varying) AS specialty,
                    ed.graduation_year,
                    ed.diploma_number,
                    COALESCE(et.name_ru, 'Не указан'::character varying) AS name_ru
                   FROM (public.education ed
                     LEFT JOIN public.education_types et ON ((ed.education_type_id = et.id)))
                  WHERE (ed.employee_id = e.id)
                  ORDER BY ed.graduation_year DESC) ed_data), '[]'::json) AS education_details,
    COALESCE(( SELECT json_agg(json_build_object('id', sp_data.id, 'subject', sp_data.subject_name, 'age_group', sp_data.age_group_name, 'certificate_name', sp_data.certificate_name, 'certificate_year', sp_data.certificate_year, 'certificate_hours', sp_data.certificate_hours)) AS json_agg
           FROM ( SELECT sp.id,
                    COALESCE(s.name_ru, 'Не указан'::character varying) AS subject_name,
                    COALESCE(ag.name, 'Не указана'::character varying) AS age_group_name,
                    sp.certificate_name,
                    sp.certificate_year,
                    sp.certificate_hours
                   FROM ((public.school_programs sp
                     LEFT JOIN public.subjects s ON ((sp.subject_id = s.id)))
                     LEFT JOIN public.age_groups ag ON ((sp.age_group_id = ag.id)))
                  WHERE (sp.employee_id = e.id)
                  ORDER BY sp.certificate_year DESC NULLS LAST) sp_data), '[]'::json) AS my_programs,
    COALESCE(( SELECT json_build_object('total_programs', count(DISTINCT sp.id), 'total_certificates', count(DISTINCT sp.certificate_name)) AS json_build_object
           FROM public.school_programs sp
          WHERE (sp.employee_id = e.id)), '{"total_programs": 0, "total_certificates": 0}'::json) AS statistics
   FROM public.employees e
  WHERE ((id = public.get_current_user_id()) AND (is_teacher = true));


ALTER VIEW public.teacher_personal_dashboard OWNER TO postgres;

--
-- TOC entry 5111 (class 0 OID 0)
-- Dependencies: 238
-- Name: VIEW teacher_personal_dashboard; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.teacher_personal_dashboard IS 'Персональная панель учителя с образованием, программами и статистикой';


--
-- TOC entry 236 (class 1259 OID 17414)
-- Name: teacher_search_by_subject; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.teacher_search_by_subject AS
 WITH teacher_subject_data AS (
         SELECT DISTINCT s.id AS subject_id,
            s.name_ru AS subject_name,
            e.id AS teacher_id,
            (((e.first_name)::text || ' '::text) || (e.last_name)::text) AS teacher_name
           FROM ((public.subjects s
             JOIN public.school_programs sp ON ((s.id = sp.subject_id)))
             JOIN public.employees e ON ((sp.employee_id = e.id)))
          WHERE ((e.is_teacher = true) AND (e.is_active = true))
        )
 SELECT subject_id,
    subject_name,
    json_agg(json_build_object('teacher_id', teacher_id, 'teacher_name', teacher_name, 'age_groups', ( SELECT json_agg(ag.name) AS json_agg
           FROM (public.school_programs sp2
             JOIN public.age_groups ag ON ((sp2.age_group_id = ag.id)))
          WHERE ((sp2.employee_id = tsd.teacher_id) AND (sp2.subject_id = tsd.subject_id))), 'certificates', ( SELECT json_agg(json_build_object('name', sp3.certificate_name, 'year', sp3.certificate_year)) AS json_agg
           FROM public.school_programs sp3
          WHERE ((sp3.employee_id = tsd.teacher_id) AND (sp3.subject_id = tsd.subject_id) AND (sp3.certificate_name IS NOT NULL))))) AS teachers
   FROM teacher_subject_data tsd
  GROUP BY subject_id, subject_name
  ORDER BY subject_name;


ALTER VIEW public.teacher_search_by_subject OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 17243)
-- Name: teacher_subjects_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.teacher_subjects_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.teacher_subjects_id_seq OWNER TO postgres;

--
-- TOC entry 5114 (class 0 OID 0)
-- Dependencies: 231
-- Name: teacher_subjects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.teacher_subjects_id_seq OWNED BY public.school_programs.id;


--
-- TOC entry 239 (class 1259 OID 17943)
-- Name: teacher_user_mapping; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.teacher_user_mapping (
    pg_username text NOT NULL,
    employee_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.teacher_user_mapping OWNER TO postgres;

--
-- TOC entry 5116 (class 0 OID 0)
-- Dependencies: 239
-- Name: TABLE teacher_user_mapping; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.teacher_user_mapping IS 'Маппинг айдишников для работников фирмы, чтобы реализовать особенную доступную им выборку по БД employees (учителя будут видеть только себя, например)';


--
-- TOC entry 4790 (class 2604 OID 17205)
-- Name: age_groups id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.age_groups ALTER COLUMN id SET DEFAULT nextval('public.age_groups_id_seq'::regclass);


--
-- TOC entry 4780 (class 2604 OID 17135)
-- Name: audit_log id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_log ALTER COLUMN id SET DEFAULT nextval('public.audit_log_id_seq'::regclass);


--
-- TOC entry 4792 (class 2604 OID 17219)
-- Name: education id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.education ALTER COLUMN id SET DEFAULT nextval('public.education_id_seq'::regclass);


--
-- TOC entry 4782 (class 2604 OID 17166)
-- Name: education_types id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.education_types ALTER COLUMN id SET DEFAULT nextval('public.education_types_id_seq'::regclass);


--
-- TOC entry 4771 (class 2604 OID 17005)
-- Name: employees id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees ALTER COLUMN id SET DEFAULT nextval('public.employees_id_seq'::regclass);


--
-- TOC entry 4785 (class 2604 OID 17179)
-- Name: qualifications id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.qualifications ALTER COLUMN id SET DEFAULT nextval('public.qualifications_id_seq'::regclass);


--
-- TOC entry 4796 (class 2604 OID 17247)
-- Name: school_programs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_programs ALTER COLUMN id SET DEFAULT nextval('public.teacher_subjects_id_seq'::regclass);


--
-- TOC entry 4787 (class 2604 OID 17192)
-- Name: subjects id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subjects ALTER COLUMN id SET DEFAULT nextval('public.subjects_id_seq'::regclass);


--
-- TOC entry 5055 (class 0 OID 17202)
-- Dependencies: 228
-- Data for Name: age_groups; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.age_groups VALUES (1, 'elementary', 'Начальная школа (1-4 класс)', 7, 10, '1-4', 'Младшие школьники', '2026-01-20 18:59:52.513527');
INSERT INTO public.age_groups VALUES (2, 'middle', 'Средняя школа (5-9 класс)', 11, 14, '5-9', 'Подростки', '2026-01-20 18:59:52.513527');
INSERT INTO public.age_groups VALUES (3, 'high', 'Старшая школа (10-11 класс)', 15, 17, '10-11', 'Старшеклассники, подготовка к ЕГЭ', '2026-01-20 18:59:52.513527');


--
-- TOC entry 5047 (class 0 OID 17132)
-- Dependencies: 220
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.audit_log VALUES (1, 'employees', 1, 'UPDATE', '{"id": 1, "emails": [{"type": "work", "address": "petrov@school.ru"}, {"type": "personal", "address": "ivan.petrov@gmail.com"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Петров", "birth_date": "1985-05-15", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Иван", "is_teacher": true, "updated_at": "2026-01-20T17:27:43.009838", "address_zip": null, "middle_name": "Сергеевич", "address_city": "Москва", "social_media": [], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79991112233"}, {"type": "work", "number": "+74951234567"}], "address_street": "ул. Ленина, д. 10, кв. 25", "address_country": null, "termination_date": null}', '{"id": 1, "emails": [{"type": "work", "address": "petrov@school.ru"}, {"type": "personal", "address": "ivan.petrov@gmail.com"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Петров", "birth_date": "1985-05-15", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Иван", "is_teacher": true, "updated_at": "2026-01-20T17:29:50.176799", "address_zip": null, "middle_name": "Сергеевич", "address_city": "Москва", "social_media": [], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79991112233"}, {"type": "work", "number": "+74951234567"}], "address_street": "ул. Ленина, д. 10, кв. 25", "address_country": "Россия", "termination_date": null}', 'postgres', '2026-01-20 17:29:50.176799');
INSERT INTO public.audit_log VALUES (2, 'employees', 2, 'UPDATE', '{"id": 2, "emails": [{"type": "work", "address": "sidorova@school.ru"}], "gender": "female", "hire_date": "2026-01-20", "is_active": true, "last_name": "Сидорова", "birth_date": "1990-08-22", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Мария", "is_teacher": true, "updated_at": "2026-01-20T17:27:43.009838", "address_zip": null, "middle_name": "Ивановна", "address_city": "Санкт-Петербург", "social_media": [], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79997778899"}], "address_street": "пр. Просвещения, д. 45, кв. 12", "address_country": null, "termination_date": null}', '{"id": 2, "emails": [{"type": "work", "address": "sidorova@school.ru"}], "gender": "female", "hire_date": "2026-01-20", "is_active": true, "last_name": "Сидорова", "birth_date": "1990-08-22", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Мария", "is_teacher": true, "updated_at": "2026-01-20T17:29:50.176799", "address_zip": null, "middle_name": "Ивановна", "address_city": "Санкт-Петербург", "social_media": [], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79997778899"}], "address_street": "пр. Просвещения, д. 45, кв. 12", "address_country": "Россия", "termination_date": null}', 'postgres', '2026-01-20 17:29:50.176799');
INSERT INTO public.audit_log VALUES (3, 'employees', 3, 'UPDATE', '{"id": 3, "emails": [{"type": "work", "address": "kuznetsov@school.ru"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Кузнецов", "birth_date": "1982-11-30", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Алексей", "is_teacher": true, "updated_at": "2026-01-20T17:27:43.009838", "address_zip": null, "middle_name": "Андреевич", "address_city": "Казань", "social_media": [], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79993334455"}, {"type": "home", "number": "+78432111222"}], "address_street": "ул. Баумана, д. 15", "address_country": null, "termination_date": null}', '{"id": 3, "emails": [{"type": "work", "address": "kuznetsov@school.ru"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Кузнецов", "birth_date": "1982-11-30", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Алексей", "is_teacher": true, "updated_at": "2026-01-20T17:29:50.176799", "address_zip": null, "middle_name": "Андреевич", "address_city": "Казань", "social_media": [], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79993334455"}, {"type": "home", "number": "+78432111222"}], "address_street": "ул. Баумана, д. 15", "address_country": "Россия", "termination_date": null}', 'postgres', '2026-01-20 17:29:50.176799');
INSERT INTO public.audit_log VALUES (4, 'employees', 4, 'UPDATE', '{"id": 4, "emails": [{"type": "work", "address": "hr@school.ru"}], "gender": "female", "hire_date": "2026-01-20", "is_active": true, "last_name": "Смирнова", "birth_date": "1988-03-10", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Анна", "is_teacher": false, "updated_at": "2026-01-20T17:27:43.009838", "address_zip": null, "middle_name": "Викторовна", "address_city": "Москва", "social_media": [], "employee_type": "administrator", "phone_numbers": [{"type": "mobile", "number": "+79994445566"}], "address_street": "ул. Тверская, д. 20", "address_country": null, "termination_date": null}', '{"id": 4, "emails": [{"type": "work", "address": "hr@school.ru"}], "gender": "female", "hire_date": "2026-01-20", "is_active": true, "last_name": "Смирнова", "birth_date": "1988-03-10", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Анна", "is_teacher": false, "updated_at": "2026-01-20T17:29:50.176799", "address_zip": null, "middle_name": "Викторовна", "address_city": "Москва", "social_media": [], "employee_type": "administrator", "phone_numbers": [{"type": "mobile", "number": "+79994445566"}], "address_street": "ул. Тверская, д. 20", "address_country": "Россия", "termination_date": null}', 'postgres', '2026-01-20 17:29:50.176799');
INSERT INTO public.audit_log VALUES (5, 'employees', 5, 'UPDATE', '{"id": 5, "emails": [{"type": "work", "address": "support@school.ru"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Васильев", "birth_date": "1992-07-18", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Дмитрий", "is_teacher": false, "updated_at": "2026-01-20T17:27:43.009838", "address_zip": null, "middle_name": "Олегович", "address_city": "Новосибирск", "social_media": [], "employee_type": "support", "phone_numbers": [{"type": "mobile", "number": "+79995556677"}], "address_street": "ул. Кирова, д. 5", "address_country": null, "termination_date": null}', '{"id": 5, "emails": [{"type": "work", "address": "support@school.ru"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Васильев", "birth_date": "1992-07-18", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Дмитрий", "is_teacher": false, "updated_at": "2026-01-20T17:29:50.176799", "address_zip": null, "middle_name": "Олегович", "address_city": "Новосибирск", "social_media": [], "employee_type": "support", "phone_numbers": [{"type": "mobile", "number": "+79995556677"}], "address_street": "ул. Кирова, д. 5", "address_country": "Россия", "termination_date": null}', 'postgres', '2026-01-20 17:29:50.176799');
INSERT INTO public.audit_log VALUES (6, 'employees', 1, 'UPDATE', '{"id": 1, "emails": [{"type": "work", "address": "petrov@school.ru"}, {"type": "personal", "address": "ivan.petrov@gmail.com"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Петров", "birth_date": "1985-05-15", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Иван", "is_teacher": true, "updated_at": "2026-01-20T17:29:50.176799", "address_zip": null, "middle_name": "Сергеевич", "address_city": "Москва", "social_media": [], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79991112233"}, {"type": "work", "number": "+74951234567"}], "address_street": "ул. Ленина, д. 10, кв. 25", "address_country": "Россия", "termination_date": null}', '{"id": 1, "emails": [{"type": "work", "address": "petrov@school.ru"}, {"type": "personal", "address": "ivan.petrov@gmail.com"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Петров", "birth_date": "1985-05-15", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Иван", "is_teacher": true, "updated_at": "2026-01-20T17:53:08.724883", "address_zip": null, "middle_name": "Сергеевич", "address_city": "Москва", "social_media": [{"url": "https://vk.com/id123456", "platform": "vk", "username": "ivan_petrov"}], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79991112233"}, {"type": "work", "number": "+74951234567"}], "address_street": "ул. Ленина, д. 10, кв. 25", "address_country": "Россия", "termination_date": null}', 'postgres', '2026-01-20 17:53:08.724883');
INSERT INTO public.audit_log VALUES (7, 'employees', 2, 'UPDATE', '{"id": 2, "emails": [{"type": "work", "address": "sidorova@school.ru"}], "gender": "female", "hire_date": "2026-01-20", "is_active": true, "last_name": "Сидорова", "birth_date": "1990-08-22", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Мария", "is_teacher": true, "updated_at": "2026-01-20T17:29:50.176799", "address_zip": null, "middle_name": "Ивановна", "address_city": "Санкт-Петербург", "social_media": [], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79997778899"}], "address_street": "пр. Просвещения, д. 45, кв. 12", "address_country": "Россия", "termination_date": null}', '{"id": 2, "emails": [{"type": "work", "address": "sidorova@school.ru"}], "gender": "female", "hire_date": "2026-01-20", "is_active": true, "last_name": "Сидорова", "birth_date": "1990-08-22", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Мария", "is_teacher": true, "updated_at": "2026-01-20T17:53:08.724883", "address_zip": null, "middle_name": "Ивановна", "address_city": "Санкт-Петербург", "social_media": [{"url": "https://vk.com/maria_sidorova", "platform": "vk", "username": "maria_sidorova"}, {"platform": "telegram", "username": "@maria_sidorova"}], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79997778899"}], "address_street": "пр. Просвещения, д. 45, кв. 12", "address_country": "Россия", "termination_date": null}', 'postgres', '2026-01-20 17:53:08.724883');
INSERT INTO public.audit_log VALUES (8, 'employees', 3, 'UPDATE', '{"id": 3, "emails": [{"type": "work", "address": "kuznetsov@school.ru"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Кузнецов", "birth_date": "1982-11-30", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Алексей", "is_teacher": true, "updated_at": "2026-01-20T17:29:50.176799", "address_zip": null, "middle_name": "Андреевич", "address_city": "Казань", "social_media": [], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79993334455"}, {"type": "home", "number": "+78432111222"}], "address_street": "ул. Баумана, д. 15", "address_country": "Россия", "termination_date": null}', '{"id": 3, "emails": [{"type": "work", "address": "kuznetsov@school.ru"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Кузнецов", "birth_date": "1982-11-30", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Алексей", "is_teacher": true, "updated_at": "2026-01-20T17:53:08.724883", "address_zip": null, "middle_name": "Андреевич", "address_city": "Казань", "social_media": [{"url": "https://vk.com/alexey_kuznetsov", "platform": "vk", "username": "alexey_k"}, {"platform": "telegram", "username": "@alexey_kuznetsov"}], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79993334455"}, {"type": "home", "number": "+78432111222"}], "address_street": "ул. Баумана, д. 15", "address_country": "Россия", "termination_date": null}', 'postgres', '2026-01-20 17:53:08.724883');
INSERT INTO public.audit_log VALUES (9, 'employees', 4, 'UPDATE', '{"id": 4, "emails": [{"type": "work", "address": "hr@school.ru"}], "gender": "female", "hire_date": "2026-01-20", "is_active": true, "last_name": "Смирнова", "birth_date": "1988-03-10", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Анна", "is_teacher": false, "updated_at": "2026-01-20T17:29:50.176799", "address_zip": null, "middle_name": "Викторовна", "address_city": "Москва", "social_media": [], "employee_type": "administrator", "phone_numbers": [{"type": "mobile", "number": "+79994445566"}], "address_street": "ул. Тверская, д. 20", "address_country": "Россия", "termination_date": null}', '{"id": 4, "emails": [{"type": "work", "address": "hr@school.ru"}], "gender": "female", "hire_date": "2026-01-20", "is_active": true, "last_name": "Смирнова", "birth_date": "1988-03-10", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Анна", "is_teacher": false, "updated_at": "2026-01-20T17:53:08.724883", "address_zip": null, "middle_name": "Викторовна", "address_city": "Москва", "social_media": [{"url": "https://vk.com/anna_smirnova", "platform": "vk", "username": "anna_s"}, {"platform": "telegram", "username": "@anna_smirnova_hr"}], "employee_type": "administrator", "phone_numbers": [{"type": "mobile", "number": "+79994445566"}], "address_street": "ул. Тверская, д. 20", "address_country": "Россия", "termination_date": null}', 'postgres', '2026-01-20 17:53:08.724883');
INSERT INTO public.audit_log VALUES (10, 'employees', 5, 'UPDATE', '{"id": 5, "emails": [{"type": "work", "address": "support@school.ru"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Васильев", "birth_date": "1992-07-18", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Дмитрий", "is_teacher": false, "updated_at": "2026-01-20T17:29:50.176799", "address_zip": null, "middle_name": "Олегович", "address_city": "Новосибирск", "social_media": [], "employee_type": "support", "phone_numbers": [{"type": "mobile", "number": "+79995556677"}], "address_street": "ул. Кирова, д. 5", "address_country": "Россия", "termination_date": null}', '{"id": 5, "emails": [{"type": "work", "address": "support@school.ru"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Васильев", "birth_date": "1992-07-18", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Дмитрий", "is_teacher": false, "updated_at": "2026-01-20T17:53:08.724883", "address_zip": null, "middle_name": "Олегович", "address_city": "Новосибирск", "social_media": [{"url": "https://vk.com/dmitry_vasilev", "platform": "vk", "username": "dmitry_v"}, {"platform": "telegram", "username": "@dmitry_support"}], "employee_type": "support", "phone_numbers": [{"type": "mobile", "number": "+79995556677"}], "address_street": "ул. Кирова, д. 5", "address_country": "Россия", "termination_date": null}', 'postgres', '2026-01-20 17:53:08.724883');
INSERT INTO public.audit_log VALUES (14, 'employees', 1, 'UPDATE', '{"id": 1, "emails": [{"type": "work", "address": "petrov@school.ru"}, {"type": "personal", "address": "ivan.petrov@gmail.com"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Петров", "birth_date": "1985-05-15", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Иван", "is_teacher": true, "updated_at": "2026-01-20T17:53:08.724883", "middle_name": "Сергеевич", "address_city": "Москва", "social_media": [{"url": "https://vk.com/id123456", "platform": "vk", "username": "ivan_petrov"}], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79991112233"}, {"type": "work", "number": "+74951234567"}], "address_country": "Россия", "termination_date": null}', '{"id": 1, "emails": [{"type": "work", "address": "petrov@school.ru"}, {"type": "personal", "address": "ivan.petrov@gmail.com"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Петров", "birth_date": "1985-05-15", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Иван1", "is_teacher": true, "updated_at": "2026-01-21T00:58:16.824019", "middle_name": "Сергеевич", "address_city": "Москва", "social_media": [{"url": "https://vk.com/id123456", "platform": "vk", "username": "ivan_petrov"}], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79991112233"}, {"type": "work", "number": "+74951234567"}], "address_country": "Россия", "termination_date": null}', 'teacher_ivan', '2026-01-21 00:58:16.824019');
INSERT INTO public.audit_log VALUES (15, 'employees', 1, 'UPDATE', '{"id": 1, "emails": [{"type": "work", "address": "petrov@school.ru"}, {"type": "personal", "address": "ivan.petrov@gmail.com"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Петров", "birth_date": "1985-05-15", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Иван", "is_teacher": true, "updated_at": "2026-01-20T17:53:08.724883", "middle_name": "Сергеевич", "address_city": "Москва", "social_media": [{"url": "https://vk.com/id123456", "platform": "vk", "username": "ivan_petrov"}], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79991112233"}, {"type": "work", "number": "+74951234567"}], "address_country": "Россия", "termination_date": null}', '{"id": 1, "emails": [{"type": "work", "address": "petrov@school.ru"}, {"type": "personal", "address": "ivan.petrov@gmail.com"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Петров", "birth_date": "1985-05-15", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Иван1", "is_teacher": true, "updated_at": "2026-01-21T00:58:16.824019", "middle_name": "Сергеевич", "address_city": "Москва", "social_media": [{"url": "https://vk.com/id123456", "platform": "vk", "username": "ivan_petrov"}], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79991112233"}, {"type": "work", "number": "+74951234567"}], "address_country": "Россия", "termination_date": null}', 'teacher_ivan', '2026-01-21 00:58:16.824019');
INSERT INTO public.audit_log VALUES (16, 'employees', 1, 'UPDATE', '{"id": 1, "emails": [{"type": "work", "address": "petrov@school.ru"}, {"type": "personal", "address": "ivan.petrov@gmail.com"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Петров", "birth_date": "1985-05-15", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Иван1", "is_teacher": true, "updated_at": "2026-01-21T00:58:16.824019", "middle_name": "Сергеевич", "address_city": "Москва", "social_media": [{"url": "https://vk.com/id123456", "platform": "vk", "username": "ivan_petrov"}], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79991112233"}, {"type": "work", "number": "+74951234567"}], "address_country": "Россия", "termination_date": null}', '{"id": 1, "emails": [{"type": "work", "address": "petrov@school.ru"}, {"type": "personal", "address": "ivan.petrov@gmail.com"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Петров", "birth_date": "1985-05-15", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Иван", "is_teacher": true, "updated_at": "2026-01-21T00:58:21.156551", "middle_name": "Сергеевич", "address_city": "Москва", "social_media": [{"url": "https://vk.com/id123456", "platform": "vk", "username": "ivan_petrov"}], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79991112233"}, {"type": "work", "number": "+74951234567"}], "address_country": "Россия", "termination_date": null}', 'teacher_ivan', '2026-01-21 00:58:21.156551');
INSERT INTO public.audit_log VALUES (17, 'employees', 1, 'UPDATE', '{"id": 1, "emails": [{"type": "work", "address": "petrov@school.ru"}, {"type": "personal", "address": "ivan.petrov@gmail.com"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Петров", "birth_date": "1985-05-15", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Иван1", "is_teacher": true, "updated_at": "2026-01-21T00:58:16.824019", "middle_name": "Сергеевич", "address_city": "Москва", "social_media": [{"url": "https://vk.com/id123456", "platform": "vk", "username": "ivan_petrov"}], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79991112233"}, {"type": "work", "number": "+74951234567"}], "address_country": "Россия", "termination_date": null}', '{"id": 1, "emails": [{"type": "work", "address": "petrov@school.ru"}, {"type": "personal", "address": "ivan.petrov@gmail.com"}], "gender": "male", "hire_date": "2026-01-20", "is_active": true, "last_name": "Петров", "birth_date": "1985-05-15", "created_at": "2026-01-20T17:27:43.009838", "first_name": "Иван", "is_teacher": true, "updated_at": "2026-01-21T00:58:21.156551", "middle_name": "Сергеевич", "address_city": "Москва", "social_media": [{"url": "https://vk.com/id123456", "platform": "vk", "username": "ivan_petrov"}], "employee_type": "teacher", "phone_numbers": [{"type": "mobile", "number": "+79991112233"}, {"type": "work", "number": "+74951234567"}], "address_country": "Россия", "termination_date": null}', 'teacher_ivan', '2026-01-21 00:58:21.156551');


--
-- TOC entry 5057 (class 0 OID 17216)
-- Dependencies: 230
-- Data for Name: education; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.education VALUES (1, 1, 'Московский государственный университет', 'Россия', 'Москва', '123456', NULL, NULL, 10, 1, 'Математика', NULL, NULL, 2007, NULL, '2026-01-20 18:03:17.629135', '2026-01-20 18:03:17.629135');
INSERT INTO public.education VALUES (2, 1, 'Высшая школа экономики', 'Россия', 'Москва', '789012', NULL, NULL, 15, 2, 'Педагогическое образование', NULL, NULL, 2010, NULL, '2026-01-20 18:03:17.629135', '2026-01-20 18:03:17.629135');
INSERT INTO public.education VALUES (3, 2, 'Санкт-Петербургский государственный университет', 'Россия', 'Санкт-Петербург', '345678', NULL, NULL, 10, 8, 'Филология', NULL, NULL, 2012, NULL, '2026-01-20 18:03:17.629135', '2026-01-20 18:03:17.629135');
INSERT INTO public.education VALUES (4, 2, 'Российский государственный педагогический университет', 'Россия', 'Санкт-Петербург', '901234', NULL, NULL, 19, 9, 'Методика преподавания русского языка', NULL, NULL, 2015, NULL, '2026-01-20 18:03:17.629135', '2026-01-20 18:03:17.629135');
INSERT INTO public.education VALUES (5, 3, 'Казанский федеральный университет', 'Россия', 'Казань', '567890', NULL, NULL, 10, 5, 'Физика', NULL, NULL, 2005, NULL, '2026-01-20 18:03:17.629135', '2026-01-20 18:03:17.629135');
INSERT INTO public.education VALUES (6, 4, 'Московский государственный университет', 'Россия', 'Москва', '112233', NULL, NULL, 10, 37, 'Психология', NULL, NULL, 2010, NULL, '2026-01-20 18:03:17.629135', '2026-01-20 18:03:17.629135');
INSERT INTO public.education VALUES (7, 4, 'Академия народного хозяйства', 'Россия', 'Москва', '445566', NULL, NULL, 16, 38, 'Управление персоналом', NULL, NULL, 2013, NULL, '2026-01-20 18:03:17.629135', '2026-01-20 18:03:17.629135');
INSERT INTO public.education VALUES (8, 1, 'Российский университет дружбы народов', 'Россия', 'Москва', 'RUDN-2020-001', 'МО', '2020-06-15', 20, 2, 'Педагогика высшей школы', '2019-09-01', '2020-06-01', 2020, 'Отлично', '2026-01-20 18:19:43.673841', '2026-01-20 18:19:43.673841');
INSERT INTO public.education VALUES (9, 2, 'Кембриджский университет', 'Великобритания', 'Кембридж', 'CAM-2018-UK', NULL, '2018-08-20', 28, 12, 'Методика преподавания английского языка', '2017-09-15', '2018-08-15', 2018, 'Отлично', '2026-01-20 18:19:43.673841', '2026-01-20 18:19:43.673841');
INSERT INTO public.education VALUES (10, 3, 'Московский физико-технический институт', 'Россия', 'Москва', 'MIPT-2016-045', 'ФЗ', '2016-07-10', 11, 6, 'Ядерная физика', '2014-09-01', '2016-06-30', 2016, 'Отлично', '2026-01-20 18:19:43.673841', '2026-01-20 18:19:43.673841');
INSERT INTO public.education VALUES (11, 4, 'Coursera / University of Michigan', 'США', 'Анн-Арбор', 'COURSERA-2021-UM', NULL, '2021-12-01', 31, 38, 'Современные HR-технологии', '2021-09-01', '2021-12-01', 2021, 'Зачтено', '2026-01-20 18:19:43.673841', '2026-01-20 18:19:43.673841');
INSERT INTO public.education VALUES (12, 5, 'Уральский федеральный университет', 'Россия', 'Екатеринбург', 'URFU-2015-789', 'ИТ', '2015-06-25', 6, 16, 'Программная инженерия', '2011-09-01', '2015-06-20', 2015, 'Хорошо', '2026-01-20 18:19:43.673841', '2026-01-20 18:19:43.673841');
INSERT INTO public.education VALUES (13, 1, 'Московский педагогический государственный университет', 'Россия', 'Москва', 'MPGU-2012-567', 'ПД', '2012-07-05', 8, 52, 'Методика преподавания математики', '2007-09-01', '2012-06-30', 2012, 'Отлично', '2026-01-20 18:19:43.673841', '2026-01-20 18:19:43.673841');
INSERT INTO public.education VALUES (14, 2, 'Центр педагогического мастерства', 'Россия', 'Москва', 'CPM-2022-123', NULL, '2022-11-30', 17, 9, 'Подготовка экспертов ЕГЭ', '2022-09-15', '2022-11-30', 2022, 'Зачтено', '2026-01-20 18:19:43.673841', '2026-01-20 18:19:43.673841');
INSERT INTO public.education VALUES (15, 3, 'Объединенный институт ядерных исследований', 'Россия', 'Дубна', 'JINR-2010-789', NULL, '2010-06-20', 12, 4, 'Теоретическая физика', '2005-09-01', '2010-06-15', 2010, 'Успешно', '2026-01-20 18:19:43.673841', '2026-01-20 18:19:43.673841');
INSERT INTO public.education VALUES (16, 4, 'Google for Education', 'США', 'Маунтин-Вью', 'GOOGLE-2023-001', NULL, '2023-03-15', 32, 39, 'Лидерство и управление командами', '2023-01-15', '2023-03-15', 2023, 'Сертификат', '2026-01-20 18:19:43.673841', '2026-01-20 18:19:43.673841');
INSERT INTO public.education VALUES (17, 5, 'Яндекс.Практикум', 'Россия', 'Москва', 'YANDEX-2022-456', NULL, '2022-10-20', 18, 46, 'DevOps: быстрый старт', '2022-03-01', '2022-10-15', 2022, 'Отлично', '2026-01-20 18:19:43.673841', '2026-01-20 18:19:43.673841');
INSERT INTO public.education VALUES (18, 1, 'Лицей №1535', 'Россия', 'Москва', 'АВ-123456', NULL, '2002-06-25', 1, NULL, 'Среднее общее образование', '1992-09-01', '2002-06-25', 2002, 'Золотая медаль', '2026-01-20 18:19:43.673841', '2026-01-20 18:19:43.673841');
INSERT INTO public.education VALUES (19, 2, 'Гимназия №610 "Петершуле"', 'Россия', 'Санкт-Петербург', 'ГИМ-1999-001', NULL, '1999-06-20', 1, NULL, 'Среднее общее образование', '1988-09-01', '1999-06-15', 1999, 'Серебряная медаль', '2026-01-20 18:19:43.673841', '2026-01-20 18:19:43.673841');
INSERT INTO public.education VALUES (20, 3, 'Сколковский институт науки и технологий', 'Россия', 'Москва', 'SKOLTECH-2019-333', NULL, '2019-11-30', 25, 17, 'Искусственный интеллект в науке', '2019-09-01', '2019-11-25', 2019, 'Зачтено', '2026-01-20 18:19:43.673841', '2026-01-20 18:19:43.673841');
INSERT INTO public.education VALUES (21, 4, 'Российская академия народного хозяйства', 'Россия', 'Москва', 'RANEPA-2018-777', NULL, '2018-05-20', 16, 37, 'Психология управления', '2018-02-15', '2018-05-15', 2018, 'Отлично', '2026-01-20 18:19:43.673841', '2026-01-20 18:19:43.673841');
INSERT INTO public.education VALUES (22, 5, 'Новосибирский государственный технический университет', 'Россия', 'Новосибирск', 'NSTU-2014-888', 'ТЕХ', '2014-06-30', 6, 18, 'Автоматизированные системы управления', '2010-09-01', '2014-06-25', 2014, 'Хорошо', '2026-01-20 18:19:43.673841', '2026-01-20 18:19:43.673841');


--
-- TOC entry 5049 (class 0 OID 17163)
-- Dependencies: 222
-- Data for Name: education_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.education_types VALUES (1, 'secondary_complete', 'Среднее общее образование (полное)', 'Complete Secondary Education', 132, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (2, 'secondary_basic', 'Основное общее образование', 'Basic Secondary Education', 108, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (3, 'vocational_primary', 'Начальное профессиональное образование', 'Primary Vocational Education', 24, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (4, 'vocational_secondary', 'Среднее профессиональное образование', 'Secondary Vocational Education', 34, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (5, 'vocational_secondary_advanced', 'Среднее профессиональное образование (углубленная подготовка)', 'Advanced Secondary Vocational Education', 46, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (6, 'higher_bachelor', 'Высшее образование (бакалавриат)', 'Higher Education (Bachelor)', 48, true, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (7, 'higher_bachelor_applied', 'Высшее образование (прикладной бакалавриат)', 'Higher Education (Applied Bachelor)', 48, true, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (8, 'higher_specialist', 'Высшее образование (специалитет)', 'Higher Education (Specialist)', 60, true, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (9, 'higher_specialist_doctor', 'Высшее медицинское образование (специалитет)', 'Higher Medical Education (Specialist)', 72, true, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (10, 'higher_master', 'Высшее образование (магистратура)', 'Higher Education (Master)', 24, true, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (11, 'higher_master_research', 'Научно-исследовательская магистратура', 'Research Master', 24, true, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (12, 'higher_phd_candidate', 'Аспирантура (кандидат наук)', 'PhD Program (Candidate of Sciences)', 36, true, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (13, 'higher_phd_doctoral', 'Докторантура (доктор наук)', 'Doctoral Program (Doctor of Sciences)', 36, true, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (14, 'higher_phd', 'Адъюнктура/аспирантура', 'Postgraduate Studies', 36, true, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (15, 'qualification_upgrade_short', 'Повышение квалификации (краткосрочное)', 'Short-term Qualification Upgrade', 1, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (16, 'qualification_upgrade_long', 'Повышение квалификации (длительное)', 'Long-term Qualification Upgrade', 3, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (17, 'qualification_upgrade_advanced', 'Повышение квалификации (повышенный уровень)', 'Advanced Qualification Upgrade', 6, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (18, 'professional_retraining_min', 'Профессиональная переподготовка (минимум)', 'Professional Retraining (Minimum)', 6, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (19, 'professional_retraining_standard', 'Профессиональная переподготовка (стандарт)', 'Professional Retraining (Standard)', 12, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (20, 'professional_retraining_extended', 'Профессиональная переподготовка (расширенная)', 'Professional Retraining (Extended)', 18, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (21, 'internship_production', 'Производственная практика', 'Production Internship', 3, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (22, 'internship_pedagogical', 'Педагогическая практика', 'Pedagogical Internship', 2, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (23, 'internship_research', 'Научно-исследовательская практика', 'Research Internship', 3, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (24, 'courses_short', 'Краткосрочные курсы', 'Short-term Courses', 1, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (25, 'courses_long', 'Длительные курсы', 'Long-term Courses', 3, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (26, 'seminars_workshops', 'Семинары и тренинги', 'Seminars and Workshops', 0, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (27, 'international_bachelor', 'Международное бакалаврское образование', 'International Bachelor Degree', 48, true, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (28, 'international_master', 'Международное магистерское образование', 'International Master Degree', 24, true, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (29, 'international_phd', 'Международная аспирантура', 'International PhD', 36, true, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (30, 'self_education', 'Самообразование', 'Self-education', NULL, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (31, 'online_courses', 'Онлайн-курсы', 'Online Courses', NULL, false, '2026-01-20 18:07:35.361091');
INSERT INTO public.education_types VALUES (32, 'corporate_training', 'Корпоративное обучение', 'Corporate Training', NULL, false, '2026-01-20 18:07:35.361091');


--
-- TOC entry 5045 (class 0 OID 17002)
-- Dependencies: 218
-- Data for Name: employees; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.employees VALUES (1, 'Иван', 'Петров', 'Сергеевич', '1985-05-15', 'male', 'Россия', 'Москва', '[{"type": "mobile", "number": "+79991112233"}, {"type": "work", "number": "+74951234567"}]', '[{"type": "work", "address": "petrov@school.ru"}, {"type": "personal", "address": "ivan.petrov@gmail.com"}]', '[{"url": "https://vk.com/id123456", "platform": "vk", "username": "ivan_petrov"}]', '2026-01-20', NULL, true, true, 'teacher', '2026-01-20 17:27:43.009838', '2026-01-21 00:58:21.156551');
INSERT INTO public.employees VALUES (2, 'Мария', 'Сидорова', 'Ивановна', '1990-08-22', 'female', 'Россия', 'Санкт-Петербург', '[{"type": "mobile", "number": "+79997778899"}]', '[{"type": "work", "address": "sidorova@school.ru"}]', '[{"url": "https://vk.com/maria_sidorova", "platform": "vk", "username": "maria_sidorova"}, {"platform": "telegram", "username": "@maria_sidorova"}]', '2026-01-20', NULL, true, true, 'teacher', '2026-01-20 17:27:43.009838', '2026-01-20 17:53:08.724883');
INSERT INTO public.employees VALUES (3, 'Алексей', 'Кузнецов', 'Андреевич', '1982-11-30', 'male', 'Россия', 'Казань', '[{"type": "mobile", "number": "+79993334455"}, {"type": "home", "number": "+78432111222"}]', '[{"type": "work", "address": "kuznetsov@school.ru"}]', '[{"url": "https://vk.com/alexey_kuznetsov", "platform": "vk", "username": "alexey_k"}, {"platform": "telegram", "username": "@alexey_kuznetsov"}]', '2026-01-20', NULL, true, true, 'teacher', '2026-01-20 17:27:43.009838', '2026-01-20 17:53:08.724883');
INSERT INTO public.employees VALUES (4, 'Анна', 'Смирнова', 'Викторовна', '1988-03-10', 'female', 'Россия', 'Москва', '[{"type": "mobile", "number": "+79994445566"}]', '[{"type": "work", "address": "hr@school.ru"}]', '[{"url": "https://vk.com/anna_smirnova", "platform": "vk", "username": "anna_s"}, {"platform": "telegram", "username": "@anna_smirnova_hr"}]', '2026-01-20', NULL, true, false, 'administrator', '2026-01-20 17:27:43.009838', '2026-01-20 17:53:08.724883');
INSERT INTO public.employees VALUES (5, 'Дмитрий', 'Васильев', 'Олегович', '1992-07-18', 'male', 'Россия', 'Новосибирск', '[{"type": "mobile", "number": "+79995556677"}]', '[{"type": "work", "address": "support@school.ru"}]', '[{"url": "https://vk.com/dmitry_vasilev", "platform": "vk", "username": "dmitry_v"}, {"platform": "telegram", "username": "@dmitry_support"}]', '2026-01-20', NULL, true, false, 'support', '2026-01-20 17:27:43.009838', '2026-01-20 17:53:08.724883');


--
-- TOC entry 5051 (class 0 OID 17176)
-- Dependencies: 224
-- Data for Name: qualifications; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.qualifications VALUES (1, 'Математик', 'Mathematician', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (2, 'Учитель математики', 'Mathematics Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (3, 'Репетитор по математике', 'Math Tutor', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (4, 'Профессор математики', 'Professor of Mathematics', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (5, 'Физик', 'Physicist', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (6, 'Учитель физики', 'Physics Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (7, 'Астроном', 'Astronomer', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (8, 'Филолог', 'Philologist', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (9, 'Учитель русского языка', 'Russian Language Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (10, 'Учитель литературы', 'Literature Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (11, 'Лингвист', 'Linguist', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (12, 'Учитель английского языка', 'English Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (13, 'Учитель немецкого языка', 'German Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (14, 'Учитель французского языка', 'French Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (15, 'Переводчик', 'Translator', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (16, 'Программист', 'Programmer', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (17, 'Учитель информатики', 'Informatics Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (18, 'IT-специалист', 'IT Specialist', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (19, 'Химик', 'Chemist', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (20, 'Учитель химии', 'Chemistry Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (21, 'Биолог', 'Biologist', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (22, 'Учитель биологии', 'Biology Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (23, 'Географ', 'Geographer', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (24, 'Историк', 'Historian', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (25, 'Учитель истории', 'History Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (26, 'Обществовед', 'Social Scientist', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (27, 'Учитель права', 'Law Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (28, 'Учитель рисования', 'Art Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (29, 'Учитель музыки', 'Music Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (30, 'Хореограф', 'Choreographer', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (31, 'Учитель физкультуры', 'Physical Education Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (32, 'Тренер', 'Coach', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (33, 'Учитель начальных классов', 'Primary School Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (34, 'Воспитатель ДОУ', 'Preschool Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (35, 'Дефектолог', 'Special Education Teacher', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (36, 'Логопед', 'Speech Therapist', 'teaching', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (37, 'Психолог', 'Psychologist', 'administrative', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (38, 'HR-менеджер', 'HR Manager', 'administrative', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (39, 'Директор по персоналу', 'HR Director', 'administrative', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (40, 'Рекрутер', 'Recruiter', 'administrative', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (41, 'Офис-менеджер', 'Office Manager', 'administrative', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (42, 'Бухгалтер', 'Accountant', 'administrative', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (43, 'Юрист', 'Lawyer', 'administrative', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (44, 'Системный администратор', 'System Administrator', 'technical', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (45, 'Сетевой инженер', 'Network Engineer', 'technical', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (46, 'DevOps-инженер', 'DevOps Engineer', 'technical', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (47, 'Специалист поддержки', 'Support Specialist', 'technical', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (48, 'Веб-разработчик', 'Web Developer', 'technical', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (49, 'Дизайнер', 'Designer', 'technical', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (50, 'Директор школы', 'School Director', 'management', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (51, 'Завуч', 'Department Head', 'management', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (52, 'Методист', 'Methodologist', 'management', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (53, 'Менеджер проектов', 'Project Manager', 'management', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (54, 'Библиотекарь', 'Librarian', 'other', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (55, 'Лаборант', 'Laboratory Assistant', 'other', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (56, 'Секретарь', 'Secretary', 'other', '2026-01-20 18:26:25.837539');
INSERT INTO public.qualifications VALUES (57, 'Водитель', 'Driver', 'other', '2026-01-20 18:26:25.837539');


--
-- TOC entry 5059 (class 0 OID 17244)
-- Dependencies: 232
-- Data for Name: school_programs; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.school_programs VALUES (1, 1, 1, 1, '2026-01-20 19:00:28.247571', '2026-01-20 19:00:28.247571', 'Олимпиадная математика для младших школьников', 2026, 72);
INSERT INTO public.school_programs VALUES (2, 1, 1, 2, '2026-01-20 19:00:28.247571', '2026-01-20 19:00:28.247571', 'Подготовка к ОГЭ по математике', 2026, 100);
INSERT INTO public.school_programs VALUES (4, 2, 2, 1, '2026-01-20 19:00:28.247571', '2026-01-20 19:00:28.247571', 'Обучение грамоте', 2026, 48);
INSERT INTO public.school_programs VALUES (5, 2, 2, 2, '2026-01-20 19:00:28.247571', '2026-01-20 19:00:28.247571', 'Подготовка к ОГЭ по русскому', 2026, 80);
INSERT INTO public.school_programs VALUES (7, 3, 3, 2, '2026-01-20 19:00:28.247571', '2026-01-20 19:00:28.247571', 'Экспериментальная физика', 2026, 60);
INSERT INTO public.school_programs VALUES (9, 3, 5, 3, '2026-01-20 19:00:28.247571', '2026-01-20 19:00:28.247571', 'Python для начинающих', 2026, 72);


--
-- TOC entry 5053 (class 0 OID 17189)
-- Dependencies: 226
-- Data for Name: subjects; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.subjects VALUES (1, 'math', 'Математика', 'Mathematics', 'core', 'Основной предмет, алгебра и геометрия', true, '2026-01-20 19:00:03.456212');
INSERT INTO public.subjects VALUES (2, 'russian', 'Русский язык', 'Russian Language', 'core', 'Родной язык и грамотность', true, '2026-01-20 19:00:03.456212');
INSERT INTO public.subjects VALUES (3, 'physics', 'Физика', 'Physics', 'science', 'Естественные науки, механика, оптика', true, '2026-01-20 19:00:03.456212');
INSERT INTO public.subjects VALUES (6, 'literature', 'Литература', 'Literature', 'humanities', 'Художественная литература', true, '2026-01-20 19:00:03.456212');
INSERT INTO public.subjects VALUES (5, 'programming', 'Информатика', 'Computer Science', 'computer', 'Основы программирования', true, '2026-01-20 19:00:03.456212');
INSERT INTO public.subjects VALUES (4, 'english', 'Английский язык', 'English', 'foreign language', 'Иностранный язык', true, '2026-01-20 19:00:03.456212');


--
-- TOC entry 5060 (class 0 OID 17943)
-- Dependencies: 239
-- Data for Name: teacher_user_mapping; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.teacher_user_mapping VALUES ('teacher_ivan', 1, '2026-01-22 17:57:56.05912', '2026-01-22 17:57:56.05912');
INSERT INTO public.teacher_user_mapping VALUES ('teacher_maria', 2, '2026-01-22 17:57:56.05912', '2026-01-22 17:57:56.05912');
INSERT INTO public.teacher_user_mapping VALUES ('teacher_alexey', 3, '2026-01-22 17:57:56.05912', '2026-01-22 17:57:56.05912');
INSERT INTO public.teacher_user_mapping VALUES ('hr_anna', 4, '2026-01-22 17:57:56.05912', '2026-01-22 17:57:56.05912');
INSERT INTO public.teacher_user_mapping VALUES ('employee_dmitry', 5, '2026-01-22 17:57:56.05912', '2026-01-22 17:57:56.05912');


--
-- TOC entry 5117 (class 0 OID 0)
-- Dependencies: 227
-- Name: age_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.age_groups_id_seq', 3, true);


--
-- TOC entry 5118 (class 0 OID 0)
-- Dependencies: 219
-- Name: audit_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.audit_log_id_seq', 17, true);


--
-- TOC entry 5119 (class 0 OID 0)
-- Dependencies: 229
-- Name: education_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.education_id_seq', 22, true);


--
-- TOC entry 5120 (class 0 OID 0)
-- Dependencies: 221
-- Name: education_types_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.education_types_id_seq', 32, true);


--
-- TOC entry 5121 (class 0 OID 0)
-- Dependencies: 217
-- Name: employees_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.employees_id_seq', 7, true);


--
-- TOC entry 5122 (class 0 OID 0)
-- Dependencies: 223
-- Name: qualifications_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.qualifications_id_seq', 57, true);


--
-- TOC entry 5123 (class 0 OID 0)
-- Dependencies: 225
-- Name: subjects_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.subjects_id_seq', 6, true);


--
-- TOC entry 5124 (class 0 OID 0)
-- Dependencies: 231
-- Name: teacher_subjects_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.teacher_subjects_id_seq', 9, true);


--
-- TOC entry 4833 (class 2606 OID 17213)
-- Name: age_groups age_groups_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.age_groups
    ADD CONSTRAINT age_groups_code_key UNIQUE (code);


--
-- TOC entry 4835 (class 2606 OID 17211)
-- Name: age_groups age_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.age_groups
    ADD CONSTRAINT age_groups_pkey PRIMARY KEY (id);


--
-- TOC entry 4818 (class 2606 OID 17141)
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- TOC entry 4837 (class 2606 OID 17227)
-- Name: education education_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.education
    ADD CONSTRAINT education_pkey PRIMARY KEY (id);


--
-- TOC entry 4820 (class 2606 OID 17174)
-- Name: education_types education_types_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.education_types
    ADD CONSTRAINT education_types_code_key UNIQUE (code);


--
-- TOC entry 4822 (class 2606 OID 17172)
-- Name: education_types education_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.education_types
    ADD CONSTRAINT education_types_pkey PRIMARY KEY (id);


--
-- TOC entry 4808 (class 2606 OID 17022)
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (id);


--
-- TOC entry 4827 (class 2606 OID 17185)
-- Name: qualifications qualifications_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.qualifications
    ADD CONSTRAINT qualifications_pkey PRIMARY KEY (id);


--
-- TOC entry 4829 (class 2606 OID 17200)
-- Name: subjects subjects_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subjects
    ADD CONSTRAINT subjects_code_key UNIQUE (code);


--
-- TOC entry 4831 (class 2606 OID 17198)
-- Name: subjects subjects_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subjects
    ADD CONSTRAINT subjects_pkey PRIMARY KEY (id);


--
-- TOC entry 4839 (class 2606 OID 17260)
-- Name: school_programs teacher_subjects_employee_id_subject_id_age_group_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_programs
    ADD CONSTRAINT teacher_subjects_employee_id_subject_id_age_group_id_key UNIQUE (employee_id, subject_id, age_group_id);


--
-- TOC entry 4841 (class 2606 OID 17258)
-- Name: school_programs teacher_subjects_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_programs
    ADD CONSTRAINT teacher_subjects_pkey PRIMARY KEY (id);


--
-- TOC entry 4845 (class 2606 OID 17951)
-- Name: teacher_user_mapping teacher_user_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.teacher_user_mapping
    ADD CONSTRAINT teacher_user_mapping_pkey PRIMARY KEY (pg_username);


--
-- TOC entry 4809 (class 1259 OID 17161)
-- Name: idx_active_teachers; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_active_teachers ON public.employees USING btree (id) WHERE ((is_teacher = true) AND (is_active = true));


--
-- TOC entry 4823 (class 1259 OID 17276)
-- Name: idx_education_types_code; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_education_types_code ON public.education_types USING btree (code);


--
-- TOC entry 4824 (class 1259 OID 17278)
-- Name: idx_education_types_duration; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_education_types_duration ON public.education_types USING btree (duration_months);


--
-- TOC entry 4825 (class 1259 OID 17277)
-- Name: idx_education_types_is_higher; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_education_types_is_higher ON public.education_types USING btree (is_higher_education);


--
-- TOC entry 4810 (class 1259 OID 17158)
-- Name: idx_emails_gin; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_emails_gin ON public.employees USING gin (emails);


--
-- TOC entry 4811 (class 1259 OID 17069)
-- Name: idx_employees_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_employees_active ON public.employees USING btree (is_active);


--
-- TOC entry 4812 (class 1259 OID 17080)
-- Name: idx_employees_fulltext; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_employees_fulltext ON public.employees USING gin (to_tsvector('russian'::regconfig, (((((last_name)::text || ' '::text) || (first_name)::text) || ' '::text) || (COALESCE(middle_name, ''::character varying))::text)));


--
-- TOC entry 4813 (class 1259 OID 17072)
-- Name: idx_employees_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_employees_name ON public.employees USING btree (last_name, first_name);


--
-- TOC entry 4814 (class 1259 OID 17070)
-- Name: idx_employees_teachers; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_employees_teachers ON public.employees USING btree (is_teacher) WHERE (is_teacher = true);


--
-- TOC entry 4815 (class 1259 OID 17071)
-- Name: idx_employees_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_employees_type ON public.employees USING btree (employee_type);


--
-- TOC entry 4816 (class 1259 OID 17159)
-- Name: idx_phone_numbers_gin; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_phone_numbers_gin ON public.employees USING gin (phone_numbers);


--
-- TOC entry 4842 (class 1259 OID 17958)
-- Name: idx_teacher_mapping_employee; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_teacher_mapping_employee ON public.teacher_user_mapping USING btree (employee_id);


--
-- TOC entry 4843 (class 1259 OID 17957)
-- Name: idx_teacher_mapping_username; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_teacher_mapping_username ON public.teacher_user_mapping USING btree (pg_username);


--
-- TOC entry 4853 (class 2620 OID 17143)
-- Name: employees audit_employees_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER audit_employees_trigger AFTER INSERT OR DELETE OR UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_function();


--
-- TOC entry 4856 (class 2620 OID 17428)
-- Name: education education_audit_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER education_audit_trigger AFTER INSERT OR DELETE OR UPDATE ON public.education FOR EACH ROW EXECUTE FUNCTION public.log_employee_changes();


--
-- TOC entry 4854 (class 2620 OID 17427)
-- Name: employees employees_audit_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER employees_audit_trigger AFTER INSERT OR DELETE OR UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.log_employee_changes();


--
-- TOC entry 4857 (class 2620 OID 17429)
-- Name: school_programs school_programs_audit_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER school_programs_audit_trigger AFTER INSERT OR DELETE OR UPDATE ON public.school_programs FOR EACH ROW EXECUTE FUNCTION public.log_employee_changes();


--
-- TOC entry 4855 (class 2620 OID 17082)
-- Name: employees update_employees_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_employees_updated_at BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 4846 (class 2606 OID 17233)
-- Name: education education_education_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.education
    ADD CONSTRAINT education_education_type_id_fkey FOREIGN KEY (education_type_id) REFERENCES public.education_types(id);


--
-- TOC entry 4847 (class 2606 OID 17228)
-- Name: education education_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.education
    ADD CONSTRAINT education_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 4848 (class 2606 OID 17238)
-- Name: education education_qualification_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.education
    ADD CONSTRAINT education_qualification_id_fkey FOREIGN KEY (qualification_id) REFERENCES public.qualifications(id);


--
-- TOC entry 4849 (class 2606 OID 17271)
-- Name: school_programs teacher_subjects_age_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_programs
    ADD CONSTRAINT teacher_subjects_age_group_id_fkey FOREIGN KEY (age_group_id) REFERENCES public.age_groups(id);


--
-- TOC entry 4850 (class 2606 OID 17261)
-- Name: school_programs teacher_subjects_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_programs
    ADD CONSTRAINT teacher_subjects_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 4851 (class 2606 OID 17266)
-- Name: school_programs teacher_subjects_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_programs
    ADD CONSTRAINT teacher_subjects_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- TOC entry 4852 (class 2606 OID 17952)
-- Name: teacher_user_mapping teacher_user_mapping_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.teacher_user_mapping
    ADD CONSTRAINT teacher_user_mapping_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5020 (class 3256 OID 17088)
-- Name: employees admin_limited_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY admin_limited_update ON public.employees FOR UPDATE TO administrator_role USING ((is_active = true)) WITH CHECK ((is_active = true));


--
-- TOC entry 5019 (class 3256 OID 17087)
-- Name: employees admin_view_access; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY admin_view_access ON public.employees FOR SELECT TO administrator_role USING ((is_active = true));


--
-- TOC entry 5014 (class 0 OID 17202)
-- Dependencies: 228
-- Name: age_groups; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.age_groups ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 5042 (class 3256 OID 17450)
-- Name: audit_log allow_all_inserts; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY allow_all_inserts ON public.audit_log FOR INSERT WITH CHECK (true);


--
-- TOC entry 5010 (class 0 OID 17132)
-- Dependencies: 220
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 5015 (class 0 OID 17216)
-- Dependencies: 230
-- Name: education; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.education ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 5011 (class 0 OID 17163)
-- Dependencies: 222
-- Name: education_types; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.education_types ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 5009 (class 0 OID 17002)
-- Dependencies: 218
-- Name: employees; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 5039 (class 3256 OID 17389)
-- Name: audit_log hr_audit_log; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY hr_audit_log ON public.audit_log TO hr_specialist USING (true);


--
-- TOC entry 5025 (class 3256 OID 17373)
-- Name: education hr_education_all; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY hr_education_all ON public.education TO hr_specialist USING (true) WITH CHECK (true);


--
-- TOC entry 5022 (class 3256 OID 17367)
-- Name: employees hr_employees_all; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY hr_employees_all ON public.employees TO hr_specialist USING (true) WITH CHECK (true);


--
-- TOC entry 5018 (class 3256 OID 17084)
-- Name: employees hr_full_access; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY hr_full_access ON public.employees TO hr_department USING ((is_active = true));


--
-- TOC entry 5028 (class 3256 OID 17377)
-- Name: school_programs hr_school_programs_all; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY hr_school_programs_all ON public.school_programs TO hr_specialist USING (true) WITH CHECK (true);


--
-- TOC entry 5043 (class 3256 OID 17961)
-- Name: teacher_user_mapping postgres_only; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY postgres_only ON public.teacher_user_mapping TO postgres USING (true);


--
-- TOC entry 5012 (class 0 OID 17176)
-- Dependencies: 224
-- Name: qualifications; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.qualifications ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 5035 (class 3256 OID 17385)
-- Name: age_groups read_age_groups; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY read_age_groups ON public.age_groups FOR SELECT TO hr_specialist, teacher, student, parent, employee, external_service USING (true);


--
-- TOC entry 5038 (class 3256 OID 17388)
-- Name: education_types read_education_types; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY read_education_types ON public.education_types FOR SELECT TO hr_specialist, teacher, student, parent, employee, external_service USING (true);


--
-- TOC entry 5037 (class 3256 OID 17387)
-- Name: qualifications read_qualifications; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY read_qualifications ON public.qualifications FOR SELECT TO hr_specialist, teacher, student, parent, employee, external_service USING (true);


--
-- TOC entry 5036 (class 3256 OID 17386)
-- Name: subjects read_subjects; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY read_subjects ON public.subjects FOR SELECT TO hr_specialist, teacher, student, parent, employee, external_service USING (true);


--
-- TOC entry 5016 (class 0 OID 17244)
-- Dependencies: 232
-- Name: school_programs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.school_programs ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 5027 (class 3256 OID 17376)
-- Name: education service_education_view; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY service_education_view ON public.education FOR SELECT TO external_service USING ((employee_id IN ( SELECT employees.id
   FROM public.employees
  WHERE ((employees.is_teacher = true) AND (employees.is_active = true)))));


--
-- TOC entry 5024 (class 3256 OID 17372)
-- Name: employees service_employees_view; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY service_employees_view ON public.employees FOR SELECT TO external_service USING (((is_teacher = true) AND (is_active = true)));


--
-- TOC entry 5030 (class 3256 OID 17380)
-- Name: school_programs service_school_programs_view; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY service_school_programs_view ON public.school_programs FOR SELECT TO external_service USING (true);


--
-- TOC entry 5026 (class 3256 OID 17375)
-- Name: education student_parent_education_view; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY student_parent_education_view ON public.education FOR SELECT TO student, parent USING ((employee_id IN ( SELECT employees.id
   FROM public.employees
  WHERE ((employees.is_teacher = true) AND (employees.is_active = true)))));


--
-- TOC entry 5023 (class 3256 OID 17370)
-- Name: employees student_parent_employees_view; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY student_parent_employees_view ON public.employees FOR SELECT TO student, parent USING (((is_teacher = true) AND (is_active = true)));


--
-- TOC entry 5029 (class 3256 OID 17379)
-- Name: school_programs student_parent_school_programs_view; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY student_parent_school_programs_view ON public.school_programs FOR SELECT TO student, parent USING ((employee_id IN ( SELECT employees.id
   FROM public.employees
  WHERE ((employees.is_teacher = true) AND (employees.is_active = true)))));


--
-- TOC entry 5013 (class 0 OID 17189)
-- Dependencies: 226
-- Name: subjects; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 5041 (class 3256 OID 17449)
-- Name: audit_log teacher_see_own_audit; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY teacher_see_own_audit ON public.audit_log FOR SELECT TO teacher_ivan USING (((changed_by)::text = CURRENT_USER));


--
-- TOC entry 5040 (class 3256 OID 17448)
-- Name: employees teacher_see_own_data; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY teacher_see_own_data ON public.employees TO teacher_ivan USING ((id = public.get_current_user_id())) WITH CHECK ((id = public.get_current_user_id()));


--
-- TOC entry 5021 (class 3256 OID 17089)
-- Name: employees teacher_self_access; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY teacher_self_access ON public.employees TO teacher_role USING ((id = (current_setting('app.current_user_id'::text, true))::integer));


--
-- TOC entry 5017 (class 0 OID 17943)
-- Dependencies: 239
-- Name: teacher_user_mapping; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.teacher_user_mapping ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 5031 (class 3256 OID 17381)
-- Name: age_groups write_age_groups; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY write_age_groups ON public.age_groups TO hr_specialist USING (true) WITH CHECK (true);


--
-- TOC entry 5034 (class 3256 OID 17384)
-- Name: education_types write_education_types; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY write_education_types ON public.education_types TO hr_specialist USING (true) WITH CHECK (true);


--
-- TOC entry 5033 (class 3256 OID 17383)
-- Name: qualifications write_qualifications; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY write_qualifications ON public.qualifications TO hr_specialist USING (true) WITH CHECK (true);


--
-- TOC entry 5032 (class 3256 OID 17382)
-- Name: subjects write_subjects; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY write_subjects ON public.subjects TO hr_specialist USING (true) WITH CHECK (true);


--
-- TOC entry 5068 (class 0 OID 0)
-- Dependencies: 5066
-- Name: DATABASE school_hr_db; Type: ACL; Schema: -; Owner: postgres
--

GRANT CONNECT ON DATABASE school_hr_db TO hr_department;
GRANT CONNECT ON DATABASE school_hr_db TO teacher_role;
GRANT CONNECT ON DATABASE school_hr_db TO administrator_role;
GRANT CONNECT ON DATABASE school_hr_db TO schedule_service;
GRANT CONNECT ON DATABASE school_hr_db TO payment_service;
GRANT CONNECT ON DATABASE school_hr_db TO booking_service;
GRANT CONNECT ON DATABASE school_hr_db TO analytics_service;
GRANT CONNECT ON DATABASE school_hr_db TO parent_role;
GRANT CONNECT ON DATABASE school_hr_db TO student_role;


--
-- TOC entry 5069 (class 0 OID 0)
-- Dependencies: 5
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO hr_department;
GRANT USAGE ON SCHEMA public TO teacher_role;
GRANT USAGE ON SCHEMA public TO administrator_role;
GRANT USAGE ON SCHEMA public TO schedule_service;
GRANT USAGE ON SCHEMA public TO payment_service;
GRANT USAGE ON SCHEMA public TO booking_service;
GRANT USAGE ON SCHEMA public TO analytics_service;
GRANT USAGE ON SCHEMA public TO parent_role;
GRANT USAGE ON SCHEMA public TO student_role;
GRANT USAGE ON SCHEMA public TO hr_specialist;
GRANT USAGE ON SCHEMA public TO teacher;
GRANT USAGE ON SCHEMA public TO student;
GRANT USAGE ON SCHEMA public TO parent;
GRANT USAGE ON SCHEMA public TO employee;
GRANT USAGE ON SCHEMA public TO external_service;


--
-- TOC entry 5070 (class 0 OID 0)
-- Dependencies: 259
-- Name: PROCEDURE add_new_teacher(IN p_first_name character varying, IN p_last_name character varying, IN p_middle_name character varying, IN p_birth_date date, IN p_gender character varying, IN p_emails jsonb, IN p_phone_numbers jsonb, IN p_subjects jsonb, IN p_education jsonb); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.add_new_teacher(IN p_first_name character varying, IN p_last_name character varying, IN p_middle_name character varying, IN p_birth_date date, IN p_gender character varying, IN p_emails jsonb, IN p_phone_numbers jsonb, IN p_subjects jsonb, IN p_education jsonb) TO hr_department;


--
-- TOC entry 5071 (class 0 OID 0)
-- Dependencies: 256
-- Name: FUNCTION get_teacher_profile(p_teacher_id integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_teacher_profile(p_teacher_id integer) TO parent_role;
GRANT ALL ON FUNCTION public.get_teacher_profile(p_teacher_id integer) TO schedule_service;
GRANT ALL ON FUNCTION public.get_teacher_profile(p_teacher_id integer) TO booking_service;


--
-- TOC entry 5073 (class 0 OID 0)
-- Dependencies: 257
-- Name: FUNCTION search_teachers(p_subject character varying, p_age_group character varying, p_min_experience integer, p_min_qualification character varying); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.search_teachers(p_subject character varying, p_age_group character varying, p_min_experience integer, p_min_qualification character varying) TO parent_role;
GRANT ALL ON FUNCTION public.search_teachers(p_subject character varying, p_age_group character varying, p_min_experience integer, p_min_qualification character varying) TO booking_service;
GRANT ALL ON FUNCTION public.search_teachers(p_subject character varying, p_age_group character varying, p_min_experience integer, p_min_qualification character varying) TO schedule_service;


--
-- TOC entry 5075 (class 0 OID 0)
-- Dependencies: 228
-- Name: TABLE age_groups; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.age_groups TO hr_specialist;
GRANT SELECT ON TABLE public.age_groups TO teacher;
GRANT SELECT ON TABLE public.age_groups TO student;
GRANT SELECT ON TABLE public.age_groups TO parent;
GRANT SELECT ON TABLE public.age_groups TO employee;
GRANT SELECT ON TABLE public.age_groups TO external_service;


--
-- TOC entry 5077 (class 0 OID 0)
-- Dependencies: 227
-- Name: SEQUENCE age_groups_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.age_groups_id_seq TO hr_specialist;


--
-- TOC entry 5082 (class 0 OID 0)
-- Dependencies: 218
-- Name: TABLE employees; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.employees TO hr_department;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.employees TO hr_specialist;
GRANT SELECT,UPDATE ON TABLE public.employees TO teacher;
GRANT SELECT,UPDATE ON TABLE public.employees TO employee;
GRANT SELECT,DELETE,UPDATE ON TABLE public.employees TO teacher_ivan;


--
-- TOC entry 5084 (class 0 OID 0)
-- Dependencies: 232
-- Name: TABLE school_programs; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.school_programs TO hr_specialist;
GRANT SELECT ON TABLE public.school_programs TO teacher;


--
-- TOC entry 5086 (class 0 OID 0)
-- Dependencies: 226
-- Name: TABLE subjects; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.subjects TO hr_specialist;
GRANT SELECT ON TABLE public.subjects TO teacher;
GRANT SELECT ON TABLE public.subjects TO student;
GRANT SELECT ON TABLE public.subjects TO parent;
GRANT SELECT ON TABLE public.subjects TO employee;
GRANT SELECT ON TABLE public.subjects TO external_service;


--
-- TOC entry 5087 (class 0 OID 0)
-- Dependencies: 235
-- Name: TABLE api_teachers_for_scheduling; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.api_teachers_for_scheduling TO external_service;


--
-- TOC entry 5089 (class 0 OID 0)
-- Dependencies: 220
-- Name: TABLE audit_log; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.audit_log TO hr_specialist;
GRANT SELECT,INSERT ON TABLE public.audit_log TO teacher_ivan;


--
-- TOC entry 5091 (class 0 OID 0)
-- Dependencies: 219
-- Name: SEQUENCE audit_log_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.audit_log_id_seq TO hr_specialist;
GRANT USAGE ON SEQUENCE public.audit_log_id_seq TO teacher_ivan;


--
-- TOC entry 5093 (class 0 OID 0)
-- Dependencies: 230
-- Name: TABLE education; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.education TO hr_specialist;
GRANT SELECT ON TABLE public.education TO teacher;
GRANT SELECT ON TABLE public.education TO employee;


--
-- TOC entry 5095 (class 0 OID 0)
-- Dependencies: 229
-- Name: SEQUENCE education_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.education_id_seq TO hr_specialist;


--
-- TOC entry 5098 (class 0 OID 0)
-- Dependencies: 222
-- Name: TABLE education_types; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.education_types TO hr_specialist;
GRANT SELECT ON TABLE public.education_types TO teacher;


--
-- TOC entry 5100 (class 0 OID 0)
-- Dependencies: 221
-- Name: SEQUENCE education_types_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.education_types_id_seq TO hr_specialist;


--
-- TOC entry 5102 (class 0 OID 0)
-- Dependencies: 217
-- Name: SEQUENCE employees_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.employees_id_seq TO hr_department;
GRANT SELECT,USAGE ON SEQUENCE public.employees_id_seq TO hr_specialist;
GRANT USAGE ON SEQUENCE public.employees_id_seq TO teacher_ivan;


--
-- TOC entry 5103 (class 0 OID 0)
-- Dependencies: 233
-- Name: TABLE hr_employee_dashboard; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.hr_employee_dashboard TO hr_specialist;


--
-- TOC entry 5104 (class 0 OID 0)
-- Dependencies: 237
-- Name: TABLE public_teacher_profiles; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.public_teacher_profiles TO student;
GRANT SELECT ON TABLE public.public_teacher_profiles TO parent;
GRANT SELECT ON TABLE public.public_teacher_profiles TO external_service;


--
-- TOC entry 5106 (class 0 OID 0)
-- Dependencies: 224
-- Name: TABLE qualifications; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.qualifications TO hr_specialist;


--
-- TOC entry 5108 (class 0 OID 0)
-- Dependencies: 223
-- Name: SEQUENCE qualifications_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.qualifications_id_seq TO hr_specialist;


--
-- TOC entry 5110 (class 0 OID 0)
-- Dependencies: 225
-- Name: SEQUENCE subjects_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.subjects_id_seq TO hr_specialist;


--
-- TOC entry 5112 (class 0 OID 0)
-- Dependencies: 238
-- Name: TABLE teacher_personal_dashboard; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.teacher_personal_dashboard TO teacher_ivan;


--
-- TOC entry 5113 (class 0 OID 0)
-- Dependencies: 236
-- Name: TABLE teacher_search_by_subject; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.teacher_search_by_subject TO student;
GRANT SELECT ON TABLE public.teacher_search_by_subject TO parent;


--
-- TOC entry 5115 (class 0 OID 0)
-- Dependencies: 231
-- Name: SEQUENCE teacher_subjects_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.teacher_subjects_id_seq TO hr_specialist;


-- Completed on 2026-01-22 18:27:34

--
-- PostgreSQL database dump complete
--

