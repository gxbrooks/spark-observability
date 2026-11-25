# sgc_inherit_location_from_host.br.json

Business rule (`sys_script`) record for `sgc_inherit_location_from_host.br.js`.
The deploy task
(`automation/ansible/playbooks/servicenow/sgc/tasks/ensure-sgc-location-business-rule.yml`)
adds `script` (the contents of the `.br.js` file) at apply time; `name` is the
lookup key.
