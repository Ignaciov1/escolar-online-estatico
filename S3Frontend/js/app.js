// EscolarOnline - Frontend S3 con Carrito + Ordenes - ACT3.3
// Configuracion: cambiar API_URL con la URL de API Gateway despues de crear
const API_URL = (window.APP_CONFIG && window.APP_CONFIG.API_URL) || "https://<API_ID>.execute-api.us-east-1.amazonaws.com/prod";

document.addEventListener('DOMContentLoaded', cargarProductos);

async function cargarProductos() {
    try {
        const response = await fetch(API_URL + '/api/products');
        if (!response.ok) throw new Error('Error al cargar');
        const productos = await response.json();
        renderizarTabla(productos);
        mostrarMensaje('Productos cargados', 'exito');
    } catch (error) { mostrarMensaje('Error: ' + error.message, 'error'); }
}

function renderizarTabla(productos) {
    const tbody = document.getElementById('productos-body');
    tbody.innerHTML = '';
    if (productos.length === 0) { tbody.innerHTML = '<tr><td colspan="7">No hay productos</td></tr>'; return; }
    productos.forEach(p => {
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${p.id}</td><td>${p.nombre}</td><td>${p.descripcion || '-'}</td><td>$${Number(p.precio).toLocaleString('es-CL')}</td><td>${p.stock}</td><td>${p.categoria || '-'}</td><td><button class="btn-carrito" onclick="agregarCarrito('${p.id}','${escapar(p.nombre)}',${p.precio})">+ Carrito</button> <button class="btn-editar" onclick="editarProducto(${p.id},'${escapar(p.nombre)}','${escapar(p.descripcion||'')}',${p.precio},${p.stock},'${escapar(p.categoria||'')}')">Editar</button> <button class="btn-eliminar" onclick="eliminarProducto(${p.id})">Eliminar</button></td>`;
        tbody.appendChild(tr);
    });
}

async function guardarProducto(event) {
    event.preventDefault();
    const id = document.getElementById('producto-id').value;
    const datos = { nombre: document.getElementById('nombre').value, descripcion: document.getElementById('descripcion').value, precio: parseFloat(document.getElementById('precio').value), stock: parseInt(document.getElementById('stock').value), categoria: document.getElementById('categoria').value };
    try {
        let response;
        if (id) { response = await fetch(API_URL + '/api/products/' + id, { method: 'PUT', headers: {'Content-Type':'application/json'}, body: JSON.stringify(datos) }); }
        else { response = await fetch(API_URL + '/api/products', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(datos) }); }
        if (!response.ok) { const err = await response.json(); throw new Error(err.error); }
        mostrarMensaje(id ? 'Producto modificado' : 'Producto creado', 'exito');
        limpiarFormulario(); cargarProductos();
    } catch (error) { mostrarMensaje('Error: ' + error.message, 'error'); }
}

async function eliminarProducto(id) {
    if (!confirm('Eliminar este producto?')) return;
    try {
        const response = await fetch(API_URL + '/api/products/' + id, { method: 'DELETE' });
        if (!response.ok) throw new Error('Error al eliminar');
        mostrarMensaje('Producto eliminado', 'exito'); cargarProductos();
    } catch (error) { mostrarMensaje('Error: ' + error.message, 'error'); }
}

// --- CARRITO ---
const USER_ID = 'user-' + Math.random().toString(36).substr(2, 6);

async function agregarCarrito(productId, nombre, precio) {
    try {
        const response = await fetch(API_URL + '/api/cart', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({ userId: USER_ID, productId, nombre, precio, cantidad: 1 }) });
        if (!response.ok) throw new Error('Error');
        mostrarMensaje('Agregado al carrito', 'exito');
        verCarrito();
    } catch (error) { mostrarMensaje('Error carrito: ' + error.message, 'error'); }
}

async function verCarrito() {
    try {
        const response = await fetch(API_URL + '/api/cart?userId=' + USER_ID);
        const data = await response.json();
        const div = document.getElementById('carrito-contenido');
        if (data.items.length === 0) { div.innerHTML = '<p>Carrito vacio</p>'; return; }
        let html = '<ul>';
        data.items.forEach(item => { html += `<li>${item.nombre} x${item.cantidad} - $${(item.precio * item.cantidad).toLocaleString('es-CL')} <button class="btn-eliminar" onclick="quitarCarrito('${item.productId}')">X</button></li>`; });
        html += `</ul><p><strong>Total: $${data.total.toLocaleString('es-CL')}</strong></p>`;
        html += `<button class="btn-orden" onclick="crearOrden()">Confirmar Pedido</button>`;
        div.innerHTML = html;
    } catch (error) { mostrarMensaje('Error: ' + error.message, 'error'); }
}

async function quitarCarrito(productId) {
    try {
        await fetch(API_URL + '/api/cart/' + productId + '?userId=' + USER_ID, { method: 'DELETE' });
        verCarrito();
    } catch (error) { mostrarMensaje('Error: ' + error.message, 'error'); }
}

// --- ORDENES ---
async function crearOrden() {
    try {
        const response = await fetch(API_URL + '/api/orders', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({ userId: USER_ID }) });
        const data = await response.json();
        if (!response.ok) throw new Error(data.error);
        mostrarMensaje('Su pedido fue procesado - Orden: ' + data.orderId + ' - Total: $' + data.total.toLocaleString('es-CL'), 'exito');
        verCarrito();
        setTimeout(verCarrito, 3000);
    } catch (error) { mostrarMensaje('Error orden: ' + error.message, 'error'); }
}

function editarProducto(id, nombre, descripcion, precio, stock, categoria) {
    document.getElementById('producto-id').value = id;
    document.getElementById('nombre').value = nombre;
    document.getElementById('descripcion').value = descripcion;
    document.getElementById('precio').value = precio;
    document.getElementById('stock').value = stock;
    document.getElementById('categoria').value = categoria;
    document.getElementById('form-titulo').textContent = 'Editar Producto (ID: ' + id + ')';
    document.getElementById('btn-guardar').textContent = 'Actualizar';
}

function cancelarEdicion() { limpiarFormulario(); }
function limpiarFormulario() { document.getElementById('producto-form').reset(); document.getElementById('producto-id').value = ''; document.getElementById('form-titulo').textContent = 'Nuevo Producto'; document.getElementById('btn-guardar').textContent = 'Guardar'; }
function mostrarMensaje(texto, tipo) { const msg = document.getElementById('mensaje'); msg.textContent = texto; msg.className = tipo === 'exito' ? 'mensaje-exito' : 'mensaje-error'; setTimeout(() => { msg.textContent = ''; msg.className = ''; }, 5000); }
function escapar(str) { return str.replace(/'/g, "\\'").replace(/"/g, '\\"'); }

// 2026 - Disenador asignatura: Ignacio A. Pastenet M.
