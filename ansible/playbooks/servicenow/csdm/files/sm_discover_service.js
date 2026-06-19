(function process(/*RESTAPIRequest*/ request, /*RESTAPIResponse*/ response) {
    var data = (request.body && request.body.data) ? request.body.data : (request.body || {});
    var serviceSysId = data.service_sys_id || request.queryParams.service_sys_id;
    var serviceName = data.service_name || request.queryParams.service_name;
    var registerEntry = data.register_entry_point !== false;

    if (!serviceSysId && !serviceName) {
        response.setStatus(400);
        return {
            error: 'Provide service_name or service_sys_id',
            example: { service_name: 'Spark Master' }
        };
    }

    var svc = new GlideRecord('cmdb_ci_service_discovered');
    if (serviceSysId) {
        if (!svc.get(serviceSysId)) {
            response.setStatus(404);
            return { error: 'Application service not found: ' + serviceSysId };
        }
    } else {
        svc.addQuery('name', serviceName);
        svc.query();
        if (!svc.next()) {
            response.setStatus(404);
            return { error: 'Application service not found: ' + serviceName };
        }
    }

    var mgr = new SNC.BusinessServiceManager();
    var entryRegistered = false;
    var entrySysId = '';

    if (registerEntry) {
        var m2m = new GlideRecord('sa_m2m_service_entry_point');
        m2m.addQuery('cmdb_ci_service', svc.getUniqueValue());
        m2m.setLimit(1);
        m2m.query();
        if (m2m.next()) {
            entryRegistered = true;
            entrySysId = m2m.cmdb_ci_endpoint.toString();
        } else {
            var rel = new GlideRecord('cmdb_rel_ci');
            rel.addQuery('parent', svc.getUniqueValue());
            rel.addQuery('type.name', 'Depends on::Used by');
            rel.setLimit(1);
            rel.query();
            if (!rel.next()) {
                response.setStatus(400);
                return {
                    error: 'No entry point (Depends on::Used by) for application service',
                    service: svc.getValue('name'),
                    service_sys_id: svc.getUniqueValue()
                };
            }
            entrySysId = rel.getValue('child');
            mgr.addEntryPoint(svc.getUniqueValue(), entrySysId);
            entryRegistered = true;
        }
    }

    mgr.startDiscovery(svc.getUniqueValue());
    svc.get(svc.getUniqueValue());

    response.setStatus(202);
    return {
        operation: 'service_mapping_discover',
        service: svc.getValue('name'),
        service_sys_id: svc.getUniqueValue(),
        entry_point_sys_id: entrySysId,
        entry_point_registered: entryRegistered,
        process_status: svc.getValue('process_status'),
        process_status_display: svc.process_status.getDisplayValue()
    };
})(request, response);
