-- ============================================
-- EscolarOnline - Base de Datos Extendida (EA3)
-- Actividad 3.3 - Arquitectura Cloud ARY1102
-- ============================================
-- Ejecutar en RDS MySQL
-- Agrega tabla ordenes sobre el schema existente de EA2

USE escolar_online;

-- Tabla de ordenes (nueva en EA3)
CREATE TABLE IF NOT EXISTS ordenes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(100) NOT NULL,
    total DECIMAL(10,2) NOT NULL,
    estado ENUM('pendiente', 'procesado', 'enviado', 'entregado') DEFAULT 'pendiente',
    items JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Verificar que tabla productos existe (de EA2)
-- Si no existe, crearla con datos de prueba
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

-- Insertar productos solo si la tabla esta vacia
INSERT INTO productos (nombre, descripcion, precio, stock, categoria)
SELECT * FROM (
    SELECT 'Cuaderno universitario 100 hojas' as nombre, 'Cuaderno matematicas cuadro grande, tapa dura' as descripcion, 2990.00 as precio, 150 as stock, 'Cuadernos' as categoria
) AS tmp
WHERE NOT EXISTS (SELECT 1 FROM productos LIMIT 1);

-- Si la tabla estaba vacia, insertar el resto
INSERT IGNORE INTO productos (id, nombre, descripcion, precio, stock, categoria) VALUES
(2, 'Mochila escolar reforzada', 'Mochila con compartimentos, resistente al agua', 24990.00, 45, 'Mochilas'),
(3, 'Set 12 lapices de colores', 'Lapices profesionales, mina suave, 12 unidades', 4990.00, 200, 'Lapices'),
(4, 'Calculadora cientifica', 'Calculadora 240 funciones, pantalla LCD', 12990.00, 60, 'Tecnologia'),
(5, 'Estuche escolar doble cierre', 'Estuche amplio con doble compartimento', 6990.00, 80, 'Estuches');

-- 2026 - Disenador asignatura: Ignacio A. Pastenet M.
