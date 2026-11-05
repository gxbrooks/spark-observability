(function process(/*RESTAPIRequest*/ request, /*RESTAPIResponse*/ response) {
    var data = (request.body && request.body.data) ? request.body.data : {};
    var ipAddress = data.ip_address || data.ip || request.queryParams.ip_address;
    var midServer = data.mid_server || data.mid_server_name || request.queryParams.mid_server;

    if (!ipAddress) {
        response.setStatus(400);
        return {
            error: 'Provide ip_address (single host or CIDR as supported by the instance Quick Discovery UI)',
            example: { ip_address: '192.168.1.3', mid_server: 'mid-brooks-lab3' }
        };
    }

    var d = new global.Discovery();
    var statusId = midServer ? d.discoveryFromIP(ipAddress, midServer) : d.discoveryFromIP(ipAddress);
    if (!statusId) {
        response.setStatus(500);
        return {
            error: 'discoveryFromIP returned no status id — verify MID is Up and can reach the target',
            ip_address: ipAddress,
            mid_server: midServer || '(auto)'
        };
    }

    var statusGr = new GlideRecord('discovery_status');
    statusGr.get(statusId);
    response.setStatus(202);
    return {
        operation: 'quick',
        discovery_status_sys_id: statusId,
        discovery_status_number: statusGr.getValue('number'),
        ip_address: ipAddress,
        mid_server: midServer || '(auto)'
    };
})(request, response);
