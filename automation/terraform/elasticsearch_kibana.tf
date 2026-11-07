# Elasticsearch/Kibana objects discovered directly from the declarative
# specs in specifications/elasticsearch/**, via the
# elastic/elasticstack provider. This is the Terraform counterpart to
# automation/ansible/scripts/elasticsearch/init-index.sh -- both read the
# exact same files; neither is authoritative over the other, so run
# `terraform import` before the first `apply` to avoid duplicate-create
# races against objects init-index.sh already created live.
#
# Every resource here relies on the naming convention in
# specifications/elasticsearch/docs/Naming_Convention.md: a file's
# basename stem IS the live object's name/ID. That's what lets
# fileset()-driven for_each cover every category with zero per-category
# .tf code -- a new category just needs its files to follow the
# convention, nothing here needs to change.
#
# Deliberately not covered (see tmp/terraform_ansible_learnings.md):
#   - *.dashboard.json -- no live automation reference at all today
#     (hand-built in Kibana, exported here only for backup), so bringing
#     it under Terraform is a new capability, not a replacement of
#     existing custom software like the six types below are.
#   - batch-metrics/ -- deprecated, not run by init-index.sh.

locals {
  es_specs_dir = "${path.module}/../../specifications/elasticsearch"

  # config/batch-metrics/ is deprecated (see its own README.md) and not
  # run by init-index.sh's main sequence -- it has its own standalone
  # init-index-batch-metrics.sh, never invoked automatically. Excluded
  # from every glob below so these globs don't try to manage objects
  # that were never created, per the exemption documented in
  # specifications/elasticsearch/docs/Naming_Convention.md.

  # --- ILM policies --------------------------------------------------
  ilm_files = [for f in fileset(local.es_specs_dir, "**/*.ilm.json") : f if !startswith(f, "batch-metrics/")]
  ilm_policies = {
    for f in local.ilm_files :
    trimsuffix(basename(f), ".ilm.json") => jsondecode(file("${local.es_specs_dir}/${f}")).policy.phases
  }

  # --- Index templates -------------------------------------------------
  template_files = [for f in fileset(local.es_specs_dir, "**/*.template.json") : f if !startswith(f, "batch-metrics/")]
  index_templates = {
    for f in local.template_files :
    trimsuffix(basename(f), ".template.json") => jsondecode(file("${local.es_specs_dir}/${f}"))
  }

  # --- Ingest pipelines ------------------------------------------------
  pipeline_files = [for f in fileset(local.es_specs_dir, "**/*.pipeline.json") : f if !startswith(f, "batch-metrics/")]
  ingest_pipelines = {
    for f in local.pipeline_files :
    trimsuffix(basename(f), ".pipeline.json") => jsondecode(file("${local.es_specs_dir}/${f}"))
  }

  # --- Transforms --------------------------------------------------------
  transform_files = [for f in fileset(local.es_specs_dir, "**/*.transform.json") : f if !startswith(f, "batch-metrics/")]
  transforms = {
    for f in local.transform_files :
    trimsuffix(basename(f), ".transform.json") => jsondecode(file("${local.es_specs_dir}/${f}"))
  }

  # --- Kibana data views -------------------------------------------------
  dataview_files = [for f in fileset(local.es_specs_dir, "**/*.dataview.json") : f if !startswith(f, "batch-metrics/")]
  dataviews = {
    for f in local.dataview_files :
    jsondecode(file("${local.es_specs_dir}/${f}")).data_view.id => jsondecode(file("${local.es_specs_dir}/${f}")).data_view
  }

  # --- Kibana saved searches ----------------------------------------------
  # *.search.json files already have filename stem == live saved-object
  # id (the Naming_Convention.md audit renamed every one that didn't),
  # so this is fileset()-driven like everything else above -- no
  # separate id map needed. Each file already carries its own top-level
  # "attributes" key (and "references" when the search needs one) in
  # exactly the shape a saved-object envelope expects; this just adds
  # the "type"/"id" the envelope needs on top.
  search_files = [for f in fileset(local.es_specs_dir, "**/*.search.json") : f if !startswith(f, "batch-metrics/")]
  saved_searches = {
    for f in local.search_files :
    trimsuffix(basename(f), ".search.json") => jsondecode(file("${local.es_specs_dir}/${f}"))
  }
}

# ---------------------------------------------------------------------------
# ILM policies
#
# Action set below is exactly what's used across every *.ilm.json file in
# this repo today (rollover/forcemerge/set_priority/downsample in hot,
# downsample/set_priority/forcemerge in warm, downsample/set_priority in
# cold, delete in delete) -- not the full ILM action surface. Adding a
# phase/action combination this repo doesn't use yet means extending the
# dynamic blocks below, same as adding support for a brand new resource
# type would.
# ---------------------------------------------------------------------------
resource "elasticstack_elasticsearch_index_lifecycle" "policy" {
  for_each = local.ilm_policies
  name     = each.key

  dynamic "hot" {
    for_each = try([each.value.hot], [])
    content {
      min_age = try(hot.value.min_age, null)

      dynamic "rollover" {
        for_each = try([hot.value.actions.rollover], [])
        content {
          max_age  = try(rollover.value.max_age, null)
          max_size = try(rollover.value.max_size, null)
          max_docs = try(rollover.value.max_docs, null)
        }
      }
      dynamic "forcemerge" {
        for_each = try([hot.value.actions.forcemerge], [])
        content {
          max_num_segments = try(forcemerge.value.max_num_segments, null)
          index_codec      = try(forcemerge.value.index_codec, null)
        }
      }
      dynamic "set_priority" {
        for_each = try([hot.value.actions.set_priority], [])
        content {
          priority = try(set_priority.value.priority, null)
        }
      }
      dynamic "downsample" {
        for_each = try([hot.value.actions.downsample], [])
        content {
          fixed_interval = try(downsample.value.fixed_interval, null)
        }
      }
    }
  }

  dynamic "warm" {
    for_each = try([each.value.warm], [])
    content {
      min_age = try(warm.value.min_age, null)

      dynamic "forcemerge" {
        for_each = try([warm.value.actions.forcemerge], [])
        content {
          max_num_segments = try(forcemerge.value.max_num_segments, null)
          index_codec      = try(forcemerge.value.index_codec, null)
        }
      }
      dynamic "set_priority" {
        for_each = try([warm.value.actions.set_priority], [])
        content {
          priority = try(set_priority.value.priority, null)
        }
      }
      dynamic "downsample" {
        for_each = try([warm.value.actions.downsample], [])
        content {
          fixed_interval = try(downsample.value.fixed_interval, null)
        }
      }
    }
  }

  dynamic "cold" {
    for_each = try([each.value.cold], [])
    content {
      min_age = try(cold.value.min_age, null)

      dynamic "set_priority" {
        for_each = try([cold.value.actions.set_priority], [])
        content {
          priority = try(set_priority.value.priority, null)
        }
      }
      dynamic "downsample" {
        for_each = try([cold.value.actions.downsample], [])
        content {
          fixed_interval = try(downsample.value.fixed_interval, null)
        }
      }
    }
  }

  dynamic "delete" {
    for_each = try([each.value.delete], [])
    content {
      min_age = try(delete.value.min_age, null)

      # Every *.ilm.json file's delete action is bare `{}` -- Elasticsearch
      # itself fills in delete_searchable_snapshot: true as its own default
      # and returns that on GET, so set it explicitly here to match what's
      # actually live rather than leaving it unset (which plans a diff).
      dynamic "delete" {
        for_each = try([delete.value.actions.delete], [])
        content {
          delete_searchable_snapshot = try(delete.value.delete_searchable_snapshot, true)
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Index templates
# ---------------------------------------------------------------------------
resource "elasticstack_elasticsearch_index_template" "template" {
  for_each       = local.index_templates
  name           = each.key
  index_patterns = each.value.index_patterns
  priority       = try(each.value.priority, null)

  dynamic "data_stream" {
    for_each = try([each.value.data_stream], [])
    content {}
  }

  template {
    settings = jsonencode(try(each.value.template.settings, {}))
    mappings = jsonencode(try(each.value.template.mappings, {}))
  }
}

# ---------------------------------------------------------------------------
# Ingest pipelines
# ---------------------------------------------------------------------------
resource "elasticstack_elasticsearch_ingest_pipeline" "pipeline" {
  for_each    = local.ingest_pipelines
  name        = each.key
  description = try(each.value.description, null)
  processors  = [for p in each.value.processors : jsonencode(p)]
  on_failure  = try([for p in each.value.on_failure : jsonencode(p)], null)
}

# ---------------------------------------------------------------------------
# Transforms
# ---------------------------------------------------------------------------
resource "elasticstack_elasticsearch_transform" "transform" {
  for_each    = local.transforms
  name        = each.key
  description = try(each.value.description, null)
  frequency   = try(each.value.frequency, null)

  # Defaults to false (stopped) when omitted -- every transform in this
  # repo is started right after creation by init-index.sh, so explicitly
  # keep it enabled rather than let a plan/apply stop a running transform.
  enabled = true

  max_page_search_size = try(each.value.settings.max_page_search_size, null)

  source {
    indices = each.value.source.index
    query   = try(jsonencode(each.value.source.query), null)
  }

  destination {
    index = each.value.dest.index
  }

  dynamic "sync" {
    for_each = try([each.value.sync], [])
    content {
      time {
        field = try(sync.value.time.field, null)
        delay = try(sync.value.time.delay, null)
      }
    }
  }

  pivot = jsonencode(each.value.pivot)
}

# ---------------------------------------------------------------------------
# Kibana data views
# ---------------------------------------------------------------------------
resource "elasticstack_kibana_data_view" "view" {
  for_each = local.dataviews

  data_view = {
    id              = each.value.id
    title           = each.value.title
    name            = try(each.value.name, null)
    time_field_name = try(each.value.timeFieldName, null)
    allow_no_index  = try(each.value.allowNoIndex, null)

    source_filters = try(
      [for sf in each.value.sourceFilters : sf.value],
      null
    )

    # Two raw shapes exist across these files: newer ones write fieldAttrs
    # directly (already the right shape); older ones write a more verbose
    # fields map (name/type/customLabel) -- no file has both, so a plain
    # merge is enough to normalize either into field_attrs.
    field_attrs = {
      for fname, fattr in merge(try(each.value.fieldAttrs, {}), try(each.value.fields, {})) :
      fname => { custom_label = try(fattr.customLabel, null) }
      if try(fattr.customLabel, null) != null
    }

    field_formats = {
      for fname, ff in try(each.value.fieldFormats, {}) :
      fname => {
        id = ff.id
        params = try({
          pattern       = try(ff.params.pattern, null)
          input_format  = try(ff.params.inputFormat, null)
          output_format = try(ff.params.outputFormat, null)
        }, null)
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Kibana saved searches
#
# No native resource wraps Kibana's per-type saved-object endpoint (the
# one init-index.sh calls directly: POST /api/saved_objects/search/<id>)
# -- only the generic bulk _import API, via this resource. That API's
# own "id" attribute is just a generated id for the import *call*, not
# the saved object's id, so there's nothing stable to `terraform import`
# against the way the other resources in this file have. It doesn't
# need one either: overwrite=true makes every apply idempotent against
# whatever already exists live (same semantic as init-index.sh's own
# ?overwrite=true), so the first apply here safely reconciles with
# objects init-index.sh already created instead of erroring as a
# duplicate create.
# ---------------------------------------------------------------------------
resource "elasticstack_kibana_import_saved_objects" "search" {
  for_each  = local.saved_searches
  overwrite = true

  file_contents = jsonencode({
    type       = "search"
    id         = each.key
    attributes = each.value.attributes
    references = try(each.value.references, [])
  })
}
