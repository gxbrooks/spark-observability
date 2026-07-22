# Spark Master CI validation anomalies (2026-07-22)

Queried: ServiceNow `optimizincdemo1` and Dynatrace `pdt20158`.

1. **No `cmdb_ci_kubernetes_deployment` for spark-master** — actual workload CI is **`cmdb_ci_kubernetes_statefulset`** named `spark-master` (sys_id `26f85500fdd643949dc31d92648d3abc`).

2. **SGC does not bind Dynatrace cloud-app entities to the pod/StatefulSet** — DT has `CLOUD_APPLICATION-DDA8B7F35B5223C8` (`spark-master`) and `CLOUD_APPLICATION_INSTANCE-4F2D46089A9D634B` (`spark-master-0`), but **no** `sys_object_source` rows with those entity IDs. Pod CI exists from KVA (`sys_object_source` name=ServiceNow only). Webhook cannot bind `CLOUD_APPLICATION_INSTANCE` → pod via SGO today.

3. **Illustrative name "Apache Spark Master" does not exist** — real process group is `Apache Spark 10.244.0.131 spark-master-*` (`PROCESS_GROUP-6EB611A83EA5AF4B` → `cmdb_ci_group`). Multiple historical `PROCESS_GROUP`s contain `spark-master` in the name (pod IP churn).

4. **Host naming** — DT HOST displayName=`Lab3` (`HOST-D8207A117616460E`); SN linux_server and k8s_node both named **`lab3`**.

5. **AS Depends on unexpected endpoints** — `Lab3.lan:31686` and `Lab3.lan:32636` (likely leftover vertical entry points), in addition to intended CSDM depends_on (OTel, ES, Logstash, lab3 nfs_server). Application Service → `cmdb_ci_linux_server` depends_on edges are no longer declared in CSDM; remove any leftover **Depends on::Used by** edges to `lab3` (`cmdb_ci_linux_server`) from prior deploys.

6. **Pod placement relationship** — SN uses **Contains** from `lab3` (k8s node) → `spark-master-0`, not `Runs on` from pod → node.
