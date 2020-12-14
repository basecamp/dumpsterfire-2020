exports.handler = async (event) => {
    const response = {
        "status": 302,
        "headers": {
            "location": [ {"value": "https://hey.science/dumpster-fire/"} ]
        },
        "body": "<html></html>",
        "bodyEncoding": "text"
    };
    return response;
};
