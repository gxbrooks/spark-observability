

esapi POST //https://es01:9200/spark-log-ds/_update_by_query elasticsearch/q2.json | jq . > r.json

esapi PUT /_watcher/watch/spark-test elasticsearch/spark-test.watcher.json

esapi POST /_watcher/watch/spark-test/_execute?debug=true

esapi POST /_bulk elasticsearch/test.bulk.json | jq . > bulk.res.json
esapi PUT /_watcher/watch/spark_batch_watcherXXX elasticsearch/batch_info.spark.watcher.json  | jq .

jq '."watch_record"."result"."actions"[]{"id": ."id", "status": ."status" }' r.watch.json

esapi GET /_license/trial_status
esapi GET /_license
esapi POST /_license/start_trial?acknowledge=true

# batch-traces

esapi GET /batch-traces/_search elasticsearch/batch-traces/batch-traces.query.json  |jq . > ~/scratch/batch-traces.out.json

esapi PUT /_enrich/policy/match-policy elasticsearch/match/match.enrich-policy.json

esapi PUT /_ilm/policy/batch-events elasticsearch/ILM/batch-events.ilm.json
esapi PUT /_ilm/policy/spark-logs elasticsearch/ILM/spark-logs.ilm.json


esapi PUT /_ilm/policy/spark-logs elasticsearch/ILM/spark-logs.ilm.json

esapi GET /batch-events/_search elasticsearch/query.json  |jq . > q.json

# Good with new directory structure

esapi POST /batch-events/_update_by_query elasticsearch/batch-events/clear_matched.ubq.json | jq .
esapi POST /batch-events/_delete_by_query elasticsearch/batch-events/delete-matched.dbq.json | jq .

# watchers

esapi PUT /_watcher/watch/batch-match elasticsearch/batch-events/match.watcher.json 
esapi POST /_watcher/watch/batch-match/_execute?debug=true > mw.out.json

esapi PUT /_watcher/watch/delete-matched elasticsearch/batch-events/delete-matched.watcher.json
esapi POST /_watcher/watch/delete-matched/_execute?debug=true > dmw.out.json


esapi POST /_watcher/watch/delete-matched/_deactivate 
esapi POST /_watcher/watch/batch-match/_deactivate
esapi POST /_watcher/watch/batch-metrics/_deactivate

esapi POST /_watcher/watch/delete-matched/_activate 
esapi POST /_watcher/watch/batch-match/_activate

esapi DELETE /_transform/batch-metrics | jq .

esapi PUT /_watcher/watch/batch-metrics elasticsearch/batch-metrics/batch-metrics.watcher.json
esapi POST /_watcher/watch/batch-metrics/_execute?debug=true > bmw.out.json



# get all "batch-match-join" watcher runs that met the condition
esapi GET /.ds-.watcher-history\*/_search elasticsearch/batch-events/match-join.watcher-runs.query.json  | jq . > ~/scratch/match-join.watcher-runs.query.out.json

# batch-events

esapi GET /batch-events/_search elasticsearch/batch-events/batch-events.query.json  |jq . > ~/outputs/batch-events.out.json

esapi GET /batch-events/_search?event_uid="Start:spark:Task:7449d6aeb0be:/opt/spark/spark-events/app-20240903164156-0007.inprogress:0:0:61:0" elasticsearch/batch-events/event_uid.query.json
esapi GET /batch-events/_search?q="Start:spark:Task:7449d6aeb0be:/opt/spark/spark-events/app-20240903164156-0007.inprogress:0:0:61:0" elasticsearch/batch-events/event_uid.query.json

# Get all watch results that had batch matches
esapi GET /.ds-.watcher-history\*/_search elasticsearch/batch-events/batch-match-watches.query.json  | jq . > q.json

# updates to emulate watcher updates
PUT /<target>/_doc/<_id>

POST /<target>/_doc/

esapi POST /batch-events/_doc/8af6a0994b05ee4d53d963bd42a22c788ffcaf9b?routing=fc419eef43f4e80f5faf45b63349bf2d8e7256cb elasticsearch/inputs/match.watcher.mustache_with_join_field.input.json | jq . |less

# find matching start and end events 

esapi GET /batch-events/_search?
esapi GET /batch-events/_search elasticsearch/batch-events/match-join.query.json  |jq .