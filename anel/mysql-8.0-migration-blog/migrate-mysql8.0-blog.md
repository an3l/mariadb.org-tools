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


# MDEV-33486: Failed restore of dumped MySQL8.0 users with mariadb-dump

https://jira.mariadb.org/browse/MDEV-33486

1. Start MySQL 8.0 with [print_identified_with_as_hex](https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html#sysvar_print_identified_with_as_hex)
  - See [bug](https://bugs.mysql.com/bug.php?id=98732) cannot recreate user with `caching_sha2_password` plugin since string may contain binary characters
2. Path `mariadb-dump`

Script updated now we have dumped files created. Still problem with users is there.
```bash
$ ls dump-data
mysql-dump-data.sql.zst  mysql-dump.sql  mysql-dump-stats.sql.zst  mysql-dump-tzs.sql.zst  mysql-dump-users.sql.zst
$ docker ps
CONTAINER ID   IMAGE          COMMAND                  CREATED         STATUS                          PORTS                 NAMES
812d92b18cec   mariadb:lts    "docker-entrypoint.s…"   7 minutes ago   Up 7 minutes (healthy)          3306/tcp              mariadb-migrated-mysql8.0
8540652bb0c6   mariadb:lts    "docker-entrypoint.s…"   7 minutes ago   Up 7 minutes (healthy)          3306/tcp              mariadb-container-dump
433e1c92c753   mysql:8.3.0    "docker-entrypoint.s…"   7 minutes ago   Up 7 minutes (healthy)          3306/tcp, 33060/tcp   mysql-container

```
After adding `` to MySQL user password is in hex ([example](https://dbfiddle.uk/JXl0hvTI))
```sql
 CREATE USER `test123`@`%` IDENTIFIED WITH 'caching_sha2_password' AS 0x244124303035245E3E1F7C5679352031516D404455437E02286D3F5931614B3542374433575A4647704C5944364C736C34384E2E416F30447A784B725832557A307366534331 REQUIRE NONE PASSWORD EXPIRE DEFAULT ACCOUNT UNLOCK PASSWORD HISTORY DEFAULT PASSWORD REUSE INTERVAL DEFAULT PASSWORD REQUIRE CURRENT DEFAULT
```

## Testing in plugin MariaDB
- In MySQL
```SQL
mysql> show plugins;
+----------------------------------+----------+--------------------+---------+---------+
| Name                             | Status   | Type               | Library | License |
+----------------------------------+----------+--------------------+---------+---------+
| binlog                           | ACTIVE   | STORAGE ENGINE     | NULL    | GPL     |
| sha256_password                  | ACTIVE   | AUTHENTICATION     | NULL    | GPL     |
| caching_sha2_password            | ACTIVE   | AUTHENTICATION     | NULL    | GPL     |
| sha2_cache_cleaner               | ACTIVE   | AUDIT              | NULL    | GPL     |
| daemon_keyring_proxy_plugin      | ACTIVE   | DAEMON             | NULL    | GPL     |

mysql> select plugin_name from information_schema.plugins where plugin_type='authentication';
+-----------------------+
| plugin_name           |
+-----------------------+
| sha256_password       |
| caching_sha2_password |
| mysql_native_password |
+-----------------------+
3 rows in set (0.01 sec)

```
- In MariaDB
```sql
MariaDB [(none)]>  select plugin_name from information_schema.plugins where plugin_type='authentication';
+-----------------------+
| plugin_name           |
+-----------------------+
| mysql_native_password |
| mysql_old_password    |
| unix_socket           |
+-----------------------+
3 rows in set (0.001 sec)
```
In MariaDB `auth_socket` should serve as `caching_sha2_password`.

- So this fails:
```sql
>  CREATE USER `test123`@`%` IDENTIFIED WITH 'caching_sha2_password' AS 0x244124303035245E3E1F7C5679352031516D404455437E02286D3F5931614B3542374433575A4647704C5944364C736C34384E2E416F30447A784B725832557A307366534331;
 ERROR 1064 (42000): You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '0x244124303035245E3E1F7C5679352031516D404455437E02286D3F5931614B3542374433575...' at line 1
# When as string:
> CREATE USER `test123`@`%` IDENTIFIED WITH 'caching_sha2_password' AS "0x244124303035245E3E1F7C5679352031516D404455437E02286D3F5931614B3542374433575A4647704C5944364C736C34384E2E416F30447A784B725832557A307366534331";
ERROR 1524 (HY000): Plugin 'caching_sha2_password' is not loaded
# Puting the string in MySQL
mysql> CREATE USER `test123`@`%` IDENTIFIED WITH 'caching_sha2_password' AS "0x244124303035245E3E1F7C5679352031516D404455437E02286D3F5931614B3542374433575A4647704C5944364C736C34384E2E416F30447A784B725832557A307366534331";
ERROR 1827 (HY000): The password hash doesn't have the expected format.
```