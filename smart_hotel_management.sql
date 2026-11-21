-- Smart Hotel Management System
-- SQL target: MySQL 8.0+
-- Advanced features demonstrated: constraints, indexes, views, stored procedure,
-- transaction-safe reservation logic, triggers, and full-text search.

CREATE DATABASE IF NOT EXISTS smart_hotel_management;
USE smart_hotel_management;

CREATE TABLE IF NOT EXISTS Guest (
    guest_id INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    phone VARCHAR(15),
    address VARCHAR(255),
    date_of_birth DATE,
    id_proof VARCHAR(100),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_guest_email CHECK (email LIKE '%@%.%')
);

CREATE TABLE IF NOT EXISTS Room_Type (
    room_type_id INT PRIMARY KEY AUTO_INCREMENT,
    type_name VARCHAR(50) NOT NULL UNIQUE,
    description VARCHAR(255),
    price_per_night DECIMAL(10,2) NOT NULL,
    capacity INT NOT NULL,
    amenities VARCHAR(500),
    CONSTRAINT chk_room_type_price CHECK (price_per_night > 0),
    CONSTRAINT chk_room_type_capacity CHECK (capacity > 0)
);

CREATE TABLE IF NOT EXISTS Room (
    room_id INT PRIMARY KEY AUTO_INCREMENT,
    room_number INT NOT NULL UNIQUE,
    room_type_id INT NOT NULL,
    floor INT NOT NULL,
    status ENUM('Available', 'Occupied', 'Maintenance', 'Unavailable')
        NOT NULL DEFAULT 'Available',
    FOREIGN KEY (room_type_id) REFERENCES Room_Type(room_type_id),
    CONSTRAINT chk_room_floor CHECK (floor >= 0)
);

CREATE TABLE IF NOT EXISTS Reservation (
    reservation_id INT PRIMARY KEY AUTO_INCREMENT,
    guest_id INT NOT NULL,
    room_id INT NOT NULL,
    check_in DATE NOT NULL,
    check_out DATE NOT NULL,
    guests_count INT NOT NULL,
    booking_status ENUM('Pending', 'Confirmed', 'Checked-in', 'Checked-out', 'Cancelled')
        NOT NULL DEFAULT 'Pending',
    total_amount DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_reservation_guest FOREIGN KEY (guest_id)
        REFERENCES Guest(guest_id) ON UPDATE CASCADE,
    FOREIGN KEY (room_id) REFERENCES Room(room_id),
    CONSTRAINT chk_reservation_dates CHECK (check_out > check_in),
    CONSTRAINT chk_reservation_guests CHECK (guests_count > 0),
    CONSTRAINT chk_reservation_amount CHECK (total_amount >= 0)
);

-- Upgrade existing installations so guest ID changes propagate to reservations.
SET @guest_fk_name = (
    SELECT CONSTRAINT_NAME
    FROM information_schema.KEY_COLUMN_USAGE
    WHERE CONSTRAINT_SCHEMA = DATABASE()
      AND TABLE_NAME = 'Reservation'
      AND COLUMN_NAME = 'guest_id'
      AND REFERENCED_TABLE_NAME = 'Guest'
    LIMIT 1
);
SET @guest_fk_update_rule = (
    SELECT UPDATE_RULE
    FROM information_schema.REFERENTIAL_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = DATABASE()
      AND CONSTRAINT_NAME = @guest_fk_name
    LIMIT 1
);
SET @drop_guest_fk_sql = IF(
    @guest_fk_name IS NOT NULL AND @guest_fk_update_rule <> 'CASCADE',
    CONCAT('ALTER TABLE Reservation DROP FOREIGN KEY `',
           REPLACE(@guest_fk_name, '`', '``'), '`'),
    'SELECT 1'
);
PREPARE drop_guest_fk_stmt FROM @drop_guest_fk_sql;
EXECUTE drop_guest_fk_stmt;
DEALLOCATE PREPARE drop_guest_fk_stmt;
SET @add_guest_fk_sql = IF(
    @guest_fk_name IS NULL OR @guest_fk_update_rule <> 'CASCADE',
    'ALTER TABLE Reservation ADD CONSTRAINT fk_reservation_guest FOREIGN KEY (guest_id) REFERENCES Guest(guest_id) ON UPDATE CASCADE',
    'SELECT 1'
);
PREPARE add_guest_fk_stmt FROM @add_guest_fk_sql;
EXECUTE add_guest_fk_stmt;
DEALLOCATE PREPARE add_guest_fk_stmt;

CREATE TABLE IF NOT EXISTS Payment (
    payment_id INT PRIMARY KEY AUTO_INCREMENT,
    reservation_id INT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    payment_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    payment_method ENUM('Cash', 'Card', 'UPI', 'Net Banking') NOT NULL,
    payment_status ENUM('Pending', 'Successful', 'Failed', 'Refunded') NOT NULL DEFAULT 'Pending',
    transaction_id VARCHAR(100) UNIQUE,
    FOREIGN KEY (reservation_id) REFERENCES Reservation(reservation_id),
    CONSTRAINT chk_payment_amount CHECK (amount > 0)
);

CREATE TABLE IF NOT EXISTS Hotel_User (
    user_id INT PRIMARY KEY AUTO_INCREMENT,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('Admin', 'Receptionist', 'Manager') NOT NULL DEFAULT 'Receptionist',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS Reservation_Audit (
    audit_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    reservation_id INT NOT NULL,
    action_name VARCHAR(30) NOT NULL,
    old_status VARCHAR(30),
    new_status VARCHAR(30),
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (reservation_id) REFERENCES Reservation(reservation_id)
);

CREATE INDEX idx_reservation_dates ON Reservation(room_id, check_in, check_out);
CREATE INDEX idx_reservation_guest ON Reservation(guest_id);
CREATE INDEX idx_payment_reservation ON Payment(reservation_id);
CREATE INDEX idx_room_status_type ON Room(status, room_type_id);
CREATE FULLTEXT INDEX idx_room_type_search
    ON Room_Type(type_name, description, amenities);

DROP VIEW IF EXISTS v_active_reservations;
CREATE VIEW v_active_reservations AS
SELECT
    r.reservation_id,
    r.guest_id,
    r.room_id,
    CONCAT(g.first_name, ' ', g.last_name) AS guest_name,
    g.first_name AS guest_first_name,
    g.last_name AS guest_last_name,
    g.email,
    rm.room_number,
    rt.type_name,
    r.check_in,
    r.check_out,
    r.guests_count,
    r.booking_status,
    r.total_amount,
    COALESCE(SUM(CASE WHEN p.payment_status = 'Successful' THEN p.amount ELSE 0 END), 0)
        AS amount_paid,
    r.total_amount - COALESCE(SUM(
        CASE WHEN p.payment_status = 'Successful' THEN p.amount ELSE 0 END
    ), 0) AS balance_due
FROM Reservation r
JOIN Guest g ON g.guest_id = r.guest_id
JOIN Room rm ON rm.room_id = r.room_id
JOIN Room_Type rt ON rt.room_type_id = rm.room_type_id
LEFT JOIN Payment p ON p.reservation_id = r.reservation_id
WHERE r.booking_status IN ('Pending', 'Confirmed', 'Checked-in')
GROUP BY r.reservation_id, r.guest_id, r.room_id, g.first_name, g.last_name, g.email, rm.room_number,
         rt.type_name, r.check_in, r.check_out, r.guests_count,
         r.booking_status, r.total_amount;

DROP TRIGGER IF EXISTS trg_reservation_validate;
DROP TRIGGER IF EXISTS trg_reservation_audit;
DROP TRIGGER IF EXISTS trg_guest_validate;
DROP PROCEDURE IF EXISTS sp_create_reservation;
DROP PROCEDURE IF EXISTS sp_update_guest;
DROP PROCEDURE IF EXISTS sp_update_reservation;
DROP PROCEDURE IF EXISTS sp_delete_reservation;

DELIMITER //

CREATE TRIGGER trg_guest_validate
BEFORE INSERT ON Guest
FOR EACH ROW
BEGIN
    IF NEW.date_of_birth IS NOT NULL AND NEW.date_of_birth >= CURRENT_DATE THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Date of birth must be in the past';
    END IF;
END//

CREATE TRIGGER trg_reservation_validate
BEFORE INSERT ON Reservation
FOR EACH ROW
BEGIN
    DECLARE room_capacity INT;
    SELECT rt.capacity INTO room_capacity
    FROM Room rm
    JOIN Room_Type rt ON rt.room_type_id = rm.room_type_id
    WHERE rm.room_id = NEW.room_id;

    IF NEW.check_out <= NEW.check_in THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Check-out must be after check-in';
    END IF;
    IF NEW.guests_count > room_capacity THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Guest count exceeds room capacity';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM Reservation existing
        WHERE existing.room_id = NEW.room_id
          AND existing.booking_status IN ('Pending', 'Confirmed', 'Checked-in')
          AND NEW.check_in < existing.check_out
          AND NEW.check_out > existing.check_in
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Room is already reserved for the selected dates';
    END IF;
END//

CREATE TRIGGER trg_reservation_audit
AFTER UPDATE ON Reservation
FOR EACH ROW
BEGIN
    IF OLD.booking_status <> NEW.booking_status THEN
        INSERT INTO Reservation_Audit
            (reservation_id, action_name, old_status, new_status)
        VALUES
            (NEW.reservation_id, 'STATUS_CHANGE', OLD.booking_status, NEW.booking_status);
    END IF;
END//

CREATE PROCEDURE sp_create_reservation(
    IN p_guest_id INT,
    IN p_room_id INT,
    IN p_check_in DATE,
    IN p_check_out DATE,
    IN p_guests_count INT
)
BEGIN
    DECLARE v_price DECIMAL(10,2);
    DECLARE v_total DECIMAL(10,2);
    DECLARE v_days INT;

    START TRANSACTION;
    SELECT rt.price_per_night INTO v_price
    FROM Room rm
    JOIN Room_Type rt ON rt.room_type_id = rm.room_type_id
    WHERE rm.room_id = p_room_id
    FOR UPDATE;

    IF v_price IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room does not exist';
    END IF;

    SET v_days = DATEDIFF(p_check_out, p_check_in);
    SET v_total = v_days * v_price;

    INSERT INTO Reservation
        (guest_id, room_id, check_in, check_out, guests_count, booking_status, total_amount)
    VALUES
        (p_guest_id, p_room_id, p_check_in, p_check_out, p_guests_count, 'Confirmed', v_total);

    COMMIT;
END//

CREATE PROCEDURE sp_update_guest(
    IN p_original_guest_id INT,
    IN p_guest_id INT,
    IN p_first_name VARCHAR(50),
    IN p_last_name VARCHAR(50)
)
BEGIN
    DECLARE v_temporary_email VARCHAR(100);
    DECLARE v_email VARCHAR(100);
    DECLARE v_phone VARCHAR(15);
    DECLARE v_address VARCHAR(255);
    DECLARE v_date_of_birth DATE;
    DECLARE v_id_proof VARCHAR(100);
    DECLARE v_created_at TIMESTAMP;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF p_guest_id IS NULL OR p_guest_id < 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Guest ID must be positive';
    END IF;
    IF p_first_name IS NULL OR TRIM(p_first_name) = ''
       OR CHAR_LENGTH(p_first_name) > 50
       OR p_last_name IS NULL OR TRIM(p_last_name) = ''
       OR CHAR_LENGTH(p_last_name) > 50 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Guest first and last names are required';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Guest WHERE guest_id = p_original_guest_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Guest does not exist';
    END IF;
    IF p_guest_id <> p_original_guest_id
       AND EXISTS (SELECT 1 FROM Guest WHERE guest_id = p_guest_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Guest ID is already in use';
    END IF;

    IF p_guest_id = p_original_guest_id THEN
        UPDATE Guest
        SET first_name = TRIM(p_first_name),
            last_name = TRIM(p_last_name)
        WHERE guest_id = p_original_guest_id;
    ELSE
        SELECT email, phone, address, date_of_birth, id_proof, created_at
        INTO v_email, v_phone, v_address, v_date_of_birth, v_id_proof, v_created_at
        FROM Guest
        WHERE guest_id = p_original_guest_id;

        SET v_temporary_email = CONCAT(
    'guest-',
    p_guest_id,
    '-',
    REPLACE(UUID(), '-', ''),
    '@temporary.local'
);

        INSERT INTO Guest
            (guest_id, first_name, last_name, email, phone, address, date_of_birth, id_proof, created_at)
        VALUES
            (p_guest_id, TRIM(p_first_name), TRIM(p_last_name),
             v_temporary_email, v_phone, v_address, v_date_of_birth, v_id_proof, v_created_at);

        UPDATE Reservation
        SET guest_id = p_guest_id
        WHERE guest_id = p_original_guest_id;

        DELETE FROM Guest WHERE guest_id = p_original_guest_id;

        UPDATE Guest
        SET email = v_email
        WHERE guest_id = p_guest_id;
    END IF;

    COMMIT;
END//

CREATE PROCEDURE sp_update_reservation(
    IN p_reservation_id INT,
    IN p_guest_id INT,
    IN p_room_id INT,
    IN p_check_in DATE,
    IN p_check_out DATE,
    IN p_guests_count INT
)
BEGIN
    DECLARE v_price DECIMAL(10,2);
    DECLARE v_capacity INT;
    DECLARE v_exists INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    SELECT COUNT(*) INTO v_exists
    FROM Reservation
    WHERE reservation_id = p_reservation_id
      AND booking_status IN ('Pending', 'Confirmed');

    IF v_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reservation does not exist or cannot be edited';
    END IF;
    IF p_check_out <= p_check_in THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Check-out must be after check-in';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Guest WHERE guest_id = p_guest_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Guest does not exist';
    END IF;

    SELECT rt.price_per_night, rt.capacity INTO v_price, v_capacity
    FROM Room rm
    JOIN Room_Type rt ON rt.room_type_id = rm.room_type_id
    WHERE rm.room_id = p_room_id
    FOR UPDATE;

    IF v_price IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room does not exist';
    END IF;
    IF p_guests_count < 1 OR p_guests_count > v_capacity THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Guest count exceeds room capacity';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM Reservation existing
        WHERE existing.room_id = p_room_id
          AND existing.reservation_id <> p_reservation_id
          AND existing.booking_status IN ('Pending', 'Confirmed', 'Checked-in')
          AND p_check_in < existing.check_out
          AND p_check_out > existing.check_in
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Room is already reserved for the selected dates';
    END IF;

    UPDATE Reservation
    SET guest_id = p_guest_id,
        room_id = p_room_id,
        check_in = p_check_in,
        check_out = p_check_out,
        guests_count = p_guests_count,
        total_amount = DATEDIFF(p_check_out, p_check_in) * v_price
    WHERE reservation_id = p_reservation_id;
    COMMIT;
END//

CREATE PROCEDURE sp_delete_reservation(IN p_reservation_id INT)
BEGIN
    DECLARE v_exists INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    SELECT COUNT(*) INTO v_exists
    FROM Reservation
    WHERE reservation_id = p_reservation_id;

    IF v_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reservation does not exist';
    END IF;
    IF EXISTS (SELECT 1 FROM Payment WHERE reservation_id = p_reservation_id)
       OR EXISTS (SELECT 1 FROM Reservation_Audit WHERE reservation_id = p_reservation_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reservation has payment or audit history and cannot be deleted';
    END IF;

    DELETE FROM Reservation WHERE reservation_id = p_reservation_id;
    COMMIT;
END//

DELIMITER ;

-- Representative DML seed data.
INSERT INTO Room_Type (type_name, description, price_per_night, capacity, amenities)
VALUES
    ('Deluxe King', 'King bed with city view', 4500.00, 2, 'Wi-Fi, TV, Breakfast, Mini-bar'),
    ('Family Suite', 'Two-room suite for families', 7500.00, 4, 'Wi-Fi, TV, Breakfast, Kitchenette'),
    ('Executive Twin', 'Twin beds for business travellers', 5200.00, 2, 'Wi-Fi, TV, Work desk')
ON DUPLICATE KEY UPDATE description = VALUES(description);

INSERT INTO Guest (first_name, last_name, email, phone, address, date_of_birth, id_proof)
VALUES
    ('Aarav', 'Sharma', 'aarav.sharma@example.com', '9876543210', 'Bengaluru', '1998-04-12', 'AADHAAR-1001'),
    ('Meera', 'Nair', 'meera.nair@example.com', '9876543211', 'Kochi', '1995-09-20', 'PASSPORT-2001')
ON DUPLICATE KEY UPDATE phone = VALUES(phone);

INSERT INTO Room (room_number, room_type_id, floor, status)
SELECT 101, room_type_id, 1, 'Available' FROM Room_Type WHERE type_name = 'Deluxe King'
ON DUPLICATE KEY UPDATE status = VALUES(status);

INSERT INTO Room (room_number, room_type_id, floor, status)
SELECT 201, room_type_id, 2, 'Available' FROM Room_Type WHERE type_name = 'Family Suite'
ON DUPLICATE KEY UPDATE status = VALUES(status);

-- Example operations for demonstration.
SET @demo_guest_id = (
    SELECT guest_id FROM Guest WHERE email = 'aarav.sharma@example.com'
);
SET @demo_room_id = (
    SELECT room_id FROM Room WHERE room_number = 101
);
CALL sp_create_reservation(
    @demo_guest_id, @demo_room_id, '2026-11-10', '2026-11-13', 2
);

INSERT INTO Payment
    (reservation_id, amount, payment_method, payment_status, transaction_id)
SELECT reservation_id, total_amount, 'UPI', 'Successful', 'TXN-DEMO-0001'
FROM Reservation
WHERE guest_id = (SELECT guest_id FROM Guest WHERE email = 'aarav.sharma@example.com')
ORDER BY reservation_id DESC
LIMIT 1;

UPDATE Reservation
SET booking_status = 'Checked-in'
WHERE reservation_id = (
    SELECT reservation_id FROM (
        SELECT reservation_id
        FROM Reservation
        WHERE guest_id = (SELECT guest_id FROM Guest WHERE email = 'aarav.sharma@example.com')
        ORDER BY reservation_id DESC LIMIT 1
    ) latest
);

-- SELECT examples: JOIN, aggregate, HAVING, ORDER BY, subquery, and full-text search.
SELECT * FROM v_active_reservations ORDER BY check_in;

SELECT rt.type_name, COUNT(r.room_id) AS room_count,
       AVG(rt.price_per_night) AS average_rate
FROM Room_Type rt
LEFT JOIN Room r ON r.room_type_id = rt.room_type_id
GROUP BY rt.room_type_id, rt.type_name
HAVING COUNT(r.room_id) > 0
ORDER BY average_rate DESC;

SELECT g.email, g.first_name, g.last_name
FROM Guest g
WHERE g.guest_id IN (
    SELECT r.guest_id FROM Reservation r
    WHERE r.total_amount > (SELECT AVG(total_amount) FROM Reservation)
);

SELECT room_type_id, type_name,
       MATCH(type_name, description, amenities)
       AGAINST ('+Wi-Fi +Breakfast' IN BOOLEAN MODE) AS relevance
FROM Room_Type
WHERE MATCH(type_name, description, amenities)
      AGAINST ('+Wi-Fi +Breakfast' IN BOOLEAN MODE);

-- Recursive CTE: report reserved rooms for each of the next 30 days.
WITH RECURSIVE next_30_days AS (
    SELECT CURRENT_DATE() AS stay_date
    UNION ALL
    SELECT DATE_ADD(stay_date, INTERVAL 1 DAY)
    FROM next_30_days
    WHERE stay_date < DATE_ADD(CURRENT_DATE(), INTERVAL 29 DAY)
)
SELECT calendar.stay_date,
       COUNT(DISTINCT r.room_id) AS reserved_rooms,
       COUNT(DISTINCT r.reservation_id) AS active_reservations
FROM next_30_days calendar
LEFT JOIN Reservation r
    ON calendar.stay_date >= r.check_in
   AND calendar.stay_date < r.check_out
   AND r.booking_status IN ('Pending', 'Confirmed', 'Checked-in')
GROUP BY calendar.stay_date
ORDER BY calendar.stay_date;

-- DELETE example (restricted to a clearly identified test record).
-- DELETE FROM Payment WHERE transaction_id = 'TXN-TEST-DELETE';
