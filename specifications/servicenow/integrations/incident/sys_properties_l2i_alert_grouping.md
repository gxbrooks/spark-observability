# L2I alert grouping sys_properties

Job-based grouping requires matching `metric_name` AND `cmdb_ci`, so
Automated grouping does not bucket every log on the same service instance.
Aggregation stays enabled (PATTERN still runs).

`sa_analytics.agg.query.group_logic_order` is a product-owned, ordered list.
Its entry uses `value_includes` instead of `value`: deploy appends
`TAG_BASED` to the instance's current list (keeping the product order) when
it is missing, so the metric_class TBAC definition (CPU-family clustering)
can run. Deploy does not create the property when the instance has no value.
