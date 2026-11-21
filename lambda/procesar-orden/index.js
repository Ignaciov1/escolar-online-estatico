const mysql = require('mysql2/promise');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand, BatchWriteCommand } = require('@aws-sdk/lib-dynamodb');

const dynamoClient = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(dynamoClient);

const TABLE_NAME = process.env.TABLE_NAME || 'carrito-escolaronline';

const dbConfig = {
    host: process.env.DB_HOST,
    user: process.env.DB_USER || 'alumno',
    password: process.env.DB_PASS || 'alumno123',
    database: process.env.DB_NAME || 'escolar_online',
    port: parseInt(process.env.DB_PORT) || 3306
};

// Handler: trigger SQS (recibe batch de mensajes)
exports.handler = async (event) => {
    console.log(`Procesando ${event.Records.length} mensaje(s) de SQS`);

    for (const record of event.Records) {
        try {
            const order = JSON.parse(record.body);
            console.log(`Procesando orden: ${order.orderId} para usuario: ${order.userId}`);

            // 1. Guardar orden en MySQL
            const connection = await mysql.createConnection(dbConfig);

            await connection.execute(
                'INSERT INTO ordenes (user_id, total, estado, items, processed_at) VALUES (?, ?, ?, ?, NOW())',
                [order.userId, order.total, 'procesado', JSON.stringify(order.items)]
            );

            await connection.end();
            console.log(`Orden ${order.orderId} guardada en MySQL`);

            // 2. Limpiar carrito del usuario en DynamoDB
            const cartItems = await docClient.send(new QueryCommand({
                TableName: TABLE_NAME,
                KeyConditionExpression: 'userId = :uid',
                ExpressionAttributeValues: { ':uid': order.userId }
            }));

            if (cartItems.Items && cartItems.Items.length > 0) {
                // Eliminar items del carrito en batches de 25
                const deleteRequests = cartItems.Items.map(item => ({
                    DeleteRequest: {
                        Key: { userId: item.userId, productId: item.productId }
                    }
                }));

                // DynamoDB BatchWrite acepta max 25 items
                for (let i = 0; i < deleteRequests.length; i += 25) {
                    const batch = deleteRequests.slice(i, i + 25);
                    await docClient.send(new BatchWriteCommand({
                        RequestItems: { [TABLE_NAME]: batch }
                    }));
                }
                console.log(`Carrito limpiado para usuario: ${order.userId}`);
            }

            console.log(`Orden ${order.orderId} procesada exitosamente`);

        } catch (error) {
            console.error(`Error procesando mensaje: ${error.message}`);
            // Si falla, SQS reintentara (el mensaje vuelve a la cola)
            throw error;
        }
    }

    return { statusCode: 200, body: 'Ordenes procesadas' };
};

// 2026 - Disenador asignatura: Ignacio A. Pastenet M.
