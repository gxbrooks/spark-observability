# SGC Store applications

`store_apps.yml` is the desired-state list of ServiceNow Store apps and plugins
for the Dynatrace Service Graph Connector stack, in install order. Later items
depend on earlier ones.

`version` pins the expected installed version. Empty means no pin; `sgc/install.yml`
installs the latest resolvable version. Pins match `sn_dynatrace_integ` 1.15.0
Store-declared dependencies.
