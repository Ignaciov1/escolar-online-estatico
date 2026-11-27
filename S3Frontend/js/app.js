// CleanMarket Fintech SpA - Frontend S3 Static Website (EKS + Serverless)
const API_URL = (window.APP_CONFIG && window.APP_CONFIG.API_URL) || "https://<API_ID>.execute-api.us-east-1.amazonaws.com/prod";

let USER_ID = 'cli-hogar-01';

document.addEventListener('DOMContentLoaded', () => {
    const sel = document.getElementById('cliente-select');
    if (sel) USER_ID = sel.value;
    cargarProductos();
    verCarrito();
});

function cambiarCliente() {
    const sel = document.getElementById('cliente-select');
    if (sel) USER_ID = sel.value;
    verCarrito();
}

async function cargarProductos() {
    try {
        const response = await fetch(API_URL + '/api/products');
        if (!response.ok) throw new Error('Error al cargar catalogo');
        const productos = await response.json();
        renderizarTabla(productos);
    } catch (error) {
        mostrarMensaje('Error al cargar productos: ' + error.message, 'error');
    }
}

function renderizarTabla(productos) {
    const tbody = document.getElementById('productos-body');
    tbody.innerHTML = '';
    if (!Array.isArray(productos) || productos.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7">No hay productos registrados</td></tr>';
        return;
    }
    productos.forEach(p => {
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${p.id}</td><td><strong>${p.nombre}</strong></td><td>${p.descripcion || '-'}</td><td>$${Number(p.precio).toLocaleString('es-CL')}</td><td>${p.stock}</td><td>${p.categoria || '-'}</td><td><button class="btn-carrito" onclick="agregarCarrito('${p.id}','${escapar(p.nombre)}',${p.precio})">+ Carrito</button> <button class="btn-editar" onclick="editarProducto(${p.id},'${escapar(p.nombre)}','${escapar(p.descripcion || '')}',${p.precio},${p.stock},'${escapar(p.categoria || '')}')">Editar</button> <button class="btn-eliminar" onclick="eliminarProducto(${p.id})">Eliminar</button></td>`;
        tbody.appendChild(tr);
    });
}

async function guardarProducto(event) {
    event.preventDefault();
    const id = document.getElementById('producto-id').value;
    const datos = {
        nombre: document.getElementById('nombre').value,
        descripcion: document.getElementById('descripcion').value,
        precio: parseFloat(document.getElementById('precio').value),
        stock: parseInt(document.getElementById('stock').value, 10),
        categoria: document.getElementById('categoria').value
    };
    try {
        const url = id ? `${API_URL}/api/products/${id}` : `${API_URL}/api/products`;
        const method = id ? 'PUT' : 'POST';
        const response = await fetch(url, {
            method,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(datos)
        });
        if (!response.ok) {
            const err = await response.json();
            throw new Error(err.error || 'Error al guardar producto');
        }
        mostrarMensaje(id ? 'Producto actualizado correctamente' : 'Producto creado en catalogo', 'exito');
        limpiarFormulario();
        cargarProductos();
    } catch (error) {
        mostrarMensaje('Error: ' + error.message, 'error');
    }
}

async function eliminarProducto(id) {
    if (!confirm('Â¿Eliminar este producto del catalogo?')) return;
    try {
        const response = await fetch(API_URL + '/api/products/' + id, { method: 'DELETE' });
        if (!response.ok) throw new Error('Error al eliminar producto');
        mostrarMensaje('Producto eliminado correctamente', 'exito');
        cargarProductos();
    } catch (error) {
        mostrarMensaje('Error: ' + error.message, 'error');
    }
}

// --- CARRITO (Lambda Cart -> DynamoDB TTL) ---
async function agregarCarrito(productId, nombre, precio) {
    try {
        const response = await fetch(API_URL + '/api/cart', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ userId: USER_ID, productId, nombre, precio, cantidad: 1 })
        });
        if (!response.ok) throw new Error('No se pudo agregar al carrito');
        mostrarMensaje(`"${nombre}" agregado al carrito (${USER_ID})`, 'exito');
        verCarrito();
    } catch (error) {
        mostrarMensaje('Error carrito: ' + error.message, 'error');
    }
}

async function verCarrito() {
    try {
        const response = await fetch(API_URL + '/api/cart?userId=' + encodeURIComponent(USER_ID));
        const data = await response.json();
        const div = document.getElementById('carrito-contenido');
        if (!data.items || data.items.length === 0) {
            div.innerHTML = '<p class="empty-state">Carrito vacio. Selecciona productos del catalogo para iniciar una orden.</p>';
            return;
        }
        let html = '<ul>';
        data.items.forEach(item => {
            html += `<li><span><strong>${item.nombre}</strong> &times; ${item.cantidad} &mdash; $${(item.precio * item.cantidad).toLocaleString('es-CL')}</span> <button class="btn-eliminar" onclick="quitarCarrito('${item.productId}')">Quitar</button></li>`;
        });
        html += `</ul><p class="cart-total"><strong>Total a pagar: $${Number(data.total).toLocaleString('es-CL')} CLP</strong></p>`;
        html += `<button class="btn-orden" onclick="crearOrden()">Confirmar Pedido</button>`;
        div.innerHTML = html;
    } catch (error) {
        mostrarMensaje('Error al consultar carrito: ' + error.message, 'error');
    }
}

async function quitarCarrito(productId) {
    try {
        await fetch(`${API_URL}/api/cart/${productId}?userId=${encodeURIComponent(USER_ID)}`, { method: 'DELETE' });
        verCarrito();
    } catch (error) {
        mostrarMensaje('Error: ' + error.message, 'error');
    }
}

// --- ORDENES (Lambda Create-Order -> SQS -> Lambda Process-Order -> RDS MySQL) ---
async function crearOrden() {
    try {
        const response = await fetch(API_URL + '/api/orders', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ userId: USER_ID })
        });
        const data = await response.json();
        if (!response.ok) throw new Error(data.error || 'Error al procesar orden');
        const texto = `${data.message || 'Su pedido fue procesado'} | Orden: ${data.orderId} | Total: $${Number(data.total).toLocaleString('es-CL')} CLP`;
        mostrarMensaje(texto, 'exito');
        setTimeout(() => {
            verCarrito();
            cargarProductos();
        }, 3500);
    } catch (error) {
        mostrarMensaje('Error orden: ' + error.message, 'error');
    }
}

function editarProducto(id, nombre, descripcion, precio, stock, categoria) {
    document.getElementById('producto-id').value = id;
    document.getElementById('nombre').value = nombre;
    document.getElementById('descripcion').value = descripcion;
    document.getElementById('precio').value = precio;
    document.getElementById('stock').value = stock;
    document.getElementById('categoria').value = categoria;
    document.getElementById('form-titulo').textContent = 'Editar Producto (ID: ' + id + ')';
    document.getElementById('btn-guardar').textContent = 'Actualizar Producto';
}

function cancelarEdicion() { limpiarFormulario(); }

function limpiarFormulario() {
    document.getElementById('producto-form').reset();
    document.getElementById('producto-id').value = '';
    document.getElementById('form-titulo').textContent = 'Nuevo Producto de Limpieza';
    document.getElementById('btn-guardar').textContent = 'Guardar Producto';
}

function mostrarMensaje(texto, tipo) {
    const msg = document.getElementById('mensaje');
    msg.textContent = texto;
    msg.className = tipo === 'exito' ? 'mensaje-exito' : 'mensaje-error';
    setTimeout(() => { msg.textContent = ''; msg.className = ''; }, 6000);
}

function escapar(str) {
    return String(str).replace(/'/g, "\\'").replace(/"/g, '\\"');
}