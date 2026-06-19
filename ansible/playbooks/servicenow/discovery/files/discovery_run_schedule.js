(function process(/*RESTAPIRequest*/ request, /*RESTAPIResponse*/ response) {
    var data = (request.body && request.body.data) ? request.body.data : {};
    var scheduleName = data.schedule_name || request.queryParams.schedule_name;
    var scheduleSysId = data.schedule_sys_id || request.queryParams.schedule_sys_id;

    if (!scheduleName && !scheduleSysId) {
        response.setStatus(400);
        return {
            error: 'Provide schedule_name or schedule_sys_id',
            example: { schedule_name: 'Brooks Lab CI Discovery' }
        };
    }

    var gr = new GlideRecord('discovery_schedule');
    if (scheduleSysId) {
        if (!gr.get(scheduleSysId)) {
            response.setStatus(404);
            return { error: 'Schedule not found: ' + scheduleSysId };
        }
    } else {
        gr.addQuery('name', scheduleName);
        gr.query();
        if (!gr.next()) {
            response.setStatus(404);
            return { error: 'Schedule not found: ' + scheduleName };
        }
    }

    var d = new global.Discovery();
    var statusId = d.discoverNow(gr);
    if (!statusId) {
        response.setStatus(500);
        return {
            error: 'discoverNow returned no status id',
            schedule: gr.getValue('name'),
            schedule_sys_id: gr.getUniqueValue()
        };
    }

    var statusGr = new GlideRecord('discovery_status');
    statusGr.get(statusId);
    response.setStatus(202);
    return {
        operation: 'schedule',
        discovery_status_sys_id: statusId,
        discovery_status_number: statusGr.getValue('number'),
        schedule: gr.getValue('name'),
        schedule_sys_id: gr.getUniqueValue()
    };
})(request, response);
