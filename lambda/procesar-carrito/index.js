const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, UpdateCommand, QueryCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

const TABLE_NAME = process.env.TABLE_NAME || 'carrito-cleanmarket';

exports.handler = async (event) => {
    const method = event.httpMethod || event.requestContext?.http?.method;

    try {
        if (method === 'POST') {
            const body = JSON.parse(event.body);
            const { userId, productId, nombre, precio, cantidad, reemplazar } = body;
            const cantNum = Number(cantidad);

            if (!userId || !productId || !nombre || !precio || !Number.isFinite(cantNum) || cantNum < 1) {
                return response(400, { error: 'Campos obligatorios: userId, productId, nombre, precio, cantidad (>= 1)' });
            }

            const expiresAt = Math.floor(Date.now() / 1000) + 86400; // TTL 24 horas
            const updateExpr = reemplazar
                ? 'SET nombre = :n, precio = :p, cantidad = :c, addedAt = :a, expiresAt = :e'
                : 'SET nombre = :n, precio = :p, cantidad = if_not_exists(cantidad, :zero) + :c, addedAt = :a, expiresAt = :e';

            const exprValues = {
                ':n': nombre,
                ':p': Number(precio),
                ':c': cantNum,
                ':a': new Date().toISOString(),
                ':e': expiresAt
            };
            if (!reemplazar) {
                exprValues[':zero'] = 0;
            }

            const updated = await docClient.send(new UpdateCommand({
                TableName: TABLE_NAME,
                Key: { userId, productId: String(productId) },
                UpdateExpression: updateExpr,
                ExpressionAttributeValues: exprValues,
                ReturnValues: 'ALL_NEW'
            }));

            return response(201, {
                message: reemplazar ? 'Cantidad actualizada en el carrito' : 'Producto agregado al carrito',
                userId,
                productId: String(productId),
                cantidad: updated.Attributes?.cantidad ?? cantNum
            });
        }

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
        console.error('Error en procesar-carrito:', error);
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