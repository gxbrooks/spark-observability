"""action: tf_template

Drop-in replacement for ansible.builtin.template(src, dest, mode) on
representation files that must also be readable by Terraform's built-in
templatefile() function. Renders with the small Terraform-syntax subset in
module_utils/tf_template_core.py instead of Jinja2 -- see that file for
exactly what's supported.

Scoped to this project's actual usage: every current call site renders on
the controller (delegate_to: localhost) to a local path, so this writes
dest directly with local file I/O rather than reimplementing template's
remote-copy machinery. If a future call site needs a remote dest, extend
this rather than assuming it already works.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "module_utils"))
from tf_template_core import TfTemplateError, render  # noqa: E402

from ansible.errors import AnsibleActionFail
from ansible.plugins.action import ActionBase


class ActionModule(ActionBase):
    TRANSFERS_FILES = False

    def run(self, tmp=None, task_vars=None):
        result = super().run(tmp, task_vars)
        task_vars = task_vars or {}

        src = self._task.args.get("src")
        dest = self._task.args.get("dest")
        mode = self._task.args.get("mode")

        if not src or not dest:
            raise AnsibleActionFail("tf_template: 'src' and 'dest' are required")

        src_path = self._loader.path_dwim_relative(
            self._loader.get_basedir(), "templates", src
        )
        if not os.path.exists(src_path):
            src_path = self._loader.path_dwim(src)
        if not os.path.exists(src_path):
            raise AnsibleActionFail("tf_template: src not found: %s" % src)

        with open(src_path, "r", encoding="utf-8") as f:
            src_text = f.read()

        # Task-level `vars:` land in task_vars unresolved -- a common
        # pattern here is `vars: {DT_API_URL: "{{ dt_api_url_resolved }}"}`,
        # a Jinja2 expression string, not yet evaluated by the time an
        # action plugin sees it. ansible.builtin.template gets this for
        # free because it renders through Ansible's own Jinja2 Templar,
        # whose variable lookups recursively resolve nested expressions;
        # our renderer doesn't go through Jinja2 at all, so without this
        # step `${DT_API_URL}` would substitute the literal unresolved
        # string instead of its value. Resolve just the task's own `vars:`
        # (not the whole task_vars scope -- that's enormous and the rest
        # is already-resolved facts) through the templar, then layer the
        # resolved values over task_vars for the renderer's scope.
        self._templar.available_variables = task_vars
        local_vars = getattr(self._task, "vars", None) or {}
        resolved_overrides = self._templar.template(local_vars, fail_on_undefined=False)
        scope = dict(task_vars)
        scope.update(resolved_overrides)

        try:
            rendered = render(src_text, scope)
        except TfTemplateError as exc:
            raise AnsibleActionFail("tf_template: %s" % exc)

        existing = None
        if os.path.exists(dest):
            with open(dest, "r", encoding="utf-8") as f:
                existing = f.read()

        changed = existing != rendered
        if changed and not self._play_context.check_mode:
            with open(dest, "w", encoding="utf-8") as f:
                f.write(rendered)
            if mode is not None:
                os.chmod(dest, int(str(mode), 8))

        result["changed"] = changed
        result["dest"] = dest
        return result
