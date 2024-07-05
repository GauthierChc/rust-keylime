#!/bin/bash

set -e
cmd="$@"
# Define the host and ports
host="127.0.0.1"
port="8891"

# Function to check if a port is listening
port_is_listening() {
    host=$1
    port=$2
    if curl --connect-timeout 2 "http://$host:$port" 2>&1 | grep -q "Recv failure: Connection reset by peer"; then
        return 0  # Success (registrar is ready)
    else
        return 1  # Failure (registrar not ready)
    fi
}

# Loop through each port and wait until one is listening
for port in $port; do
    while ! port_is_listening $host $port; do
        echo "Waiting for Keylime registrar to be ready on $host:$port..."
        sleep 5
    done
done

echo "Keylime registrar is ready on $host:$port. Exiting."
sleep 5
exec $cmd