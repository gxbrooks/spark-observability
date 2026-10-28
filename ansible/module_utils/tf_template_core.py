"""Renderer for the Terraform templatefile() syntax subset used by this project.

Exists so the same *.json.j2 / *.yaml.j2 representation files under
observability/ and servicenow/ can be rendered identically by Ansible (via
this module) and by Terraform (via the built-in templatefile() function)
once the Terraform side exists. Do not add syntax Terraform's templatefile()
does not itself support -- the point is that both engines read one file.

Supported subset (matches actual usage in this repo, nothing more):
  ${identifier}                      -- variable substitution, undefined is
                                         a hard error (matches Terraform's
                                         templatefile() behavior: every
                                         referenced variable must be supplied).
  %{ for item in listname }...%{ endfor }
  %{ for i, item in listname }...%{ endfor }
                                         -- iterate a list of dicts/strings
                                         passed in the vars map (always a
                                         variable -- no inline list/object
                                         literals; put that data in the
                                         caller's vars instead); dotted
                                         attribute access (item.key) is
                                         supported inside the loop body.
  %{ if i > 0 }...%{ endif }            -- only this exact comparison (an
                                         index variable against the literal
                                         0), for the "comma before every
                                         item but the first" JSON-array
                                         pattern. Not a general expression
                                         evaluator.

Not supported (none of the converted files need it): any other %{ if }
condition, nested loops, inline list/object literals in %{ for }, HCL
function calls, string escapes beyond what's already valid JSON/YAML text.
If a new file needs one of those, extend this module deliberately -- don't
silently reach for Jinja2.
"""
from __future__ import annotations

import re

_VAR_RE = re.compile(r"\$\{\s*([A-Za-z_][A-Za-z0-9_.]*)\s*\}")
_FOR_RE = re.compile(
    r"%\{\s*for\s+(?:([A-Za-z_][A-Za-z0-9_]*)\s*,\s*)?([A-Za-z_][A-Za-z0-9_]*)\s+in\s+([A-Za-z_][A-Za-z0-9_]*)\s*\}"
    r"(.*?)"
    r"%\{\s*endfor\s*\}",
    re.DOTALL,
)
_IF_GT_ZERO_RE = re.compile(
    r"%\{\s*if\s+([A-Za-z_][A-Za-z0-9_]*)\s*>\s*0\s*\}(.*?)%\{\s*endif\s*\}",
    re.DOTALL,
)


class TfTemplateError(Exception):
    pass


def _resolve_dotted(name, scope):
    parts = name.split(".")
    value = scope
    for i, part in enumerate(parts):
        if isinstance(value, dict):
            if part not in value:
                raise TfTemplateError(
                    "undefined variable '%s' (stopped at '%s')" % (name, ".".join(parts[: i + 1]))
                )
            value = value[part]
        else:
            raise TfTemplateError(
                "cannot resolve '%s': '%s' is not a mapping" % (name, ".".join(parts[:i]))
            )
    return value


def _substitute_vars(text, scope):
    def repl(m):
        name = m.group(1)
        value = _resolve_dotted(name, scope)
        if isinstance(value, bool):
            return "true" if value else "false"
        return str(value)

    return _VAR_RE.sub(repl, text)


def _expand_if_gt_zero(text, scope):
    def repl(m):
        var_name, body = m.groups()
        value = scope.get(var_name)
        if not isinstance(value, int) or isinstance(value, bool):
            raise TfTemplateError(
                "%%{ if %s > 0 } needs an int in scope, got %r" % (var_name, value)
            )
        return _substitute_vars(body, scope) if value > 0 else ""

    return _IF_GT_ZERO_RE.sub(repl, text)


def _expand_for_loops(text, scope):
    def repl(m):
        index_name, item_name, list_name, body = m.groups()
        if list_name not in scope:
            raise TfTemplateError("undefined list variable '%s' in %%{ for }" % list_name)
        items = scope[list_name]
        out = []
        for idx, item in enumerate(items):
            inner_scope = dict(scope)
            inner_scope[item_name] = item
            if index_name:
                inner_scope[index_name] = idx
            body_rendered = _expand_if_gt_zero(body, inner_scope)
            # a nested %{ for } would need recursion here; none of the
            # converted files use one, so it's intentionally unsupported.
            out.append(_substitute_vars(body_rendered, inner_scope))
        return "".join(out)

    return _FOR_RE.sub(repl, text)


def render(text, variables):
    """Render `text` (the template file's contents) against `variables`.

    Mirrors terraform templatefile(path, variables): every ${...} reference
    must be present in `variables` (or reachable via dotted lookup through
    it), or rendering fails loudly instead of silently emitting an empty
    string the way Jinja2's default undefined behavior would.
    """
    scope = dict(variables or {})
    text = _expand_for_loops(text, scope)
    text = _substitute_vars(text, scope)
    return text
