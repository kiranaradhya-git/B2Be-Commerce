exports.handler = async (event) => {
    // Example: Fetch product data from DynamoDB
    const response = {
        statusCode: 200,
        headers: {
            "Content-Type": "application/json"
        },
        body: JSON.stringify({ message: "Hello from Product Catalog Lambda!" }),
    };
    return response;
};
