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

    try {
        var evaluator = new GlideScopedEvaluator();
        evaluator.setApplication('sn_service_mapping');
        evaluator.putVariable('serviceSysId', serviceSysId);
        evaluator.putVariable('tags', tags);
        evaluator.evaluateString(
            'var tagUtils = new SMServiceByTagsUtils();' +
            'tagUtils.updateServiceFromTagsList(serviceSysId, tags, null);'
        );
    } catch (e) {
        response.setStatus(500);
        return {
            error: e.message || String(e),
            service_sys_id: serviceSysId,
            service: serviceGr.getValue('name')
        };
    }

    serviceGr.get(serviceSysId);

    response.setStatus(202);
    return {
        operation: 'service_mapping_populate_tag_list',
        service: serviceGr.getValue('name'),
        service_sys_id: serviceSysId,
        sys_class_name: serviceGr.getValue('sys_class_name'),
        tags: tags,
        process_status: serviceGr.getValue('process_status'),
        process_status_display: serviceGr.process_status.getDisplayValue(),
        service_status: serviceGr.getValue('service_status'),
        service_status_display: serviceGr.service_status.getDisplayValue()
    };
})(request, response);
