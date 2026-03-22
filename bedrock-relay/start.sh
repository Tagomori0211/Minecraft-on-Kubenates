#!/bin/bash
export DEST_HOST=$(sudo kubectl get pods -n minecraft -l app=mc-bedrock -o jsonpath='{.items[0].status.podIP}')
echo "Resolved Bedrock Pod IP to $DEST_HOST"
exec /usr/bin/node /home/shinari/bedrock-relay/index.js
