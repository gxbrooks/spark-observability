(function process(/*RESTAPIRequest*/ request, /*RESTAPIResponse*/ response) {
    var data = (request.body && request.body.data) ? request.body.data : (request.body || {});
    var categories = data.categories || [];

    if (!categories || !categories.length) {
        response.setStatus(400);
        return { error: 'categories array required (name and tag_key per entry)' };
    }

    var results = [];

    try {
        for (var i = 0; i < categories.length; i++) {
            var spec = categories[i];
            var catName = spec.name;
            var tagKey = spec.tag_key;
            if (!catName || !tagKey) {
                results.push({
                    name: catName || '',
                    tag_key: tagKey || '',
                    status: 'error',
                    detail: 'name and tag_key required'
                });
                continue;
            }

            var catGr = new GlideRecord('svc_tag_categories');
            catGr.addQuery('name', catName);
            catGr.setWorkflow(false);
            catGr.query();
            var createdCategory = false;
            if (!catGr.next()) {
                catGr.initialize();
                catGr.name = catName;
                catGr.insert();
                createdCategory = true;
            }
            var catSysId = catGr.getUniqueValue();

            var nameGr = new GlideRecord('svc_tag_names');
            nameGr.addQuery('category', catSysId);
            nameGr.addQuery('name', tagKey);
            nameGr.setWorkflow(false);
            nameGr.query();
            var createdKey = false;
            if (!nameGr.next()) {
                nameGr.initialize();
                nameGr.category = catSysId;
                nameGr.name = tagKey;
                nameGr.insert();
                createdKey = true;
            }

            results.push({
                name: catName,
                tag_key: tagKey,
                category_sys_id: catSysId,
                status: (createdCategory || createdKey) ? 'created' : 'present',
                created_category: createdCategory,
                created_tag_key: createdKey
            });
        }
    } catch (e) {
        response.setStatus(500);
        return {
            error: e.message || String(e),
            categories: categories
        };
    }

    response.setStatus(200);
    return {
        operation: 'service_mapping_ensure_tag_categories',
        categories: results
    };
})(request, response);
