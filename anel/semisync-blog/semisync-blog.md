# MariaDB semi-sync replication using containers

In the last blog [MariaDB replication using containers](https://mariadb.org/mariadb-replication-using-containers/)
we showed how to properly replicate data in MariaDB using Docker containers.
We used standard or asynchronous or lazy replication.

```mermaid
flowchart LR
   %% subgraph async["Standard (asynchronous) replication"]
        direction LR
        %% Definitions
        primary[("MariaDB\nPrimary")]
        rep1[("MariaDB\nReplica 1")]
        rep2[("MariaDB\nReplica 2")]

        %% Connections
        primary-.->rep1 & rep2
        %% Style color
        linkStyle 0,1 stroke:#321be0,stroke-width:4px,color:red;
    %% end
```

In this blog we will visualise following:

1. Standard replication configuration
2. Standard replication transaction example
3. Semi-sync replication configuration
4. Semi-sync replication transaction example
5. Semi-sync demo example

## 1. Standard replication configuration
To configure the standard replication implemented in previous blog was straight forward:

```mermaid
sequenceDiagram
    participant Primary
    participant Replica1
    participant Replica2

    Note over Primary,Replica2: Standard (asynchronous) replication
    critical Setup and start primary
        option Setup primary configuration
            Primary->Primary: Set log-bin, server_id
        option Setup user
            Primary->Primary: Create user and grant privileges
    end
    rect rgb(191, 223, 255)
        note left of Primary: Primary started
    end
    critical Setup and start replicas
        option Setup replica configuration
            Replica1->Replica1: Set `server_id`
            Replica2->Replica2: Set `server_id`
        option Setup replica filtering - optional
            Replica1->Replica1: Filter specific database
        option Change master
            Replica1->Replica1: Execute `change master`
            Replica2->Replica2: Execute `change master`
    end
     rect rgb(191, 223, 255)
        note over Replica1, Replica2: Replicas started
    end
```

## 2. Standard replication transaction

On thread level (see [replication-threads](https://mariadb.com/kb/en/replication-threads/)),flow of active transaction we can express as following:

```mermaid
sequenceDiagram
    autonumber
    %%{
    init: {
        'theme': 'base',
        'themeVariables': {
            'primaryColor': '#BB2528',
            'primaryTextColor': '#292626',
            'primaryBorderColor': '#7C0000',
            'lineColor': '#F8B229',
            'secondaryColor': '#006100',
            'tertiaryColor': '#fff',
            'sequenceNumberColor':'#F7AFAD'
        }
    }
    }%%

    box Primary threads
        participant Binlog-dump-1
        participant Binlog-dump-2
        participant Cp as Client primary
    end

    box Replica 1 thread
        participant IO-1
        participant SQL-1
        participant w as Worker [parallel replication]
    end

    box Replica 2 thread
        participant IO-2
        participant SQL-2
    end

    Note over Binlog-dump-1,SQL-2: Standard (asynchronous) replication transaction cycle
    rect rgb(191, 223, 255)
        note over Binlog-dump-1, Cp: Primary started
    end
    rect rgb(191, 223, 255)
        note over IO-1, w: Replica 1 started
    end
    rect rgb(191, 223, 255)
        note over IO-2, SQL-2: Replica 2 started
    end
    Cp->>Cp: Make transaction T1
    par Dump binlog to r1
        IO-1->>Binlog-dump-1: R1 ready, please give events.
        Binlog-dump-1->>IO-1: Dump binary log to r1
    and Dump binlog to r2
        IO-2->>Binlog-dump-2: R2 ready, please give events.
        Binlog-dump-2->>IO-2: Dump binary log to r2
    and Write relaylog r1
        activate IO-1
        IO-1-->IO-1: Write relay log
        IO-1-->>IO-1: Write/update master.info
        deactivate IO-1
    and Write relaylog r2
        activate IO-2
        IO-2-->IO-2: Write relay log
        IO-2-->>IO-2: Write/update master.info
        deactivate IO-2
    end

    par Read relay logs r1
        SQL-1->>IO-1: Read relaylog events
        activate SQL-1
        SQL-1-->SQL-1: write relay-log.info
        opt Binlog uses GTID (MASTER_USE_GTID)
            SQL-1-->SQL-1: Write event in mysql.gtid_slave_pos
        end
        deactivate SQL-1
    and Read relay logs r2
        SQL-2->>IO-2: Read relaylog events
        activate SQL-2
        SQL-2-->SQL-2: write relay-log.info
        opt Binlog uses GTID (MASTER_USE_GTID)
            SQL-2-->SQL-2: Write event in mysql.gtid_slave_pos
        end
        deactivate SQL-2
    end
```

Type of the replication is asynchronous that means that we don't have any feedback information from replicas,
that event has been successfully received by replica, as can be seen from picture.

## 3. Semi-sync replication configuration
To configure the semi-sync replication we need to stop replicase and set environment variables on primary and replicas.
On primary set `rpl_semi_sync_master_enabled` and on replicas set `rpl_semi_sync_slave_enabled`.

```mermaid
sequenceDiagram
    participant Primary
    participant Replica1
    participant Replica2

    Note over Primary,Replica2: Standard (asynchronous) replication
    critical Setup and start primary
        option Setup primary configuration
            Primary->Primary: Set log-bin, server_id, rpl_semi_sync_master_enabled
        option Setup user
            Primary->Primary: Create user and grant privileges
    end
    rect rgb(191, 223, 255)
        note left of Primary: Primary started
    end
    critical Setup and start replicas
        option Stop replicas
            Replica1->Replica1: Stop IO thread
            Replica2->Replica2: Stop IO thread
        option Setup replica configuration
            Replica1->Replica1: Set `server_id`, rpl_semi_sync_slave_enabled
            Replica2->Replica2: Set `server_id`, rpl_semi_sync_slave_enabled
        option Setup replica filtering - optional
            Replica1->Replica1: Filter specific database
        option Change master
            Replica1->Replica1: Execute `change master`
            Replica2->Replica2: Execute `change master`
        option Start replicas
            Replica1->Replica1: Start IO thread
            Replica2->Replica2: Start IO thread
    end
     rect rgb(191, 223, 255)
        note over Replica1, Replica2: Replicas started
    end
```

## 4. Semi-sync replication transaction example
Semi-sync should overcome that problem, with introducing additional primary thread , called ["ACK Receiver Thread"](https://mariadb.com/kb/en/replication-threads/#ack-receiver-thread).
Only one replica is needed to confirm, that it has received and logged the events, as showed on following picture:

```mermaid
sequenceDiagram
    autonumber
    %%{init: {'theme': 'dark'} }%%

    box Primary threads
        participant Binlog-dump-1
        participant Binlog-dump-2
        participant Cp as Client primary
    end

    box Primary threads -semisync
        participant ack1 as ACK 1
        participant ack2 as ACK 2
    end

    box Replica 1 thread
        participant IO-1
        participant SQL-1
        participant w as Worker [parallel-replication]
    end

    box Replica 2 thread
        participant IO-2
        participant SQL-2
    end

Note over Binlog-dump-1,SQL-2: Semi-sync replication transaction cycle
    rect rgb(191, 223, 255)
        note over Binlog-dump-1, Cp: Primary started
    end
    rect rgb(191, 223, 255)
        note over IO-1, w: Replica 1 started
    end
    rect rgb(191, 223, 255)
        note over IO-2, SQL-2: Replica 2 started
    end
    Cp->>Cp: Make transaction T1
    par Dump binlog to r1
        IO-1->>Binlog-dump-1: R1 ready, please give events.
        Binlog-dump-1->>IO-1: Dump binary log to r1
    and Dump binlog to r2
        IO-2->>Binlog-dump-2: R2 ready, please give events.
        Binlog-dump-2->>IO-2: Dump binary log to r2
    and Write relaylog r1
        activate IO-1
        IO-1-->IO-1: Write relay log
        IO-1-->>IO-1: Write/update master.info
        deactivate IO-1
    and Write relaylog r2
        activate IO-2
        IO-2-->IO-2: Write relay log
        IO-2-->>IO-2: Write/update master.info
        deactivate IO-2
    end

    par Read relay logs r1
        SQL-1->>IO-1: Read relaylog events
        activate SQL-1
        SQL-1-->SQL-1: write relay-log.info
        opt Binlog uses GTID (MASTER_USE_GTID)
            SQL-1-->SQL-1: Write event in mysql.gtid_slave_pos
        end
        deactivate SQL-1
    and Read relay logs r2
        SQL-2->>IO-2: Read relaylog events
        activate SQL-2
        SQL-2-->SQL-2: write relay-log.info
        opt Binlog uses GTID (MASTER_USE_GTID)
            SQL-2-->SQL-2: Write event in mysql.gtid_slave_pos
        end
        deactivate SQL-2
    end
    %% Semi-sync
        activate SQL-1
        SQL-1->>IO-1: Event executed
        deactivate SQL-1
        activate IO-1
        opt Transaction received - no timeout
            IO-1->>ack1: Transaction received
            Note over IO-1, ack1: Semisync response R1
            deactivate IO-1
            activate ack1
            ack1->>Binlog-dump-1: Report to binlog r1
            Note over ack1, Binlog-dump-1: Send new event to r1 & r2
            deactivate ack1
        end
        opt Transaction not received - timeout
            ack1->>Binlog-dump-1: Switch to asynchronous replication.
            Note left of Binlog-dump-1: Rpl_semi_sync_master_status =OFF
        end
        %% Semi-sync - optional - depending if R1 received first
        %%    activate SQL-2
        %%    SQL-2->>IO-2: Event executed
        %%    deactivate SQL-2
        %%    activate IO-2
        %%    IO-2->>ack2: Transaction received
        %%    Note over IO-2, ack2: Semisync response R2
        %%   deactivate IO-2
        %%    activate ack2
        %%    ack2->>Binlog-dump-2: Report to binlog r2
        %%    Note over ack2, Binlog-dump-2: Send new event r2
        %%    deactivate ack2
    %% not possible
    %% style ack1 fill:#f9f,stroke:#333,stroke-width:4px
    %% if needed mscgen can be used
```

## 5. Semi-sync demo example with containers
We will be using GTIDs as promised in last blog.
GTID is enabled automatically, however we need to update configuration on the replicas by adding `CHANGE MASTER TO master_use_gtid=slave_pos`.
This way replication will start at the position of the last GTID replicated to replica (seen from `gtid_slave_pos` system variable).
### 5.1 Start the cluster
```
```
### 5.2 Check containers
```bash
$ docker compose up
 docker ps
CONTAINER ID   IMAGE          COMMAND                  CREATED          STATUS                             PORTS                                       NAMES
bfaa9f47e2a0   mariadb:10.6   "docker-entrypoint.s…"   30 seconds ago   Up 28 seconds (health: starting)   0.0.0.0:3388->3306/tcp, :::3388->3306/tcp   mariadb-replica-2-semisync
b8b64e3c7bf7   mariadb:10.6   "docker-entrypoint.s…"   30 seconds ago   Up 29 seconds (health: starting)   0.0.0.0:3377->3306/tcp, :::3377->3306/tcp   mariadb-replica-1-semisync
cddcba02bded   mariadb:10.6   "docker-entrypoint.s…"   30 seconds ago   Up 29 seconds (health: starting)   0.0.0.0:3366->3306/tcp, :::3366->3306/tcp   mariadb-primary-semisync

```
From logs we can see that
```bash
mariadb-replica-1-semisync  | 2023-11-22 14:49:58 5 [Note] Slave I/O thread: Start semi-sync replication to master 'repluser@mariadb-primary-semisync:3366' in log '' at position 4
mariadb-replica-1-semisync  | 2023-11-22 14:49:58 6 [Note] Slave SQL thread initialized, starting replication in log 'FIRST' at position 4, relay log './my-mariadb-relay-bin.000001' position: 4; GTID position ''
mariadb-replica-1-semisync  | 2023-11-22 14:49:58 0 [Note] mariadbd: ready for connections.
mariadb-replica-1-semisync  | Version: '10.11.6-MariaDB-1:10.11.6+maria~ubu2204-log'  socket: '/run/mysqld/mysqld.sock'  port: 3306  mariadb.org binary distribution
mariadb-replica-1-semisync  | 2023-11-22 14:49:58 5 [ERROR] Slave I/O: error connecting to master 'repluser@mariadb-primary-semisync:3366' - retry-time: 10  maximum-retries: 100000  message: Can't connect to server on 'mariadb-primary-semisync' (111 "Connection refused"), Internal MariaDB error code: 2003

mariadb-primary-semisync    | 2023-11-22 14:50:07 7 [Warning] Timeout waiting for reply of binlog (file: my-mariadb-bin.000001, pos: 491), semi-sync up to file , position 0.
mariadb-primary-semisync    | 2023-11-22 14:50:07 7 [Note] Semi-sync replication switched OFF.

```

### 5.3 Check primary
- Check semisync enabled
```bash
$ docker exec -it mariadb-primary-semisync -e "select @@rpl_semi_sync_master_enabled;"
....
```
- Check master status
```bash
$ docker exec mariadb-primary-semisync mariadb -uroot -psecret -e "show master status\G;"
*************************** 1. row ***************************
            File: my-mariadb-bin.000002
        Position: 347
    Binlog_Do_DB: 
Binlog_Ignore_DB: 
```

- Check binary logs
There are 2 binary logs
```bash
$ ls /var/lib/mysql/|grep my-maria
my-mariadb-bin.000001
my-mariadb-bin.000002
my-mariadb-bin.index
```

- The same can be seen from `mariadb` client:
```bash
$ docker exec mariadb-primary-semisync mariadb -uroot -psecret -e "show binary logs\G;"
*************************** 1. row ***************************
 Log_name: my-mariadb-bin.000001
File_size: 989
*************************** 2. row ***************************
 Log_name: my-mariadb-bin.000002
File_size: 347

```

This is weird
```bash
$ docker exec mariadb-primary-semisync mariadb-binlog my-mariadb-bin.000002
```
### 5.4 Check replica
```bash
```
$ docker exec -it mariadb-primary-semisync -e "select @@rpl_semi_sync_slave_enabled;"
....
```
```


- Not related to the blog - part of the [MDBF](https://jira.mariadb.org/browse/MDBF-573). (this will not be part of the blog)