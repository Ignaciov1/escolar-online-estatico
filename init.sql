-- ============================================
-- CleanMarket Fintech SpA - Base de Datos RDS MySQL
-- Evaluacion Final Transversal - Arquitectura Cloud ARY1102
-- ============================================

CREATE DATABASE IF NOT EXISTS cleanmarket;
USE cleanmarket;

-- Tabla de clientes (segmentos Hogar, Oficina e Industria)
CREATE TABLE IF NOT EXISTS clientes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(100) NOT NULL UNIQUE,
    nombre VARCHAR(200) NOT NULL,
    email VARCHAR(200) NOT NULL,
    segmento ENUM('Hogar', 'Oficina', 'Industria') NOT NULL DEFAULT 'Hogar',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de productos de higiene y limpieza
CREATE TABLE IF NOT EXISTS productos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    descripcion TEXT,
    precio DECIMAL(10,2) NOT NULL,
    stock INT NOT NULL DEFAULT 0,
    categoria VARCHAR(100),
    imagen_url VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Tabla de ordenes procesadas de forma asincrona desde SQS
CREATE TABLE IF NOT EXISTS ordenes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(100) NOT NULL,
    total DECIMAL(10,2) NOT NULL,
    estado ENUM('pendiente', 'procesado', 'enviado', 'entregado') DEFAULT 'pendiente',
    items JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_ordenes_user_id (user_id)
);

-- Carga inicial idempotente de clientes
INSERT IGNORE INTO clientes (id, user_id, nombre, email, segmento) VALUES
(1, 'cli-hogar-01', 'Camila Rojas', 'camila.rojas@hogar.cl', 'Hogar'),
(2, 'cli-oficina-01', 'Servicios Corporativos Centro Ltda.', 'compras@oficinacentro.cl', 'Oficina'),
(3, 'cli-industria-01', 'Planta Alimentaria Sur S.A.', 'abastecimiento@plantasur.cl', 'Industria');

-- Carga inicial idempotente de catalogo de higiene y limpieza
INSERT IGNORE INTO productos (id, nombre, descripcion, precio, stock, categoria) VALUES
(1, 'Detergente Liquido Concentrado 5L', 'Detergente enzimatico biodegradable de alto rendimiento para ropa y textiles', 12990.00, 120, 'Hogar'),
(2, 'Desinfectante Amonio Cuaternario 5L', 'Desinfectante bactericida y virucida grado profesional para pisos y superficies', 15490.00, 85, 'Industria'),
(3, 'Cloro Gel Concentrado 2L', 'Limpiador blanqueador en gel antisalpicaduras para banos y cocinas', 3490.00, 200, 'Hogar'),
(4, 'Jabon Liquido Antibacterial 5L', 'Bidon recarga de jabon neutro con glicerina para dispensadores corporativos', 9990.00, 95, 'Oficina'),
(5, 'Papel Higienico Institucional Pack x12', 'Rollos jumbo doble hoja de 300 metros para oficinas y alto flujo', 18990.00, 70, 'Oficina'),
(6, 'Alcohol Gel Higienizante 70% 1L', 'Gel sanitizante de manos sin enjuague con valvula dosificadora', 4990.00, 150, 'Industria');