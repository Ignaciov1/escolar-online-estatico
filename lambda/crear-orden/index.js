const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const { SQSClient, SendMessageCommand } = require('@aws-sdk/client-sqs');

const dynamoClient = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(dynamoClient);
const sqsClient = new SQSClient({});

const TABLE_NAME = process.env.TABLE_NAME || 'carrito-cleanmarket';
const QUEUE_URL = process.env.QUEUE_URL;

exports.handler = async (event) => {
    try {
        const body = JSON.parse(event.body);
        const { userId } = body;

        if (!userId) {
            return response(400, { error: 'Campo obligatorio: userId' });
        }

        const cartResult = await docClient.send(new QueryCommand({
            TableName: TABLE_NAME,
            KeyConditionExpression: 'userId = :uid',
            ExpressionAttributeValues: { ':uid': userId }
        }));

        const items = cartResult.Items || [];

        if (items.length === 0) {
            return response(400, { error: 'El carrito esta vacio', userId });
        }

        const total = items.reduce((sum, item) => sum + (item.precio * item.cantidad), 0);
        const orderId = `CM-${Date.now()}-${Math.random().toString(36).substr(2, 6).toUpperCase()}`;

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

        await sqsClient.send(new SendMessageCommand({
            QueueUrl: QUEUE_URL,
            MessageBody: JSON.stringify(orderMessage),
            MessageAttributes: {
                'userId': { DataType: 'String', StringValue: userId },
                'orderId': { DataType: 'String', StringValue: orderId }
            }
        }));

        return response(200, {
            message: 'Su pedido fue procesado',
            orderId,
            total,
            cantidadItems: items.length,
            estado: 'procesado'
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