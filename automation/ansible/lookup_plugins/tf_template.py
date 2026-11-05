"""lookup: tf_template
description: Render a file using the Terraform templatefile() syntax subset
  (see module_utils/tf_template_core.py), as a drop-in replacement for
  lookup('template', path) on representation files shared with Terraform.
options:
  _terms:
    description: path(s) to the template file
    required: True
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "module_utils"))
from tf_template_core import render  # noqa: E402

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase


class LookupModule(LookupBase):
    def run(self, terms, variables=None, **kwargs):
        scope = {}
        if variables:
            scope.update(variables)
        scope.update(kwargs)

        results = []
        for term in terms:
            path = self.find_file_in_search_path(variables, "templates", term) or term
            try:
                with open(path, "r", encoding="utf-8") as f:
                    text = f.read()
                results.append(render(text, scope))
            except Exception as exc:  # noqa: BLE001
                raise AnsibleError("tf_template: failed rendering %s: %s" % (path, exc))
        return results
