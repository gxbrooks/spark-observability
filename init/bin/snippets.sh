

init/bin/rapi.sh POST https://es01:9200/spark-log-ds/_update_by_query init/q2.json | jq . > r.json

init/bin/rapi.sh PUT _watcher/watch/spark-test init/spark-test.watcher.json

init/bin/rapi.sh POST _watcher/watch/spark-test/_execute?debug=true

init/bin/rapi.sh POST _bulk init/test.bulk.json | jq . > bulk.res.json
init/bin/rapi.sh PUT _watcher/watch/spark_batch_watcherXXX init/batch_info.spark.watcher.json  | jq .
init/bin/rapi.sh POST XXXspark-log-ds/_update_by_query init/clear_copied_flag.json | jq . > r.watch.json

jq '."watch_record"."result"."actions"[]{"id": ."id", "status": ."status" }' r.watch.json

init/bin/rapi.sh GET _license/trial_status
init/bin/rapi.sh GET _license
init/bin/rapi.sh POST _license/start_trial?acknowledge=true

init/bin/rapi.sh POST _ingest/pipeline/spark-pipeline/_simulate init/ingest/ingest.testjson |jq .|more

