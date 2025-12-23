/* Creation of database */
CREATE DATABASE FoodOrder;
USE FoodOrder;

/*Create relation and schema*/
CREATE TABLE roles (
  role_id INT PRIMARY KEY AUTO_INCREMENT,
  role_name VARCHAR(30) NOT NULL UNIQUE
);

CREATE TABLE users (
  user_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(200) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  phone VARCHAR(50),
  loyalty_points INT DEFAULT 0,
  role_id INT NOT NULL,
  CONSTRAINT fk_user_role FOREIGN KEY (role_id) REFERENCES roles(role_id)
);

CREATE TABLE addresses (
  address_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  street VARCHAR(255),
  city VARCHAR(120),
  pincode VARCHAR(20),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_address_user FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE restaurants (
  restaurant_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  contact VARCHAR(120),
  cuisine_type VARCHAR(120),
  owner_user_id BIGINT,
  license VARCHAR(120),
  rating DECIMAL(3,2) DEFAULT 0,
  CONSTRAINT fk_rest_owner FOREIGN KEY (owner_user_id) REFERENCES users(user_id)
);

CREATE TABLE restaurant_admins (
  admin_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  restaurant_id BIGINT NOT NULL,
  user_id BIGINT NOT NULL,
  access_level VARCHAR(100),
  CONSTRAINT fk_admin_rest FOREIGN KEY (restaurant_id) REFERENCES restaurants(restaurant_id),
  CONSTRAINT fk_admin_user FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE menu_items (
  menu_item_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  restaurant_id BIGINT NOT NULL,
  name VARCHAR(255) NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  availability INT DEFAULT 1,
  CONSTRAINT fk_menu_rest FOREIGN KEY (restaurant_id) REFERENCES restaurants(restaurant_id)
);

CREATE TABLE orders (
  order_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  customer_id BIGINT NOT NULL,
  restaurant_id BIGINT NOT NULL,
  address_id BIGINT NOT NULL,
  order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  status ENUM('PENDING','CONFIRMED','PREPARING','OUT_FOR_DELIVERY','DELIVERED','CANCELLED') DEFAULT 'PENDING',
  amount DECIMAL(10,2) DEFAULT 0,
  payment_status ENUM('UNPAID','PAID') DEFAULT 'UNPAID',
  CONSTRAINT fk_order_customer FOREIGN KEY (customer_id) REFERENCES users(user_id),
  CONSTRAINT fk_order_rest FOREIGN KEY (restaurant_id) REFERENCES restaurants(restaurant_id),
  CONSTRAINT fk_order_address FOREIGN KEY (address_id) REFERENCES addresses(address_id)
);

CREATE TABLE order_items (
  order_item_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  order_id BIGINT NOT NULL,
  menu_item_id BIGINT NOT NULL,
  quantity INT NOT NULL,
  unit_price DECIMAL(10,2) NOT NULL,
  line_total DECIMAL(12,2) NOT NULL,
  CONSTRAINT fk_oi_order FOREIGN KEY (order_id) REFERENCES orders(order_id),
  CONSTRAINT fk_oi_menu FOREIGN KEY (menu_item_id) REFERENCES menu_items(menu_item_id)
);

CREATE TABLE payments (
  payment_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  order_id BIGINT NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  payment_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  method VARCHAR(100),
  status ENUM('INITIATED','SUCCESS','FAILED','REFUNDED') DEFAULT 'INITIATED',
  CONSTRAINT fk_payment_order FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE TABLE reviews (
  review_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  customer_id BIGINT NOT NULL,
  restaurant_id BIGINT NOT NULL,
  rating INT CHECK (rating BETWEEN 1 AND 5),
  comment VARCHAR(500),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_review_customer FOREIGN KEY (customer_id) REFERENCES users(user_id),
  CONSTRAINT fk_review_rest FOREIGN KEY (restaurant_id) REFERENCES restaurants(restaurant_id)
);

CREATE TABLE delivery_agents (
  delivery_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(200),
  contact VARCHAR(100)
);

CREATE TABLE delivery (
  delivery_record_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  order_id BIGINT NOT NULL,
  delivery_id_ref BIGINT NOT NULL,
  status ENUM('ASSIGNED','PICKED_UP','DELIVERED','FAILED') DEFAULT 'ASSIGNED',
  assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  delivered_at TIMESTAMP NULL,
  CONSTRAINT fk_delivery_order FOREIGN KEY (order_id) REFERENCES orders(order_id),
  CONSTRAINT fk_delivery_agent FOREIGN KEY (delivery_id_ref) REFERENCES delivery_agents(delivery_id)
);

/*Create Triggers*/
DELIMITER //
CREATE TRIGGER trg_calc_line_total BEFORE INSERT ON order_items
FOR EACH ROW
BEGIN
  SET NEW.line_total = NEW.quantity * NEW.unit_price;
END//
DELIMITER ;

DELIMITER //
CREATE TRIGGER trg_update_order_amount AFTER INSERT ON order_items
FOR EACH ROW
BEGIN
  UPDATE orders
  SET amount = (SELECT SUM(line_total) FROM order_items WHERE order_id = NEW.order_id)
  WHERE order_id = NEW.order_id;
END//
DELIMITER ;

DELIMITER //
CREATE TRIGGER trg_reduce_availability AFTER INSERT ON order_items
FOR EACH ROW
BEGIN
  UPDATE menu_items
  SET availability = availability - NEW.quantity
  WHERE menu_item_id = NEW.menu_item_id AND availability > 0;
END//
DELIMITER ;

/*Create procedures*/
DELIMITER //
CREATE PROCEDURE place_order(IN p_customer BIGINT, IN p_rest BIGINT, IN p_addr BIGINT, OUT p_order BIGINT)
BEGIN
  INSERT INTO orders(customer_id, restaurant_id, address_id)
  VALUES(p_customer, p_rest, p_addr);
  SET p_order = LAST_INSERT_ID();
END//
DELIMITER ;

DELIMITER //
CREATE PROCEDURE process_payment(IN p_order BIGINT, IN p_amt DECIMAL(10,2))
BEGIN
  INSERT INTO payments(order_id, amount, status) VALUES(p_order, p_amt, 'SUCCESS');
  UPDATE orders SET payment_status = 'PAID' WHERE order_id = p_order;
END//
DELIMITER ;

DELIMITER //
CREATE PROCEDURE update_order_status(IN p_order BIGINT, IN p_status VARCHAR(50))
BEGIN
  UPDATE orders SET status = p_status WHERE order_id = p_order;
END//
DELIMITER ;

DELIMITER //
CREATE PROCEDURE sp_restock_menu_items()
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE mi_id BIGINT;
    DECLARE cur CURSOR FOR
        SELECT menu_item_id FROM menu_items WHERE availability < 10;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    OPEN cur;

    restock_loop: LOOP
        FETCH cur INTO mi_id;
        IF done THEN
            LEAVE restock_loop;
        END IF;
        UPDATE menu_items
        SET availability = availability + 50
        WHERE menu_item_id = mi_id;
    END LOOP;

    CLOSE cur;
END//
DELIMITER ;

/*Create functions*/
DELIMITER //
CREATE FUNCTION fn_calculate_loyalty_points(p_user_id BIGINT) RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE total_points INT;
    SELECT FLOOR(SUM(amount) / 10) INTO total_points
    FROM orders
    WHERE customer_id = p_user_id AND payment_status = 'PAID';
    RETURN IFNULL(total_points, 0);
END//
DELIMITER ;

DELIMITER //
CREATE FUNCTION fn_avg_restaurant_rating(p_rest BIGINT) RETURNS DECIMAL(3,2)
DETERMINISTIC
BEGIN
    DECLARE avg_rating DECIMAL(3,2);
    SELECT AVG(rating) INTO avg_rating
    FROM reviews
    WHERE restaurant_id = p_rest;
    RETURN IFNULL(avg_rating, 0);
END//
DELIMITER ;

DELIMITER //
CREATE FUNCTION fn_daily_revenue(p_rest BIGINT, p_date DATE) RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
    DECLARE revenue DECIMAL(10,2);
    SELECT IFNULL(SUM(p.amount),0) INTO revenue
    FROM payments p
    JOIN orders o ON p.order_id = o.order_id
    WHERE o.restaurant_id = p_rest
      AND DATE(p.payment_date) = p_date
      AND p.status = 'SUCCESS';
    RETURN revenue;
END//
DELIMITER ;


/*Insert sample data into the tables*/ 
/* ---------------------------
   Roles
--------------------------- */
INSERT INTO roles (role_name) VALUES
('customer'),
('restaurant_owner'),
('admin');

-- Users
INSERT INTO users (name, email, phone, loyalty_points, role_id)
VALUES
('John Doe', 'john@gmail.com', '9876543210', 0, 1),      -- customer
('Alice Smith', 'alice@yahoo.com', '9123456780', 0, 2),   -- restaurant owner
('Admin User', 'admin@foodsys.com', '9000000000', 0, 3);  -- admin

-- Addresses
INSERT INTO addresses (user_id, street, city, pincode)
VALUES
(1, '221B Baker Street', 'London', 'NW16XE'),
(1, '44 Albert Road', 'London', 'SE12GP'),
(2, '12 Rose Lane', 'London', 'E17HZ');

-- Restaurants
INSERT INTO restaurants (name, contact, cuisine_type, owner_user_id, license, rating)
VALUES
('Italiano House', '020012345', 'Italian', 2, 'LIC-IT-001', 4.5),
('Burger Hub', '020098765', 'Fast Food', 2, 'LIC-BG-002', 4.1);

-- Restaurant admins
INSERT INTO restaurant_admins (restaurant_id, user_id, access_level)
VALUES
(1, 2, 'owner'),
(2, 2, 'owner');

-- Menu items
INSERT INTO menu_items (restaurant_id, name, price, availability)
VALUES
(1, 'Pasta Alfredo', 10.99, 100),
(1, 'Margherita Pizza', 8.49, 50),
(2, 'Cheese Burger', 6.99, 200),
(2, 'French Fries', 3.49, 300);

-- Orders (paid)
INSERT INTO orders (customer_id, restaurant_id, address_id, status, amount, payment_status)
VALUES
(1, 1, 1, 'DELIVERED', 30.47, 'PAID'),  -- John ordered from Italiano House
(1, 2, 2, 'DELIVERED', 20.97, 'PAID');  -- John ordered from Burger Hub

-- Order items (line_total will be auto-calculated by trigger)
INSERT INTO order_items (order_id, menu_item_id, quantity, unit_price)
VALUES
(1, 1, 2, 10.99),  -- 2 x Pasta Alfredo = 21.98
(1, 2, 1, 8.49),   -- 1 x Margherita Pizza = 8.49
(2, 3, 3, 6.99),   -- 3 x Cheese Burger = 20.97
(2, 4, 0, 3.49);   -- 0 x French Fries (optional, won't affect total)

-- Payments
INSERT INTO payments (order_id, amount, payment_date, method, status)
VALUES
(1, 30.47, NOW(), 'CREDIT_CARD', 'SUCCESS'),
(2, 20.97, NOW(), 'CREDIT_CARD', 'SUCCESS');

-- Reviews
INSERT INTO reviews (customer_id, restaurant_id, rating, comment)
VALUES
(1, 1, 5, 'Delicious pasta, quick service!'),
(1, 2, 4, 'Tasty burgers, fries were okay.');

-- Delivery agents & delivery assignment
INSERT INTO delivery_agents (name, contact)
VALUES ('Bob Rider', '0770000001');

INSERT INTO delivery (order_id, delivery_id_ref, status)
VALUES
(1, 1, 'DELIVERED'),
(2, 1, 'DELIVERED');

/* ---------------------------
   Sample queries — application usage
   --------------------------- */

-- 1) View all restaurants
SELECT restaurant_id, name, cuisine_type, rating
FROM restaurants;

-- 2) View menu for restaurant_id = 1
SELECT menu_item_id, name, price, availability
FROM menu_items
WHERE restaurant_id = 1;

-- 3) Customer (user_id = 1) order history (join orders -> restaurants)
SELECT o.order_id, o.status, o.order_date, o.amount, r.name AS restaurant_name
FROM orders o
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
WHERE o.customer_id = 1
ORDER BY o.order_date DESC;

-- 4) Restaurant owner (user_id = 2) — view orders for their restaurants
SELECT o.order_id, o.status, o.order_date, o.amount, u.name AS customer_name
FROM orders o
JOIN users u ON o.customer_id = u.user_id
WHERE o.restaurant_id IN (SELECT restaurant_id FROM restaurants WHERE owner_user_id = 2)
ORDER BY o.order_date DESC;

-- 5) Compute total of order_id = 1 from order_items
SELECT SUM(quantity * unit_price) AS computed_total
FROM order_items
WHERE order_id = 1;

-- 6) Top-selling menu items (quantity summed)
SELECT mi.menu_item_id, mi.name, SUM(oi.quantity) AS total_sold
FROM order_items oi
JOIN menu_items mi ON oi.menu_item_id = mi.menu_item_id
GROUP BY mi.menu_item_id, mi.name
ORDER BY total_sold DESC
LIMIT 10;

-- 7) Daily revenue summary from payments
SELECT DATE(payment_date) AS sale_date, SUM(amount) AS revenue
FROM payments
GROUP BY DATE(payment_date)
ORDER BY sale_date DESC;



/* ---------------------------
   Test triggers
   --------------------------- */

-- A) Insert another order_item into order_id = 1 — triggers should:
INSERT INTO order_items (order_id, menu_item_id, quantity, unit_price)
VALUES (1, 1, 1, 10.99); 

-- B) Verify updated order amount
SELECT order_id, amount, payment_status
FROM orders
WHERE order_id = 1;

-- C) Verify menu availability was reduced for menu_item_id = 1
SELECT menu_item_id, name, availability
FROM menu_items
WHERE menu_item_id = 1;



/* ---------------------------
   Test stored procedures
   --------------------------- */

-- 1) Test place_order(p_customer, p_rest, p_addr, OUT p_order)
SET @new_order_id = 0;
CALL place_order(1, 1, 1, @new_order_id);
SELECT @new_order_id AS created_order_id;

-- 2) Now you can insert order_items for @new_order_id if you want:
INSERT INTO order_items (order_id, menu_item_id, quantity, unit_price)
VALUES (@new_order_id, 3, 2, 6.99); -- 2 x Cheese Burger

-- 3) Recompute/verify the order amount (the trigger should update it automatically)
SELECT order_id, amount FROM orders WHERE order_id = @new_order_id;

-- 4) Test process_payment(p_order, p_amt)
CALL process_payment(@new_order_id, 13.98); -- pay for 2 burgers (6.99 * 2)
SELECT * FROM payments WHERE order_id = @new_order_id;

-- 5) Test update_order_status(p_order, p_status)
CALL update_order_status(@new_order_id, 'CONFIRMED');
SELECT order_id, status FROM orders WHERE order_id = @new_order_id;

-- 6) Auto restock low availablity items (using a cursor)
CALL sp_restock_menu_items();

/* ---------------------------
   Test stored functions
   --------------------------- */

-- 1) Calculate loyalty points for a customer
SELECT name, fn_calculate_loyalty_points(user_id) AS loyalty_points
FROM users;

-- 2) Calculate average rationg for a restaturant
SELECT name, fn_avg_restaurant_rating(restaurant_id) AS avg_rating
FROM restaurants;

-- 3)Calculate daily revenue for a restaurant
SELECT name, fn_daily_revenue(restaurant_id, CURDATE()) AS today_revenue
FROM restaurants;





/* ---------------------------
   Helpful verification queries
   --------------------------- */

-- All orders with totals and number of items
SELECT o.order_id, o.customer_id, o.restaurant_id, o.amount,
       COUNT(oi.order_item_id) AS items_count
FROM orders o
LEFT JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.customer_id, o.restaurant_id, o.amount
ORDER BY o.order_date DESC;

-- Payments for a customer
SELECT p.payment_id, p.order_id, p.amount, p.payment_date, p.method, p.status
FROM payments p
JOIN orders o ON p.order_id = o.order_id
WHERE o.customer_id = 1
ORDER BY p.payment_date DESC;














