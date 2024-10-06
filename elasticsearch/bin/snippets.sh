

rapi POST //https://es01:9200/spark-log-ds/_update_by_query elasticsearch/q2.json | jq . > r.json

rapi PUT /_watcher/watch/spark-test elasticsearch/spark-test.watcher.json

rapi POST /_watcher/watch/spark-test/_execute?debug=true

rapi POST /_bulk elasticsearch/test.bulk.json | jq . > bulk.res.json
rapi PUT /_watcher/watch/spark_batch_watcherXXX elasticsearch/batch_info.spark.watcher.json  | jq .

jq '."watch_record"."result"."actions"[]{"id": ."id", "status": ."status" }' r.watch.json

rapi GET /_license/trial_status
rapi GET /_license
rapi POST /_license/start_trial?acknowledge=true

rapi POST /_ingest/pipeline/spark-pipeline/_simulate elasticsearch/ingest/ingest.testjson |jq .|more
 
rapi PUT /_enrich/policy/match-policy elasticsearch/match/match.enrich-policy.json

rapi PUT /_ilm/policy/batch-active elasticsearch/ILM/batch-active.ilm.json
rapi PUT /_ilm/policy/spark-logs elasticsearch/ILM/spark-logs.ilm.json


rapi PUT /_ilm/policy/spark-logs elasticsearch/ILM/spark-logs.ilm.json

rapi GET /batch-active-index/_search elasticsearch/query.json  |jq . > q.json

# Good with new directory structure

rapi POST /batch-active-index/_update_by_query elasticsearch/batch-active/clear_matched.ubq.json | jq .
rapi POST /batch-active-index/_delete_by_query elasticsearch/batch-active/delete-matched.dbq.json | jq .

# watchers

rapi PUT /_watcher/watch/batch-match elasticsearch/batch-active/match.watcher.json 
rapi POST /_watcher/watch/batch-match/_execute?debug=true > mw.out.json

rapi PUT /_watcher/watch/delete-matched elasticsearch/batch-active/delete-matched.watcher.json
rapi POST /_watcher/watch/delete-matched/_execute?debug=true > dmw.out.json


rapi POST /_watcher/watch/delete-matched/_deactivate 
rapi POST /_watcher/watch/batch-match/_deactivate
rapi POST /_watcher/watch/batch-metrics/_deactivate

rapi POST /_watcher/watch/delete-matched/_activate 
rapi POST /_watcher/watch/batch-match/_activate

rapi DELETE /_transform/batch-metrics | jq .

rapi PUT /_watcher/watch/batch-metrics elasticsearch/batch-metrics/batch-metrics.watcher.json
rapi POST /_watcher/watch/batch-metrics/_execute?debug=true > bmw.out.json



rapi GET /.ds-.watcher-history\*/_search elasticsearch/batch-active/batch-match-watchers.runs.query.json  | jq . > q.json

rapi GET /batch-active-index/_search?uid="Start:spark:Task:7449d6aeb0be:/opt/spark/spark-events/app-20240903164156-0007.inprogress:0:0:61:0" elasticsearch/batch-active/uid.query.json
rapi GET /batch-active-index/_search?q="Start:spark:Task:7449d6aeb0be:/opt/spark/spark-events/app-20240903164156-0007.inprogress:0:0:61:0" elasticsearch/batch-active/uid.query.json

# Get all watch results that had batch matches
rapi GET /.ds-.watcher-history\*/_search elasticsearch/batch-active/batch-match-watches.query.json  | jq . > q.json

# updates to emulate watcher updates
PUT /<target>/_doc/<_id>

POST /<target>/_doc/

rapi POST /batch-active-index/_doc/8af6a0994b05ee4d53d963bd42a22c788ffcaf9b?routing=fc419eef43f4e80f5faf45b63349bf2d8e7256cb elasticsearch/inputs/match.watcher.mustache_with_join_field.input.json | jq . |less

# find matching start and end events 

rapi GET /batch-active-index/_search?
rapi GET /batch-active-index/_search elasticsearch/batch-active/match-join.query.json  |jq .