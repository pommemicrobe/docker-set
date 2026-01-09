#!/bin/bash
# MySQL healthcheck script - avoids exposing password in process list
mysqladmin ping -h localhost -u root -p"${MYSQL_ROOT_PASSWORD}" --silent
