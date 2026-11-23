# -*- coding: utf-8 -*-
"""Return the running ansible-playbook's parsed CLI arguments.

Used by playbooks/servicenow/common/target.yml to fan a ServiceNow playbook out
to every instance when it is run with ``-e target=all``: each extra instance is
run as a child ``ansible-playbook`` of the same ServiceNow playbook with the same
inventory, extra vars, tags, verbosity and check/diff flags, plus
``-e target=<id>``.

Lookups run in a worker forked from the ansible-playbook controller, so
``ansible.context.CLIARGS``, ``sys.argv`` and the working directory are the
controller's.
"""
from __future__ import annotations

import os
import sys

from ansible import context
from ansible.plugins.lookup import LookupBase

DOCUMENTATION = r"""
name: sn_cli_args
short_description: Parsed ansible-playbook CLI arguments of the current run
description:
  - Returns one dict with python, ansible_playbook, cwd, inventory, extra_vars,
    tags, skip_tags, subset, verbosity, check and diff.
"""


class LookupModule(LookupBase):
    def run(self, terms, variables=None, **kwargs):
        args = context.CLIARGS
        return [{
            "python": sys.executable,
            "ansible_playbook": sys.argv[0],
            "cwd": os.getcwd(),
            "inventory": list(args.get("inventory") or []),
            "extra_vars": list(args.get("extra_vars") or []),
            "tags": [t for t in (args.get("tags") or []) if t != "all"],
            "skip_tags": list(args.get("skip_tags") or []),
            "subset": args.get("subset") or "",
            "verbosity": int(args.get("verbosity") or 0),
            "check": bool(args.get("check")),
            "diff": bool(args.get("diff")),
        }]
