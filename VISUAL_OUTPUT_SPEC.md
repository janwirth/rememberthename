# rememberthename - Unified Visual Output Spec

This spec defines one unified output shape across all resolution methods.

Methods covered:

- `shallow`
- `step`
- `deep`
- `all`

The visual/reporting format MUST stay identical across methods.
Only the resolved data volume changes by method.

## 1) Required Outputs

Every run can produce two visual outputs:

- terminal summary (Unicode tree)
- full tracks export (CSV)

## 2) Full Tracks CSV

Purpose:

- export all resolved tracks in a flat, portable format

Rules:

- output contains every resolved track (`all tracks`)
- deterministic ordering (same input + method => same row order)
- include header row
- UTF-8 text, comma-separated values, standard CSV escaping

Required columns:

- `title`
- `artist`
- `service`
- `source_id`

## 3) Terminal Output (Unicode Tree)

Purpose:

- quick human scan in terminal
- stable shape across all methods

Rendering rule:

- Unicode tree style only (`├──`, `└──`, `│`)
- do not use ASCII fallback connectors (`|-`, ``-`)

Top-level sections in this exact order:

1. `lists`
2. `all tracks`

### 3.1 `lists` section

For each resolved list, render:

- list title
- track count
- first 3 tracks in list order

Format:

- `list node`: `<title> (<track_count>)`
- `track preview node`: `<track_title> - <artist>`

If a list has fewer than 3 tracks:

- render only available tracks

### 3.2 `all tracks` section

Render:

- first 3 tracks from global track ordering
- ellipsis separator line
- last 3 tracks from global track ordering

Rules:

- if total tracks <= 6, show all tracks once (no duplicated rows)
- ellipsis line is exactly `...` and only shown when omitted middle exists
- track row format: `<track_title> - <artist> [<service>]`

## 4) Canonical Terminal Template

```text
lists
├── <list title A> (<count>)
│   ├── <track 1> - <artist>
│   ├── <track 2> - <artist>
│   └── <track 3> - <artist>
└── <list title B> (<count>)
    ├── <track 1> - <artist>
    ├── <track 2> - <artist>
    └── <track 3> - <artist>

all tracks
├── first 3
│   ├── <title> - <artist> [<service>]
│   ├── <title> - <artist> [<service>]
│   └── <title> - <artist> [<service>]
├── ...
└── last 3
    ├── <title> - <artist> [<service>]
    ├── <title> - <artist> [<service>]
    └── <title> - <artist> [<service>]
```

## 5) Compliance Notes

- All methods MUST use this exact section structure and labels.
- CSV export MUST always represent all resolved tracks.
- Terminal output is a summary view, not a full dump.
  Normalization rules:
- trailing `/` means folder node
- no trailing `/` means file/leaf node
- indentation depth defines parent-child nesting
- output renderer still MUST emit terminal view in Unicode tree format defined above
