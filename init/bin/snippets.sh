

init/bin/rapi.sh POST https://es01:9200/spark-log-ds/_update_by_query init/q2.json | jq . > r.json

init/bin/rapi.sh PUT _watcher/watch/spark-test init/spark-test.watcher.json

init/bin/rapi.sh POST _watcher/watch/spark-test/_execute?debug=true

init/bin/rapi.sh POST _bulk init/test.bulk.json | jq . > bulk.res.json
init/bin/rapi.sh PUT _watcher/watch/spark_batch_watcherXXX init/batch_info.spark.watcher.json  | jq .

jq '."watch_record"."result"."actions"[]{"id": ."id", "status": ."status" }' r.watch.json

init/bin/rapi.sh GET _license/trial_status
init/bin/rapi.sh GET _license
init/bin/rapi.sh POST _license/start_trial?acknowledge=true

init/bin/rapi.sh POST _ingest/pipeline/spark-pipeline/_simulate init/ingest/ingest.testjson |jq .|more

init/bin/rapi.sh PUT _enrich/policy/match-policy init/match/match.enrich-policy.json

init/bin/rapi.sh PUT _watcher/watch/spark-match init/match/spark.match.watcher.json | jq .
init/bin/rapi.sh POST _watcher/watch/spark-match/_execute?debug=true

init/bin/rapi.sh PUT _ilm/policy/batch-active init/ILM/batch-active.ilm.json
init/bin/rapi.sh PUT _ilm/policy/spark-logs init/ILM/spark-logs.ilm.json


init/bin/rapi.sh PUT _ilm/policy/spark-logs init/ILM/spark-logs.ilm.json

init/bin/rapi.sh GET batch-active-index/_search init/query.json  |jq . > q.json

# Good with new directory structure

init/bin/rapi.sh POST batch-active-index/_update_by_query init/batch-active/clear_matched.ubq.json | jq .
init/bin/rapi.sh POST batch-active-index/_delete_by_query init/batch-active/delete-matched.dbq.json | jq .

# watchers

init/bin/rapi.sh PUT _watcher/watch/batch-match init/batch-active/match.watcher.json 
init/bin/rapi.sh POST _watcher/watch/batch-match/_execute?debug=true > mw.out.json

init/bin/rapi.sh PUT _watcher/watch/delete-matched init/batch-active/delete-matched.watcher.json
init/bin/rapi.sh POST _watcher/watch/delete-matched/_execute?debug=true > dmw.out.json