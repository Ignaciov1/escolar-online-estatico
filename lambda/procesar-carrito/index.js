const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand, QueryCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

const TABLE_NAME = process.env.TABLE_NAME || 'carrito-escolaronline';

exports.handler = async (event) => {
    const method = event.httpMethod || event.requestContext?.http?.method;
    const path = event.path || event.rawPath;

    try {
        // POST /api/cart - Agregar item al carrito
        if (method === 'POST') {
            const body = JSON.parse(event.body);
            const { userId, productId, nombre, precio, cantidad } = body;

            if (!userId || !productId || !nombre || !precio || !cantidad) {
                return response(400, { error: 'Campos obligatorios: userId, productId, nombre, precio, cantidad' });
            }

            const expiresAt = Math.floor(Date.now() / 1000) + 86400; // 24 horas

            await docClient.send(new PutCommand({
                TableName: TABLE_NAME,
                Item: {
                    userId,
                    productId: String(productId),
                    nombre,
                    precio: Number(precio),
                    cantidad: Number(cantidad),
                    addedAt: new Date().toISOString(),
                    expiresAt
                }
            }));

            return response(201, { message: 'Producto agregado al carrito', userId, productId });
        }

        // GET /api/cart?userId=xxx - Consultar carrito
        if (method === 'GET') {
            const userId = event.queryStringParameters?.userId;

            if (!userId) {
                return response(400, { error: 'Parametro requerido: userId' });
            }

            const result = await docClient.send(new QueryCommand({
                TableName: TABLE_NAME,
                KeyConditionExpression: 'userId = :uid',
                ExpressionAttributeValues: { ':uid': userId }
            }));

            const items = result.Items || [];
            const total = items.reduce((sum, item) => sum + (item.precio * item.cantidad), 0);

            return response(200, { userId, items, total, cantidadItems: items.length });
        }

        // DELETE /api/cart/{productId}?userId=xxx - Quitar item del carrito
        if (method === 'DELETE') {
            const userId = event.queryStringParameters?.userId;
            const productId = event.pathParameters?.productId;

            if (!userId || !productId) {
                return response(400, { error: 'Parametros requeridos: userId (query), productId (path)' });
            }

            await docClient.send(new DeleteCommand({
                TableName: TABLE_NAME,
                Key: { userId, productId: String(productId) }
            }));

            return response(200, { message: 'Producto eliminado del carrito', userId, productId });
        }

        return response(405, { error: 'Metodo no permitido' });

    } catch (error) {
        console.error('Error:', error);
        return response(500, { error: 'Error interno', detalle: error.message });
    }
};

function response(statusCode, body) {
    return {
        statusCode,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type'
        },
        body: JSON.stringify(body)
    };
}

// 2026 - Disenador asignatura: Ignacio A. Pastenet M.
