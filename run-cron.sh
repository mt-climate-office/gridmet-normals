#!/bin/bash
# Script to run gridmet-normals via Docker
# This script is designed to be called from cron

# Change to the directory containing the docker-compose.yml
cd "$(dirname "$0")"

# Run the Docker container
docker-compose up --build

# Optional: Clean up stopped containers
docker-compose down

# Log completion
echo "gridmet-normals run completed at $(date)" >> /var/log/gridmet-normals.log
