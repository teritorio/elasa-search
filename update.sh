#!/usr/bin/bash

set -e

source .env

rm -f data/*.sjson && \
docker compose --profile '*' run --rm t2addok ruby update.rb "${DATASOURCE_API_URL}" && \
echo "flush..." && \
docker compose exec -T redis redis-cli --raw FLUSHALL && \
echo "addok..." && \
docker compose exec -T addok bash -c "cat /data/*.sjson | addok batch && addok ngrams" && \
echo "save..." && \
docker compose exec -T redis redis-cli --raw BGSAVE && \
echo "done"
