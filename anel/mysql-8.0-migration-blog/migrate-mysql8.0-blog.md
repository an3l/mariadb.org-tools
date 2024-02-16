# Migrate from 8.0 to MariaDB
Part of [MDBF-633: Create blogs for migration from MySQL 5.7/8.0 with Docker Official Images using Docker compose](https://jira.mariadb.org/browse/MDBF-633)
Navigate to [mariadb-docker/examples/migraton-8.0](https://github.com/MariaDB/mariadb-docker/tree/master/examples)
Check compose file (compose-mysql8.0.yml)
Execute command
```bash
$ docker compose -f compose-mysql8.0.yml up
$ docker ps
CONTAINER ID   IMAGE          COMMAND                  CREATED         STATUS                          PORTS                 NAMES
67cb1983194f   mysql:8.3.0    "docker-entrypoint.s…"   3 minutes ago   Up 3 minutes (healthy)          3306/tcp, 33060/tcp   mysql-container
$ docker exec -it mysql-container mysql -uroot -psecret -e "select * from testdb.countries"
$ docker exec -it mysql-container mysql -uroot -psecret -e "show databases"
mysql: [Warning] Using a password on the command line interface can be insecure.
+----------------------+
| name                 |
+----------------------+
| Bosnia & Herzegovina |
+----------------------+
```
# Get system tables
- Before stoping the container execute `mariadb-dump --system` to get system tables
- Start mariadb container
```bash
$ docker run --name mariadb-container --rm -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1 mariadb:latest
$ docker ps
$ docker ps
CONTAINER ID   IMAGE            COMMAND                  CREATED          STATUS                          PORTS                 NAMES
88a3351fd126   mariadb:latest   "docker-entrypoint.s…"   21 seconds ago   Up 21 seconds                   3306/tcp              mariadb-container
67cb1983194f   mysql:8.3.0      "docker-entrypoint.s…"   6 minutes ago    Up 6 minutes (healthy)          3306/tcp, 33060/tcp   mysql-container
```
- Intercontainer communication
```bash
$ docker inspect mysql-container |grep IPAddress
  "IPAddress": "172.31.0.3",
$ docker inspect mariadb-container-dump |grep IPAddress
  "IPAddress": "172.31.0.2",
# Above container is not on the same subnet
$ docker inspect mariadb-container |grep IPAddress
  "IPAddress": "172.17.0.2",
```
- Run `mariadb-dump` to
```bash
$ docker exec mariadb-container-dump mariadb-dump -h mysql-container -uroot -psecret testdb > mysql-dump.sql
$ docker exec mariadb-container-dump mariadb-dump -h mariadb-container -uroot -psecret testdb > mariadb-dump.sql
```
- Check file
```
$ docker exec mariadb-container-dump  sh -c 'ls /etc/mysql/conf.d'
```
