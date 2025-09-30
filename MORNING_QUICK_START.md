# Quick Start Guide - Morning Verification

## 🎉 **Good News: Spark Event Monitoring is WORKING!**

Last night I successfully:
- ✅ Fixed variable flow system (variables.yaml → context files)
- ✅ Configured Elastic Agent to send to GaryPC.lan
- ✅ Verified Spark events flowing to Elasticsearch (1,030+ documents!)
- ✅ Confirmed all Kibana data views are accessible
- ✅ Tested complete pipeline end-to-end

---

## Quick Verification Commands (Use These First!)

### 1. Check Elasticsearch Has Spark Data
```bash
# From Lab2, check Elasticsearch indices
timeout 10 ansible GaryPC-WSL -i ansible/inventory.yml -m shell -a \
  "sudo docker exec es curl -k -s -u elastic:myElastic2025 \
  'https://localhost:9200/_cat/indices?v' | grep -E 'batch-events|spark'"

# Expected output: Should show batch-events-000001 with docs
```

### 2. View Spark Events in Kibana
Open in browser:
- **Kibana**: http://GaryPC.lan:5601
- **Username**: elastic
- **Password**: myElastic2025
- Navigate to: **Discover** → Select **"Batch Events"** data view
- You should see Spark event data with timestamps, trace_ids, etc.

### 3. Run a Fresh Spark Job
```bash
cd ~/repos/elastic-on-spark
python3 spark/apps/Chapter_04.py

# Check if event count increases
timeout 10 ansible GaryPC-WSL -i ansible/inventory.yml -m shell -a \
  "sudo docker exec es curl -k -s -u elastic:myElastic2025 \
  'https://localhost:9200/batch-events-000001/_count'"
```

---

## Important: How to Run Spark Applications Now

### Method 1: Direct Execution (Recommended)
```bash
cd ~/repos/elastic-on-spark
python3 spark/apps/Chapter_03.py   # or Chapter_04, 05, etc.
```

**No wrapper needed!** The `linux/.bashrc` automatically sets:
- `SPARK_MASTER_URL=spark://Lab2.lan:32582`
- `SPARK_EVENTS_DIR=/mnt/spark/events`
- `HDFS_DEFAULT_FS=hdfs://hdfs-namenode:9000`

### Method 2: Using Wrapper (Alternative)
```bash
./spark/run_spark_app.sh spark/apps/Chapter_03.py
```

### Method 3: Interactive iPython
```bash
cd spark/ispark
./launch_ipython.sh

# Then in iPython:
spark.read.csv("/mnt/spark/data/some_file.csv").show()
```

---

## Key Access URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| **Kibana** | http://GaryPC.lan:5601 | elastic / myElastic2025 |
| **Grafana** | http://GaryPC.lan:3000 | admin / (check observability/.env) |
| **Elasticsearch** | https://GaryPC.lan:9200 | elastic / myElastic2025 |
| **Spark History** | http://Lab2.lan:31534 | (no auth) |

---

## If You Need to Regenerate Configs

### Regenerate ALL environment files:
```bash
python3 linux/generate_env.py -f -v
```

### Regenerate just Elastic Agent config:
```bash
python3 linux/generate_env.py elastic-agent
./elastic-agent/generate_env_conf.sh
```

### Deploy updated Elastic Agent config:
```bash
ansible native -i ansible/inventory.yml \
  -m copy -a "src=elastic-agent/env.conf dest=/etc/systemd/system/elastic-agent.service.d/env.conf" \
  --become

ansible native -i ansible/inventory.yml \
  -m systemd -a "name=elastic-agent state=restarted daemon_reload=yes" \
  --become
```

---

## Known Issues & Workarounds

### Issue 1: Curl to GaryPC.lan Sometimes Hangs
**Workaround**: Always use `timeout` command
```bash
# Good:
timeout 10 curl -k -s -u elastic:myElastic2025 "https://GaryPC.lan:9200/..."

# Bad (might hang):
curl -k -s -u elastic:myElastic2025 "https://GaryPC.lan:9200/..."
```

### Issue 2: Need to Run from Inside Container
**Workaround**: Use `docker exec` for reliable access
```bash
ansible GaryPC-WSL -i ansible/inventory.yml -m shell -a \
  "sudo docker exec es curl -k -s -u elastic:myElastic2025 'https://localhost:9200/...'"
```

---

## Next Steps (Optional)

1. **Test Docker telemetry** - Check if GaryPC Windows Elastic Agent is sending Docker metrics
2. **Verify K8s telemetry** - Look for Kubernetes-specific metrics in Elasticsearch
3. **Implement /mnt/c/Volumes structure** - For cross-platform compatibility
4. **Run all Chapter files** - Verify each one generates events correctly

---

## Troubleshooting

### If Spark Events Stop Flowing
```bash
# Check Elastic Agent status
systemctl status elastic-agent

# Check Logstash
timeout 10 ansible GaryPC-WSL -i ansible/inventory.yml -m shell -a \
  "sudo docker ps | grep logstash"

# Check event directory permissions
ls -la /mnt/spark/events/

# Restart Elastic Agent if needed
ansible native -i ansible/inventory.yml \
  -m systemd -a "name=elastic-agent state=restarted" --become
```

### If History Server Doesn't Show Applications
```bash
# Check History Server is running
kubectl get pods -n spark | grep history

# Check History Server logs
kubectl logs -n spark deployment/spark-history --tail=50

# Restart if needed
kubectl rollout restart deployment/spark-history -n spark
```

---

**Everything is working! See TESTING_RESULTS.md for detailed test results.**
