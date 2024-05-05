#!/bin/bash

docker compose -f docker-compose.arm64 up -d consul-server
sleep 10
docker compose -f docker-compose.arm64 up -d registrator
sleep 10
docker logs consul-server
echo "-----------------------------------------------------------"
docker logs registrator >> ./logs-registrator.txt 2>&1
cat ./logs-registrator.txt
echo "-----------------------------------------------------------"
awk '/Syncing services on/ { found=1; print "EXPRESSÃO ENCONTRADA!"; exit } END { if (!found) { print "ERRO, EXPRESSÃO NÃO ENCONTRADA!"; exit 1 } }' ./logs-registrator.txt