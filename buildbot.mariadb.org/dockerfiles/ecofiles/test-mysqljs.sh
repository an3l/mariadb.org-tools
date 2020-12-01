#!/bin/bash

cd /code
[ -d mysql ] || git clone https://github.com/mysqljs/mysql
cd mysql
git clean -dfx
git pull --tags
if [ -n "$1" ]
then
  if [ ! -d ../"$1" ]
  then
    git worktree add ../"$1" "$1"
  fi
  cd ../"$1"
  git checkout origin/$1
fi

# We should have installed npm and have to update nodejs to latest version
npm --version
if [ -n "$?" ]
then
  npm install -g n
  n latest
  PATH="$PATH"
  node --version
fi

npm install
# Run the unit tests (probably should be controlled with worker variable)
# If unit==1 run unit test else run integration test
cd ./test
FILTER=unit npm test

# Run integration test - we are more interested in this!
#mysql -u root -e "CREATE DATABASE IF NOT EXISTS node_mysql_test"
#MYSQL_HOST=localhost MYSQL_PORT=3306 MYSQL_DATABASE=node_mysql_test MYSQL_USER=root MYSQL_PASSWORD= FILTER=integration npm test

