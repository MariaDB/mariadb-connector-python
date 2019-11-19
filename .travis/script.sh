#!/bin/bash

set -x
set -e

###################################################################################################################
# test different type of configuration
###################################################################################################################
mysql=( mysql --protocol=tcp -ubob -h127.0.0.1 --port=3305 )

if [ "$DB" = "build" ] ; then
  .travis/build/build.sh
  docker build -t build:latest --label build .travis/build/
fi

export ENTRYPOINT=$PROJ_PATH/.travis/entrypoint
if [ -n "$MAXSCALE_VERSION" ] ; then
  ###################################################################################################################
  # launch Maxscale with one server
  ###################################################################################################################
  export COMPOSE_FILE=.travis/maxscale-compose.yml
  export ENTRYPOINT=$PROJ_PATH/.travis/sql
  docker-compose -f ${COMPOSE_FILE} build
  docker-compose -f ${COMPOSE_FILE} up -d
  mysql=( mysql --protocol=tcp -ubob -h127.0.0.1 --port=4007 )
else
  docker-compose -f .travis/docker-compose.yml up -d
fi

for i in {60..0}; do
    if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
        break
    fi
    echo 'data server still not active'
    sleep 1
done

if [ -z "$MAXSCALE_VERSION" ] ; then
  docker-compose -f .travis/docker-compose.yml exec -u root db bash /pam/pam.sh
  sleep 1
  docker-compose -f .travis/docker-compose.yml stop db
  sleep 1
  docker-compose -f .travis/docker-compose.yml up -d
  docker-compose -f .travis/docker-compose.yml logs db

  for i in {60..0}; do
    if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
        break
    fi
    echo 'data server still not active'
    sleep 1
  done

fi

if [ -n "$BENCH" ] ; then
  pyenv install pypy3.6-7.2.0
  pyenv install miniconda3-4.3.30
  pyenv install 3.8.0


  export PYENV_VERSION=3.8.0
  python setup.py build
  python setup.py install
  pip install mysql-connector-python pyperf
  python bench_mariadb.py -o mariadb_bench.json --inherit-environ=TEST_USER,TEST_HOST,TEST_PORT
  python bench_mysql.py -o mysql_bench.json --inherit-environ=TEST_USER,TEST_HOST,TEST_PORT

  python -m pyperf compare_to mysql_bench.json mariadb_bench.json --table

  export PYENV_VERSION=miniconda3-4.3.30
  python setup.py build
  python setup.py install
  pip install mysql-connector-python pyperf
  python bench_mariadb.py -o mariadb_bench_miniconda3_4_3_30.json --inherit-environ=TEST_USER,TEST_HOST,TEST_PORT
  python bench_mysql.py -o mysql_bench_miniconda3_4_3_30.json --inherit-environ=TEST_USER,TEST_HOST,TEST_PORT

  python -m pyperf compare_to mysql_bench_miniconda3_4_3_30.json mariadb_bench_miniconda3_4_3_30.json --table

  export PYENV_VERSION=pypy3.6-7.2.0
  python setup.py build
  python setup.py install
  pip install mysql-connector-python pyperf
  python bench_mariadb.py -o mariadb_bench_pypy3_6.json --inherit-environ=TEST_USER,TEST_HOST,TEST_PORT
  python bench_mysql.py -o mysql_bench_pypy3_6.json --inherit-environ=TEST_USER,TEST_HOST,TEST_PORT

  python -m pyperf compare_to mysql_bench_pypy3_6.json mariadb_bench_pypy3_6.json --table

  python -m pyperf compare_to mysql_bench.json mariadb_bench.json mariadb_bench_pypy3_6.json \
    mysql_bench_pypy3_6.json mariadb_bench_miniconda3_4_3_30.json \
    mysql_bench_miniconda3_4_3_30.json --table
else
  pyenv install $PYTHON_VER
  export PYENV_VERSION=$PYTHON_VER

  python setup.py build
  python setup.py install

  python -m unittest discover -v
fi


