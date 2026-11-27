const mysql = require('mysql2/promise');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand, BatchWriteCommand } = require('@aws-sdk/lib-dynamodb');

const dynamoClient = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(dynamoClient);

const TABLE_NAME = process.env.TABLE_NAME || 'carrito-cleanmarket';

const dbConfig = {
    host: process.env.DB_HOST,
    user: process.env.DB_USER || 'alumno',
    password: process.env.DB_PASS || 'alumno123',
    database: process.env.DB_NAME || 'cleanmarket',
    port: parseInt(process.env.DB_PORT, 10) || 3306
};

exports.handler = async (event) => {
    console.log(`CleanMarket Process-Order: procesando ${event.Records.length} mensaje(s) de SQS`);

    for (const record of event.Records) {
        let connection;
        try {
            const order = JSON.parse(record.body);
            console.log(`Procesando orden ${order.orderId} para cliente ${order.userId}`);

            connection = await mysql.createConnection(dbConfig);
            await connection.beginTransaction();

            await connection.execute(
                'INSERT INTO ordenes (user_id, total, estado, items, processed_at) VALUES (?, ?, ?, ?, NOW())',
                [order.userId, order.total, 'procesado', JSON.stringify(order.items)]
            );

            if (Array.isArray(order.items)) {
                for (const item of order.items) {
                    const productId = parseInt(item.productId, 10);
                    const cantidad = parseInt(item.cantidad, 10) || 1;
                    if (!Number.isNaN(productId) && cantidad > 0) {
                        await connection.execute(
                            'UPDATE productos SET stock = GREATEST(stock - ?, 0) WHERE id = ?',
                            [cantidad, productId]
                        );
                    }
                }
            }

            await connection.commit();
            console.log(`Orden ${order.orderId} guardada y stock descontado en MySQL`);

            const cartItems = await docClient.send(new QueryCommand({
                TableName: TABLE_NAME,
                KeyConditionExpression: 'userId = :uid',
                ExpressionAttributeValues: { ':uid': order.userId }
            }));

            if (cartItems.Items && cartItems.Items.length > 0) {
                const deleteRequests = cartItems.Items.map(item => ({
                    DeleteRequest: {
                        Key: { userId: item.userId, productId: item.productId }
                    }
                }));

                for (let i = 0; i < deleteRequests.length; i += 25) {
                    const batch = deleteRequests.slice(i, i + 25);
                    await docClient.send(new BatchWriteCommand({
                        RequestItems: { [TABLE_NAME]: batch }
                    }));
                }
                console.log(`Carrito limpiado para cliente: ${order.userId}`);
            }

            console.log(`Orden ${order.orderId} confirmada: Su pedido fue procesado`);
        } catch (error) {
            if (connection) {
                try { await connection.rollback(); } catch (_) {}
            }
            console.error(`Error procesando mensaje SQS: ${error.message}`);
            throw error;
        } finally {
            if (connection) {
                await connection.end();
            }
        }
    }

    return { statusCode: 200, body: 'Su pedido fue procesado' };
};