-- =============================================================================
-- Oracle XStream CDC - Step 5: Load minimal sample data
-- Run as: sqlplus ordermgmt/<password>@//<host>:1521/XSTRPDB...
-- =============================================================================

-- Run as: sqlplus ordermgmt/<password>@//<rac-scan-ip>:1521/XSTRPDB.<your-vcn>.oraclevcn.com

-- Regions
INSERT INTO regions (region_id, region_name) VALUES (1, 'Europe');
INSERT INTO regions (region_id, region_name) VALUES (2, 'Americas');
INSERT INTO regions (region_id, region_name) VALUES (3, 'Asia');
INSERT INTO regions (region_id, region_name) VALUES (4, 'Middle East and Africa');
COMMIT;

-- Countries
INSERT INTO countries VALUES ('US', 'United States', 2);
INSERT INTO countries VALUES ('UK', 'United Kingdom', 1);
INSERT INTO countries VALUES ('IN', 'India', 3);
COMMIT;

-- Product categories
INSERT INTO product_categories (category_id, category_name) VALUES (1, 'CPU');
INSERT INTO product_categories (category_id, category_name) VALUES (2, 'Video Card');
INSERT INTO product_categories (category_id, category_name) VALUES (3, 'Mother Board');
COMMIT;

-- Customers
INSERT INTO customers (customer_id, name, address, credit_limit) VALUES (1, 'Customer One', 'Address 1', 1000);
INSERT INTO customers (customer_id, name, address, credit_limit) VALUES (2, 'Customer Two', 'Address 2', 2000);
INSERT INTO customers (customer_id, name, address, credit_limit) VALUES (3, 'Customer Three', 'Address 3', 3000);
COMMIT;

-- Employees
INSERT INTO employees (employee_id, first_name, last_name, email, phone, hire_date, job_title)
VALUES (1, 'John', 'Doe', 'john@example.com', '555-0100', SYSDATE, 'Sales Rep');
INSERT INTO employees (employee_id, first_name, last_name, email, phone, hire_date, job_title)
VALUES (2, 'Jane', 'Smith', 'jane@example.com', '555-0101', SYSDATE, 'Manager');
COMMIT;

-- Products
INSERT INTO products (product_id, product_name, category_id, list_price) VALUES (1, 'Product A', 1, 99.99);
INSERT INTO products (product_id, product_name, category_id, list_price) VALUES (2, 'Product B', 2, 199.99);
COMMIT;

-- Orders
INSERT INTO orders (order_id, customer_id, status, salesman_id, order_date)
VALUES (1, 1, 'Pending', 1, SYSDATE);
INSERT INTO orders (order_id, customer_id, status, salesman_id, order_date)
VALUES (2, 2, 'Shipped', 1, SYSDATE-1);
COMMIT;
