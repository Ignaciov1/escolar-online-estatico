const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const { SQSClient, SendMessageCommand } = require('@aws-sdk/client-sqs');

const dynamoClient = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(dynamoClient);
const sqsClient = new SQSClient({});

const TABLE_NAME = process.env.TABLE_NAME || 'carrito-escolaronline';
const QUEUE_URL = process.env.QUEUE_URL;

exports.handler = async (event) => {
    try {
        const body = JSON.parse(event.body);
        const { userId } = body;

        if (!userId) {
            return response(400, { error: 'Campo obligatorio: userId' });
        }

        // 1. Leer carrito del usuario desde DynamoDB
        const cartResult = await docClient.send(new QueryCommand({
            TableName: TABLE_NAME,
            KeyConditionExpression: 'userId = :uid',
            ExpressionAttributeValues: { ':uid': userId }
        }));

        const items = cartResult.Items || [];

        if (items.length === 0) {
            return response(400, { error: 'El carrito esta vacio', userId });
        }

        // 2. Calcular total
        const total = items.reduce((sum, item) => sum + (item.precio * item.cantidad), 0);

        // 3. Crear mensaje de orden
        const orderId = `ORD-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        const orderMessage = {
            orderId,
            userId,
            items: items.map(item => ({
                productId: item.productId,
                nombre: item.nombre,
                precio: item.precio,
                cantidad: item.cantidad
            })),
            total,
            createdAt: new Date().toISOString()
        };

        // 4. Publicar en SQS
        await sqsClient.send(new SendMessageCommand({
            QueueUrl: QUEUE_URL,
            MessageBody: JSON.stringify(orderMessage),
            MessageAttributes: {
                'userId': { DataType: 'String', StringValue: userId },
                'orderId': { DataType: 'String', StringValue: orderId }
            }
        }));

        // 5. Responder al cliente inmediatamente
        return response(200, {
            message: 'Su pedido fue recibido',
            orderId,
            total,
            cantidadItems: items.length,
            estado: 'pendiente'
        });

    } catch (error) {
        console.error('Error al crear orden:', error);
        return response(500, { error: 'Error al crear orden', detalle: error.message });
    }
};

function response(statusCode, body) {
    return {
        statusCode,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type'
        },
        body: JSON.stringify(body)
    };
}

// 2026 - Disenador asignatura: Ignacio A. Pastenet M.
