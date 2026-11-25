# Context map

| File | Contents and shape |
| --- | --- |
| [scope.json](scope.json) | Supplied manifest: `codebases[]` contains repository directories, revision pins, and `in_scope_files`. |
| [entries.json](entries.json) | Document inventory: one object per document, with `id`, workspace-relative `path`, `dimensions`, `description`, `written_for_engagement`, `level`, `visibility`, and `sources[{path, location}]`. |
| [statements.json](statements.json) | Supplied statement registry: `version`, then `files[{path, statements[]}]`. Each statement has `id`, `lines`, `quote`, and `dimensions` with its classifications. |
| [severity-set.json](severity-set.json) | Complete ordered array of severity objects: `identifier`, `display_name`, and `body_markdown`. |

Inventory dimensions are `tf`, `scope`, `known`, and `severity`; an empty array denotes background. The statements file spells `tf` as `true_finding`. A document's `level` is its content level (`platform`, `customer`, `repo`, `engagement`); a statement's per-dimension `level` is its classification. These are separate fields. Classifications apply as described in the [judging guidelines, §2](judging-guidelines.md#2-order-of-authority).

The [source map](source-map.md) links statement IDs to the engagement document, repository documentation, and source comments. Paths inside JSON are relative to the workspace root. All commands below run there.

List documents tagged for a dimension, changing `known` as needed:

```sh
python - <<'PYQUERY'
import json
for entry in json.load(open('context/entries.json')):
    if 'known' in entry['dimensions']:
        print(entry['id'], entry['path'], entry['description'], sep='	')
PYQUERY
```

Retrieve complete statement records by ID, dimension, source path, or text. Set unused filters to `None`; all enabled filters must match. For all known-related records, use `statement_id = None` and `dimension = 'known'`.

```sh
python - <<'PYQUERY'
import json
statement_id, dimension, source, term = 'S1', None, None, None
for file in json.load(open('context/statements.json'))['files']:
    for statement in file['statements']:
        if statement_id and statement['id'] != statement_id:
            continue
        if dimension and dimension not in statement['dimensions']:
            continue
        if source and source != file['path']:
            continue
        if term and term.casefold() not in statement['quote'].casefold():
            continue
        print(json.dumps({'path': file['path'], **statement}, ensure_ascii=False, indent=2))
PYQUERY
```

For text discovery, `rg -n -i 'pattern' context/statements.json` locates matches; the structured query returns their complete records. The [duplication guidance](deduplication-guidelines.md), [finding report standard](finding-report-standard.md), and [root README](../README.md) link the remaining guidance.
