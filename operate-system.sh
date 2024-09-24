#!/bin/bash

ROOT_PATH=`pwd`
pmaster_container="master"
declare -a pstandby_container=("standby")  # Corrected array declaration
docker_compose_file="docker-compose.yml"
volume_path="./v"

# Start container master
function do_start_master {
    echo "-- Run Postgres Master Container --"
    do_start_one "$pmaster_container"
    echo "-- Done --"
}

# Start containers standby
function do_start_standby {
    echo "-- Run Postgres Standby Containers --"
    for i in "${pstandby_container[@]}"; do
        do_start_one "$i"
    done
    echo "-- Done --"
}

function do_start_one {
    docker-compose -f "$docker_compose_file" up -d "$1"
    if [ $? != 0 ]; then
        echo "Build failed - Run $1 container failed"
        exit -1
    fi
}

# Check health of containers
function do_check_health {
    # Check health of master container
    echo "-- Check Health of Master Container --"
    if ! docker-compose -f "$docker_compose_file" exec "$pmaster_container" pg_isready; then
        echo "Master container is not ready."
    fi

    echo "-- Check Health of Standby Containers --"
    for i in "${pstandby_container[@]}"; do
        if ! docker-compose -f "$docker_compose_file" exec "$i" pg_isready; then
            echo "$i container is not ready."
        fi
    done
    echo "-- Done --"
}

# Create backup data standby and copy data from master
function do_backup_data {
    cd "$ROOT_PATH" || exit 1  # Exit if the cd fails
    echo "-- Backup Data --"
    for i in "${pstandby_container[@]}"; do
        cd "$volume_path" || exit 1  # Exit if the cd fails
        if [ -d "${i}_data_bk" ]; then
            echo "Removing existing backup directory ${i}_data_bk"
            rm -rf "${i}_data_bk"  # Remove existing backup directory
        fi
        mv "${i}_data" "${i}_data_bk"
        cp -r "${pmaster_container}_data" "${i}_data"
    done
    echo "-- Done --"
}

# Copy config files (pg_hba.conf, postgresql.conf) to master and standby volumes
function do_copy_config {
    cd "$ROOT_PATH" || exit 1  # Exit if the cd fails
    echo "-- Copy Config Files --"
    cp config/master/pg_hba.conf v/master_data/pg_hba.conf

    for i in "${pstandby_container[@]}"; do
        cp config/standby/postgresql.conf v/"$i"_data/postgresql.conf
        touch v/"$i"_data/standby.signal
    done
    echo "-- Done --"
}


docker-compose -f "$docker_compose_file" down
do_start_master
do_start_standby
sleep 15
do_check_health
# Build replication
docker-compose -f "$docker_compose_file" down
do_backup_data
sleep 5
do_copy_config
sleep 5
# Restart containers
docker-compose -f "$docker_compose_file" up -d
