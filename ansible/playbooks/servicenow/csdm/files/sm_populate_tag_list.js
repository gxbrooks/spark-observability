(function process(/*RESTAPIRequest*/ request, /*RESTAPIResponse*/ response) {
    var data = (request.body && request.body.data) ? request.body.data : (request.body || {});
    var serviceSysId = data.service_sys_id || request.queryParams.service_sys_id;
    var serviceName = data.service_name || request.queryParams.service_name;
    var tags = data.tags || [];

    if (!tags || !tags.length) {
        response.setStatus(400);
        return { error: 'tags array required (key/value objects for tag_list population)' };
    }

    var serviceGr = new GlideRecord('cmdb_ci_service');
    if (serviceSysId) {
        if (!serviceGr.get(serviceSysId)) {
            response.setStatus(404);
            return { error: 'Application service not found: ' + serviceSysId };
        }
    } else if (serviceName) {
        serviceGr.addQuery('name', serviceName);
        serviceGr.query();
        if (!serviceGr.next()) {
            response.setStatus(404);
            return { error: 'Application service not found: ' + serviceName };
        }
        serviceSysId = serviceGr.getUniqueValue();
    } else {
        response.setStatus(400);
        return { error: 'Provide service_name or service_sys_id' };
    }

    var steps = [];

    // 1. Tag-based population is computed only for the Tag-Based Application
    //    Service class (extends cmdb_ci_service_discovered, so CSDM lookups on
    //    the parent table still find the record and the sys_id is preserved).
    if (serviceGr.getValue('sys_class_name') !== 'cmdb_ci_service_by_tags') {
        serviceGr.setValue('sys_class_name', 'cmdb_ci_service_by_tags');
        serviceGr.update();
        steps.push('reclassed to cmdb_ci_service_by_tags');
    }

    // 2. Resolve the tag category name for each tag key (svc_tag_names →
    //    svc_tag_categories). The populator metadata references category
    //    names, not raw cmdb_key_value keys.
    var categoryValues = [];
    for (var i = 0; i < tags.length; i++) {
        var tagKey = tags[i].key;
        var tagValue = tags[i].value;
        var catName = '';
        var nameGr = new GlideRecord('svc_tag_names');
        nameGr.addQuery('name', tagKey);
        nameGr.query();
        if (nameGr.next()) {
            catName = nameGr.category.name.toString();
        }
        if (!catName) {
            response.setStatus(400);
            return {
                error: 'No CI tag category registered for tag key: ' + tagKey +
                    ' (run ensure_tag_categories first)',
                service_sys_id: serviceSysId
            };
        }
        categoryValues.push({ category: catName, value: tagValue });
    }

    // 3. Resolve the tag-based service populator record.
    var populatorSysId = '';
    var popGr = new GlideRecord('service_populator');
    if (popGr.isValid()) {
        popGr.addQuery('nameLIKEtag');
        popGr.query();
        if (popGr.next()) {
            populatorSysId = popGr.getUniqueValue();
        }
    }
    if (!populatorSysId) {
        // OOB "Service Populator For Tags" ships with a fixed sys_id.
        populatorSysId = 'cae02879c3b23300daa79624a1d3ae2f';
    }

    try {
        // 4. Configure the tag-based service definition.
        var byTagsGr = new GlideRecord('cmdb_ci_service_by_tags');
        if (!byTagsGr.get(serviceSysId)) {
            response.setStatus(500);
            return { error: 'Service not readable as cmdb_ci_service_by_tags after reclass', service_sys_id: serviceSysId };
        }
        byTagsGr.setValue('metadata', JSON.stringify({
            category_values: categoryValues,
            checksum: 'WAITING_FOR_UPDATE'
        }));
        byTagsGr.setValue('service_populator', populatorSysId);
        byTagsGr.setValue('populator_status', '0'); // Draft while topology is prepared
        byTagsGr.setValue('calculation_status', '1'); // Waiting for calculation
        byTagsGr.setValue('type', '4'); // Tag-based
        byTagsGr.update();
        steps.push('metadata + populator configured');

        // 5. Mark ready and run the populator (same engine as the
        //    "Recalculate Service" related link).
        byTagsGr = new GlideRecord('cmdb_ci_service_by_tags');
        byTagsGr.get(serviceSysId);
        byTagsGr.setValue('populator_status', '1'); // Ready for calculation
        byTagsGr.update();

        byTagsGr = new GlideRecord('cmdb_ci_service_by_tags');
        byTagsGr.get(serviceSysId);
        var runner = new SNC.ServicePopulatorRunner('INTERACTIVE');
        runner.run(byTagsGr);
        steps.push('populator run');
    } catch (e) {
        response.setStatus(500);
        return {
            error: e.message || String(e),
            steps: steps,
            service_sys_id: serviceSysId,
            service: serviceGr.getValue('name')
        };
    }

    serviceGr = new GlideRecord('cmdb_ci_service_by_tags');
    serviceGr.get(serviceSysId);

    var assocCount = new GlideAggregate('svc_ci_assoc');
    assocCount.addQuery('service_id', serviceSysId);
    assocCount.addAggregate('COUNT');
    assocCount.query();
    var members = assocCount.next() ? parseInt(assocCount.getAggregate('COUNT'), 10) : 0;

    response.setStatus(202);
    return {
        operation: 'service_mapping_populate_tag_list',
        service: serviceGr.getValue('name'),
        service_sys_id: serviceSysId,
        sys_class_name: serviceGr.getValue('sys_class_name'),
        steps: steps,
        tags: tags,
        category_values: categoryValues,
        member_count: members,
        metadata: serviceGr.getValue('metadata'),
        service_populator: serviceGr.getValue('service_populator'),
        populator_status: serviceGr.getValue('populator_status'),
        calculation_status: serviceGr.getValue('calculation_status'),
        service_status: serviceGr.getValue('service_status'),
        service_status_display: serviceGr.service_status.getDisplayValue()
    };
})(request, response);
