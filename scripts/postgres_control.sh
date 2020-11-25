#!/bin/bash

#######################################################################################################################################################
#
# This script controls the starting-up/stopping a PostgresSQL server or executing an SQL statement based on the following conditions
#
# 1. The program `docker` can be executed in current environment and can be executed without sudo: the script would use docker to start/stop PostgreSQL 
#     or execute SQL stamtement against the started server.
# 2. The program `pg_ctlcluster` or `pg_ctl` can be executed in current environment and the 'CI' environment variable is 'true': the script would use 
#    'pg_ctlcluster' or `pg_ctl` to start/stop the PostgreSQL server. It is intended to be used by CI docker container only.
# 3. The program 'psql' can be executed in current environment and the environment variables PGHOST, PGPORT, PGPASSWORD, PGUSER are properly
#    defined to access an running PostgreSQL server. 
#
#
# Usage:
#
#   # start the PostgreSQL server in case 1 or 2; in case 3, executing the "Drop TABLE mytable" on the existing PostgreSQL server
#   $ postgres_control.sh start "Drop TABLE mytable"
# 
#   # start the PostgreSQL server in case 1 or 2; in cause 3, do nothing. 
#   $ postgres_control.sh stop
#
#   # execute SQL in a running PostgreSQL server started by this script
#   $ postgres_control.sh exec "SELECT (*) FROM table;"
# 
########################################################################################################################################################

if [ ! -z `which docker 2>/dev/null` ]; then
   ### use docker
   case "$1" in 
   start)
      docker run --rm -p 127.0.0.1:5432:5432 --name test_postgres -e POSTGRES_PASSWORD=password -d postgres
      until docker run --rm --link test_postgres:pg postgres pg_isready -U postgres -h pg; do sleep 1; done
      ;;
   stop)
      docker rm -f test_postgres
      ;;
   exec)
      docker run --rm --link test_postgres:pg -e PGPASSWORD=password postgres psql -U postgres -h pg -q -c "$2"
      ;;
   status)
      echo true 
   esac
elif [ "$CI" = "true" ]; then
   if [ ! -z `which  pg_ctlcluster 2>/dev/null` ]; then
      # Ubuntu variant
      case "$1" in 
      start)
         pg_ctlcluster 13 main start
         su - postgres -c "psql -q -c \"ALTER USER postgres WITH PASSWORD 'password';\""
         ;;
      stop)
         pg_ctlcluster 13 main stop
         ;;
      exec)
         PGPASSWORD=password su - postgres -c "psql -U postgres -q -c \"$2\""
         ;;
      status)
         echo true 
      esac
   else 
      PG_CTL=`which pg_ctl 2>/dev/null`
      if [ -z $PG_CTL ] && [ -f "$PostgreSQL_ROOT/bin/pg_ctl" ]; then
         PG_CTL=$PostgreSQL_ROOT/bin/pg_ctl
      fi

      if [ ! -z "$PG_CTL" ]; then
         OS=`uname`
         if [ "$OS" = "Darwin" ]; then
            ## mac
            case "$1" in 
            start)
               $PG_CTL -D /usr/local/var/postgres start
               psql postgres -q -c "CREATE ROLE postgres WITH LOGIN PASSWORD 'password'"
               ;;
            stop)
               $PG_CTL -D /usr/local/var/postgres stop
               ;;
            exec)
               PGPASSWORD=password psql postgres -q -c "$2"
               ;;
            status)
               echo true 
            esac
         else  
            ## CentOS, amazon Linux
            case "$1" in 
            start)
               su - postgres -c "$PG_CTL start"
               su - postgres -c "psql -q -c \"ALTER USER postgres WITH PASSWORD 'password';\""
               ;;
            stop)
               su - postgres -c "$PG_CTL stop"
               ;;
            exec)
               PGPASSWORD=password psql -U postgres -q -c "$2"
               ;;
            status)
               echo true 
            esac
         fi
      fi
   fi
elif [ ! -z "$PGHOST" ] && [ -n `which psql` ]; then
   ## user supplied postgres server
   case "$1" in 
   start) 
      if [ ! -z "$2" ]; then psql -q -c "$2"; fi
      ;;
   exec)
      psql -q -c "$2"
      ;;
   status)
      echo true 
   esac
fi


