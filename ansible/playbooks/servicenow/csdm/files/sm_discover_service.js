(function process(/*RESTAPIRequest*/ request, /*RESTAPIResponse*/ response) {
    var data = (request.body && request.body.data) ? request.body.data : (request.body || {});
    var serviceSysId = data.service_sys_id || request.queryParams.service_sys_id;
    var serviceName = data.service_name || request.queryParams.service_name;
    var registerEntry = data.register_entry_point !== false;
    var midServerName = data.mid_server_name || '';

    if (!serviceSysId && !serviceName) {
        response.setStatus(400);
        return {
            error: 'Provide service_name or service_sys_id',
            example: { service_name: 'Example Application Service', mid_server_name: 'mid-example' }
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
    var entryCreated = false;
    var midAssigned = false;

    if (midServerName) {
        midAssigned = assignMidServer(svc, midServerName);
    }

    if (registerEntry) {
        var m2m = new GlideRecord('sa_m2m_service_entry_point');
        m2m.addQuery('cmdb_ci_service', svc.getUniqueValue());
        m2m.setLimit(1);
        m2m.query();
        if (m2m.next()) {
            entryRegistered = true;
            entrySysId = m2m.cmdb_ci_endpoint.toString();
        } else {
            var resolved = resolveSmEntryPoint(svc.getUniqueValue());
            if (!resolved.sysId) {
                response.setStatus(400);
                return {
                    error: resolved.error || 'Could not resolve Service Mapping entry point',
                    service: svc.getValue('name'),
                    service_sys_id: svc.getUniqueValue(),
                    hint: 'Ensure Depends on::Used by links to cmdb_ci_endpoint, cmdb_ci_linux_server, or cmdb_ci_ip_service with host set'
                };
            }
            entrySysId = resolved.sysId;
            entryCreated = resolved.created;
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
        entry_point_created: entryCreated,
        entry_point_registered: entryRegistered,
        mid_assigned: midAssigned,
        process_status: svc.getValue('process_status'),
        process_status_display: svc.process_status.getDisplayValue(),
        service_status: svc.getValue('service_status'),
        service_status_display: svc.service_status.getDisplayValue()
    };

    function assignMidServer(serviceGr, midName) {
        var mid = new GlideRecord('ecc_agent');
        mid.addQuery('name', midName);
        mid.addQuery('status', 'Up');
        mid.query();
        if (!mid.next()) {
            return false;
        }
        if (serviceGr.isValidField('mid_server') && !serviceGr.mid_server.nil()) {
            return serviceGr.mid_server.toString() === mid.getUniqueValue();
        }
        return true;
    }

    function resolveSmEntryPoint(serviceId) {
        var endpointCandidates = [];
        var linuxCandidates = [];
        var ipCandidates = [];
        var rel = new GlideRecord('cmdb_rel_ci');
        rel.addQuery('parent', serviceId);
        rel.addQuery('type.name', 'Depends on::Used by');
        rel.query();
        while (rel.next()) {
            var childId = rel.getValue('child');
            var childGr = new GlideRecord('cmdb_ci');
            if (!childGr.get(childId)) {
                continue;
            }
            var cls = childGr.getRecordClassName();
            if (cls === 'cmdb_ci_endpoint') {
                ensureEndpointHost(childGr);
                endpointCandidates.push({ sysId: childId, created: false, cls: cls });
            } else if (cls === 'cmdb_ci_linux_server') {
                linuxCandidates.push({ sysId: childId, gr: childGr, cls: cls });
            } else if (cls === 'cmdb_ci_ip_service') {
                ipCandidates.push({ sysId: childId, gr: childGr, cls: cls });
            }
        }
        if (endpointCandidates.length > 0) {
            endpointCandidates.sort(function(a, b) {
                return endpointPriority(a.sysId) - endpointPriority(b.sysId);
            });
            return endpointCandidates[0];
        }
        if (linuxCandidates.length > 0) {
            var hostEp = ensureHostEndpoint(linuxCandidates[0].gr);
            if (hostEp) {
                return { sysId: hostEp, created: true, cls: 'cmdb_ci_linux_server' };
            }
        }
        for (var i = 0; i < ipCandidates.length; i++) {
            var ipEp = ensureEndpointFromIpService(ipCandidates[i].gr);
            if (ipEp && ipEp.sysId) {
                return { sysId: ipEp.sysId, created: ipEp.created, cls: 'cmdb_ci_ip_service' };
            }
        }
        return { sysId: '', error: 'No Depends on::Used by entry point found for application service' };
    }

    function endpointPriority(epSysId) {
        var ep = new GlideRecord('cmdb_ci_endpoint');
        if (!ep.get(epSysId)) {
            return 2;
        }
        var desc = (ep.getValue('short_description') || '').toLowerCase();
        if (desc.indexOf('sm primary') >= 0) {
            return 0;
        }
        return 1;
    }

    function ensureHostEndpoint(hostGr) {
        var epName = 'SM Entry - ' + hostGr.getValue('name');
        var ep = new GlideRecord('cmdb_ci_endpoint');
        ep.addQuery('name', epName);
        ep.query();
        if (!ep.next()) {
            ep.initialize();
            ep.name = epName;
            ep.host = hostGr.getUniqueValue();
            ep.operational_status = 1;
            ep.insert();
        }
        ensureRunsOn(ep.getUniqueValue(), hostGr.getUniqueValue());
        return ep.getUniqueValue();
    }

    function ensureEndpointFromIpService(ipGr) {
        var epName = ipGr.getValue('name');
        var ep = new GlideRecord('cmdb_ci_endpoint');
        ep.addQuery('name', epName);
        ep.query();
        var created = false;
        if (!ep.next()) {
            ep.initialize();
            ep.name = epName;
            created = true;
        }
        if (!ep.host.nil()) {
            // already linked
        } else {
            var hostId = inferHostForIpService(ipGr);
            if (hostId) {
                ep.host = hostId;
            }
        }
        if (ipGr.ip_address.nil() === false) {
            ep.ip_address = ipGr.getValue('ip_address');
        }
        if (ipGr.port.nil() === false) {
            ep.port = ipGr.getValue('port');
        }
        ep.operational_status = 1;
        if (created) {
            ep.insert();
        } else {
            ep.update();
        }
        if (!ep.host.nil()) {
            ensureRunsOn(ep.getUniqueValue(), ep.host.toString());
        }
        return { sysId: ep.getUniqueValue(), created: created };
    }

    function inferHostForIpService(ipGr) {
        if (!ipGr.host.nil()) {
            return ipGr.getValue('host');
        }
        var name = ipGr.getValue('name') || '';
        var hostPart = name.split(':')[0] || '';
        if (!hostPart) {
            return '';
        }
        var host = new GlideRecord('cmdb_ci_linux_server');
        host.addQuery('name', hostPart);
        host.query();
        if (host.next()) {
            return host.getUniqueValue();
        }
        host = new GlideRecord('cmdb_ci_linux_server');
        host.addQuery('name', hostPart.toLowerCase());
        host.query();
        if (host.next()) {
            return host.getUniqueValue();
        }
        return '';
    }

    function ensureEndpointHost(epGr) {
        if (!epGr.host.nil()) {
            ensureRunsOn(epGr.getUniqueValue(), epGr.host.toString());
        }
    }

    function ensureRunsOn(childId, parentHostId) {
        var runsType = new GlideRecord('cmdb_rel_type');
        runsType.addQuery('name', 'Runs on::Runs');
        runsType.query();
        if (!runsType.next()) {
            return;
        }
        var rel = new GlideRecord('cmdb_rel_ci');
        rel.addQuery('parent', childId);
        rel.addQuery('child', parentHostId);
        rel.addQuery('type', runsType.getUniqueValue());
        rel.query();
        if (rel.next()) {
            return;
        }
        rel.initialize();
        rel.parent = childId;
        rel.child = parentHostId;
        rel.type = runsType.getUniqueValue();
        rel.insert();
    }
})(request, response);
