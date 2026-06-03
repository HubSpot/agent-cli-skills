# Aggregation Patterns (jq)

Run these after collecting all matching records into a JSONL file with the pagination loop. A bare `search` caps at 100 rows — always paginate before aggregating.

```bash
# general form
bash bulk-operations/resources/pagination-loop.sh <type> /tmp/out.jsonl <props> [extra_flags...]
```

All property values in JSONL output are **strings**. Use `tonumber` for arithmetic and `// 0` / `// null` to handle nulls.

---

## Count by dimension

```bash
bash bulk-operations/resources/pagination-loop.sh deals /tmp/deals.jsonl dealstage

jq -rs '
  group_by(.properties.dealstage)
  | map({stage: .[0].properties.dealstage, count: length})
  | sort_by(-.count)[]
  | "\(.stage)\t\(.count)"' /tmp/deals.jsonl \
| column -t -s$'\t'
```

## Count + sum by dimension

```bash
bash bulk-operations/resources/pagination-loop.sh deals /tmp/deals.jsonl dealstage,amount \
  '--filter' 'hs_is_closed!=true'

jq -rs '
  group_by(.properties.dealstage)
  | map({
      stage: .[0].properties.dealstage,
      count: length,
      total: ([.[].properties.amount | select(. != null) | tonumber] | add // 0 | round)
    })
  | sort_by(-.total)[]
  | "\(.stage)\tcount:\(.count)\tvalue:$\(.total)"' /tmp/deals.jsonl \
| column -t -s$'\t'
```

## Average by dimension

```bash
jq -rs '
  group_by(.properties.dealtype)
  | map(
      . as $group |
      {
        type: ($group[0].properties.dealtype // "unknown"),
        count: ($group | length),
        avg: (
          [ $group[].properties.amount | select(. != null) | tonumber ]
          | if length > 0 then (add / length | round) else 0 end
        )
      }
    )
  | .[]
  | "\(.type)\tcount:\(.count)\tavg:$\(.avg)"' /tmp/deals.jsonl \
| column -t -s$'\t'
```

## Min / max

```bash
jq -rs '
  map(select(.properties.amount != null))
  | {
      max: (max_by(.properties.amount | tonumber)
            | {name: .properties.dealname, amount: (.properties.amount | tonumber)}),
      min: (min_by(.properties.amount | tonumber)
            | {name: .properties.dealname, amount: (.properties.amount | tonumber)})
    }' /tmp/deals.jsonl
```

## Time series — group by month

```bash
bash bulk-operations/resources/pagination-loop.sh deals /tmp/won.jsonl amount,closedate \
  '--filter' 'hs_is_closed_won=true'

jq -rs '
  group_by(.properties.closedate[0:7])
  | map({
      month: .[0].properties.closedate[0:7],
      count: length,
      revenue: ([.[].properties.amount | select(. != null) | tonumber] | add // 0 | round)
    })
  | sort_by(.month)[]
  | "\(.month)\tdeals:\(.count)\trevenue:$\(.revenue)"' /tmp/won.jsonl \
| column -t -s$'\t'
```

## Multi-dimension grouping

```bash
bash bulk-operations/resources/pagination-loop.sh deals /tmp/deals.jsonl \
  dealstage,hubspot_owner_id,amount '--filter' 'hs_is_closed!=true'

jq -rs '
  group_by([.properties.dealstage, .properties.hubspot_owner_id])
  | map({
      stage: .[0].properties.dealstage,
      owner: .[0].properties.hubspot_owner_id,
      count: length,
      total: ([.[].properties.amount | select(. != null) | tonumber] | add // 0 | round)
    })
  | sort_by([.stage, -.total])[]
  | "\(.stage)\towner:\(.owner)\tcount:\(.count)\tvalue:$\(.total)"' \
| column -t -s$'\t'
```

## Records with / without a property set

```bash
jq -rs '
  {
    with_phone:    (map(select(.properties.phone != null and .properties.phone != "")) | length),
    without_phone: (map(select(.properties.phone == null or  .properties.phone == "")) | length)
  }' /tmp/contacts.jsonl
```

## Resolve owner IDs to names

Dump owners once, then join by ID:

```bash
hubspot owners list --format jsonl > /tmp/owners.jsonl

# join when reading back results (two-file jq input)
jq -rs '
  (.[1:][0] | map({(.id): (.firstName + " " + .lastName)}) | add) as $names |
  .[0][] |
  . + {owner_name: ($names[.properties.hubspot_owner_id] // "unknown")}
' /tmp/deals.jsonl /tmp/owners.jsonl
```

Or inline with `--slurpfile` when piping:

```bash
hubspot objects search --type deals --filter "hs_is_closed!=true" \
  --properties dealname,hubspot_owner_id \
| jq -c --slurpfile owners /tmp/owners.jsonl '
    . + {owner_name: (
      ($owners[0][] | select(.id == .properties.hubspot_owner_id)
       | .firstName + " " + .lastName) // "unknown"
    )}'
```
