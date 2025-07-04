#!/bin/bash

ENV_FILE="./.envs/php-api-service.env"

if [ -f "$ENV_FILE" ]; then
    echo "🔄 Resetting DB_USE_REPLICA to false"
    sed -i 's/^DB_USE_REPLICA=.*/DB_USE_REPLICA=false/' "$ENV_FILE"
    echo "✅ DB_USE_REPLICA set to false"
else
    echo "⚠️  .env file not found!"
fi