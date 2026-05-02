-- Independent work 2: Дәрігерлердің жұмыс кестесі мен қабылдау жазбасы
DROP SCHEMA IF EXISTS clinic_schedule CASCADE;
CREATE SCHEMA clinic_schedule;
SET search_path TO clinic_schedule;

CREATE TABLE specializations (
    specialization_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE doctors (
    doctor_id SERIAL PRIMARY KEY,
    specialization_id INT NOT NULL REFERENCES specializations(specialization_id),
    full_name VARCHAR(150) NOT NULL,
    phone VARCHAR(30) NOT NULL,
    email VARCHAR(120) UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE patients (
    patient_id SERIAL PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    birth_date DATE NOT NULL,
    phone VARCHAR(30) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE rooms (
    room_id SERIAL PRIMARY KEY,
    room_number VARCHAR(20) NOT NULL UNIQUE,
    floor INT CHECK (floor >= 1)
);

CREATE TABLE schedule_slots (
    slot_id SERIAL PRIMARY KEY,
    doctor_id INT NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    room_id INT NOT NULL REFERENCES rooms(room_id),
    work_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    status VARCHAR(20) DEFAULT 'free' CHECK (status IN ('free','booked','closed')),
    CHECK (end_time > start_time),
    UNIQUE (doctor_id, work_date, start_time),
    UNIQUE (room_id, work_date, start_time)
);

CREATE TABLE appointments (
    appointment_id SERIAL PRIMARY KEY,
    slot_id INT NOT NULL UNIQUE REFERENCES schedule_slots(slot_id),
    patient_id INT NOT NULL REFERENCES patients(patient_id),
    doctor_id INT NOT NULL REFERENCES doctors(doctor_id),
    status VARCHAR(20) DEFAULT 'planned' CHECK (status IN ('planned','completed','cancelled')),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE services (
    service_id SERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL UNIQUE,
    price NUMERIC(10,2) NOT NULL CHECK (price >= 0)
);

CREATE TABLE appointment_services (
    appointment_id INT REFERENCES appointments(appointment_id) ON DELETE CASCADE,
    service_id INT REFERENCES services(service_id),
    quantity INT DEFAULT 1 CHECK (quantity > 0),
    PRIMARY KEY (appointment_id, service_id)
);

CREATE TABLE payments (
    payment_id SERIAL PRIMARY KEY,
    appointment_id INT NOT NULL REFERENCES appointments(appointment_id),
    amount NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
    payment_method VARCHAR(30) CHECK (payment_method IN ('cash','card','kaspi')),
    paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE audit_logs (
    log_id SERIAL PRIMARY KEY,
    table_name VARCHAR(100),
    action_type VARCHAR(20),
    record_id INT,
    old_data JSONB,
    new_data JSONB,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE system_logs (
    log_id SERIAL PRIMARY KEY,
    event_type VARCHAR(100),
    object_name TEXT,
    event_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO specializations(name) VALUES
('Терапевт'), ('Кардиолог'), ('Стоматолог'), ('Педиатр');

INSERT INTO doctors(specialization_id, full_name, phone, email) VALUES
(1,'Айдаров Нұрлан Серікұлы','87010000001','n.aidarov@clinic.kz'),
(2,'Сәрсенова Әлия Ерланқызы','87010000002','a.sarsenova@clinic.kz'),
(3,'Ким Денис Викторович','87010000003','d.kim@clinic.kz');

INSERT INTO patients(full_name, birth_date, phone) VALUES
('Туменова Галия Аянқызы','2005-05-10','87075550000'),
('Омаров Еркебұлан Ержанұлы','2000-02-15','87075550001'),
('Садыкова Айша Мұратқызы','2010-09-21','87075550002');

INSERT INTO rooms(room_number, floor) VALUES ('101',1),('205',2),('307',3);

INSERT INTO schedule_slots(doctor_id, room_id, work_date, start_time, end_time) VALUES
(1,1,'2026-04-27','09:00','09:30'),
(1,1,'2026-04-27','09:30','10:00'),
(2,2,'2026-04-27','10:00','10:30'),
(3,3,'2026-04-28','11:00','11:30');

INSERT INTO services(name, price) VALUES
('Алғашқы консультация',7000),('Қайта қабылдау',5000),('ЭКГ',4000),('Стоматологиялық тексеріс',8000);

CREATE OR REPLACE PROCEDURE add_patient(p_full_name VARCHAR, p_birth_date DATE, p_phone VARCHAR)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO patients(full_name, birth_date, phone) VALUES (p_full_name, p_birth_date, p_phone);
END; $$;

CREATE OR REPLACE PROCEDURE add_schedule_slot(p_doctor_id INT, p_room_id INT, p_work_date DATE, p_start_time TIME, p_end_time TIME)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO schedule_slots(doctor_id, room_id, work_date, start_time, end_time)
    VALUES (p_doctor_id, p_room_id, p_work_date, p_start_time, p_end_time);
END; $$;

CREATE OR REPLACE PROCEDURE make_appointment(p_slot_id INT, p_patient_id INT, p_notes TEXT)
LANGUAGE plpgsql AS $$
DECLARE v_doctor_id INT; v_status VARCHAR(20);
BEGIN
    SELECT doctor_id, status INTO v_doctor_id, v_status FROM schedule_slots WHERE slot_id = p_slot_id;
    IF v_doctor_id IS NULL THEN RAISE EXCEPTION 'Мұндай кесте уақыты табылмады'; END IF;
    IF v_status <> 'free' THEN RAISE EXCEPTION 'Бұл уақыт бос емес'; END IF;
    INSERT INTO appointments(slot_id, patient_id, doctor_id, notes) VALUES (p_slot_id, p_patient_id, v_doctor_id, p_notes);
    UPDATE schedule_slots SET status = 'booked' WHERE slot_id = p_slot_id;
END; $$;

CREATE OR REPLACE PROCEDURE add_payment(p_appointment_id INT, p_payment_method VARCHAR)
LANGUAGE plpgsql AS $$
DECLARE v_amount NUMERIC(10,2);
BEGIN
    SELECT COALESCE(SUM(s.price * aps.quantity), 0) INTO v_amount
    FROM appointment_services aps JOIN services s ON s.service_id = aps.service_id
    WHERE aps.appointment_id = p_appointment_id;
    INSERT INTO payments(appointment_id, amount, payment_method) VALUES (p_appointment_id, v_amount, p_payment_method);
    UPDATE appointments SET status = 'completed' WHERE appointment_id = p_appointment_id;
END; $$;

CREATE OR REPLACE FUNCTION get_appointment_total(p_appointment_id INT) RETURNS NUMERIC(10,2)
LANGUAGE plpgsql AS $$
DECLARE v_total NUMERIC(10,2);
BEGIN
    SELECT COALESCE(SUM(s.price * aps.quantity), 0) INTO v_total
    FROM appointment_services aps JOIN services s ON s.service_id = aps.service_id
    WHERE aps.appointment_id = p_appointment_id;
    RETURN v_total;
END; $$;

CREATE OR REPLACE FUNCTION get_patient_visit_count(p_patient_id INT) RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count FROM appointments WHERE patient_id = p_patient_id;
    RETURN v_count;
END; $$;

CREATE OR REPLACE FUNCTION get_doctor_appointments_count(p_doctor_id INT) RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count FROM appointments WHERE doctor_id = p_doctor_id AND status <> 'cancelled';
    RETURN v_count;
END; $$;

CREATE OR REPLACE FUNCTION get_free_slots(p_doctor_id INT, p_date DATE)
RETURNS TABLE(slot_id INT, work_date DATE, start_time TIME, end_time TIME, room_number VARCHAR)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT ss.slot_id, ss.work_date, ss.start_time, ss.end_time, r.room_number
    FROM schedule_slots ss JOIN rooms r ON r.room_id = ss.room_id
    WHERE ss.doctor_id = p_doctor_id AND ss.work_date = p_date AND ss.status = 'free'
    ORDER BY ss.start_time;
END; $$;

CREATE OR REPLACE FUNCTION trg_prevent_double_booking_fn() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM appointments WHERE slot_id = NEW.slot_id AND appointment_id <> COALESCE(NEW.appointment_id, -1) AND status <> 'cancelled') THEN
        RAISE EXCEPTION 'Бұл уақытқа қабылдау жазбасы бұрыннан бар';
    END IF;
    RETURN NEW;
END; $$;

CREATE TRIGGER trg_prevent_double_booking BEFORE INSERT OR UPDATE ON appointments
FOR EACH ROW EXECUTE FUNCTION trg_prevent_double_booking_fn();

CREATE OR REPLACE FUNCTION trg_update_timestamp_fn() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END; $$;

CREATE TRIGGER trg_update_appointment_time BEFORE UPDATE ON appointments
FOR EACH ROW EXECUTE FUNCTION trg_update_timestamp_fn();

CREATE OR REPLACE FUNCTION trg_log_appointments_fn() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_logs(table_name, action_type, record_id, new_data) VALUES (TG_TABLE_NAME, TG_OP, NEW.appointment_id, to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_logs(table_name, action_type, record_id, old_data, new_data) VALUES (TG_TABLE_NAME, TG_OP, NEW.appointment_id, to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSE
        INSERT INTO audit_logs(table_name, action_type, record_id, old_data) VALUES (TG_TABLE_NAME, TG_OP, OLD.appointment_id, to_jsonb(OLD));
        RETURN OLD;
    END IF;
END; $$;

CREATE TRIGGER trg_log_appointments AFTER INSERT OR UPDATE OR DELETE ON appointments
FOR EACH ROW EXECUTE FUNCTION trg_log_appointments_fn();

CREATE OR REPLACE FUNCTION trg_statement_log_fn() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO audit_logs(table_name, action_type, record_id, new_data)
    VALUES (TG_TABLE_NAME, TG_OP || '_STATEMENT', NULL, jsonb_build_object('message','Оператор деңгейіндегі триггер орындалды'));
    RETURN NULL;
END; $$;

CREATE TRIGGER trg_statement_appointments AFTER INSERT OR UPDATE OR DELETE ON appointments
FOR EACH STATEMENT EXECUTE FUNCTION trg_statement_log_fn();

CREATE VIEW v_free_slots AS
SELECT ss.slot_id, d.full_name AS doctor_name, r.room_number, ss.work_date, ss.start_time, ss.end_time
FROM schedule_slots ss JOIN doctors d ON d.doctor_id = ss.doctor_id JOIN rooms r ON r.room_id = ss.room_id
WHERE ss.status = 'free';

CREATE OR REPLACE FUNCTION trg_instead_insert_free_slot_fn() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE v_doctor_id INT; v_room_id INT;
BEGIN
    SELECT doctor_id INTO v_doctor_id FROM doctors WHERE full_name = NEW.doctor_name;
    SELECT room_id INTO v_room_id FROM rooms WHERE room_number = NEW.room_number;
    INSERT INTO schedule_slots(doctor_id, room_id, work_date, start_time, end_time)
    VALUES (v_doctor_id, v_room_id, NEW.work_date, NEW.start_time, NEW.end_time);
    RETURN NEW;
END; $$;

CREATE TRIGGER trg_instead_insert_free_slot INSTEAD OF INSERT ON v_free_slots
FOR EACH ROW EXECUTE FUNCTION trg_instead_insert_free_slot_fn();

CREATE OR REPLACE FUNCTION ddl_audit_fn() RETURNS event_trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO clinic_schedule.system_logs(event_type, object_name)
    SELECT TG_TAG, object_identity FROM pg_event_trigger_ddl_commands();
END; $$;

CREATE EVENT TRIGGER trg_system_ddl_audit ON ddl_command_end
EXECUTE FUNCTION clinic_schedule.ddl_audit_fn();

-- Тестілеу
CALL add_patient('Нұрбекова Дана Қайратқызы','1999-01-12','87075550003');
CALL add_schedule_slot(2,2,'2026-04-29','12:00','12:30');
CALL make_appointment(1,1,'Алғашқы қабылдау');
INSERT INTO appointment_services(appointment_id, service_id, quantity) VALUES (1,1,1),(1,3,1);
SELECT get_appointment_total(1) AS total_sum;
CALL add_payment(1,'kaspi');
SELECT get_patient_visit_count(1) AS patient_visits;
SELECT * FROM get_free_slots(1,'2026-04-27');
SELECT * FROM audit_logs ORDER BY log_id DESC;

BEGIN;
CALL make_appointment(2,2,'Кардиологқа жазылу');
SAVEPOINT after_appointment;
-- Қате service_id, кейін тек осы жерден бастап қайтарылады
-- INSERT INTO appointment_services(appointment_id, service_id, quantity) VALUES (2,999,1);
ROLLBACK TO SAVEPOINT after_appointment;
INSERT INTO appointment_services(appointment_id, service_id, quantity) VALUES (2,2,1);
COMMIT;

BEGIN;
CALL make_appointment(3,3,'Тест қабылдау');
ROLLBACK;
