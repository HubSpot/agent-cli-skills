# JSON reshape patterns

All examples assume JSONL input from `hubspot objects list|search|get`. Output always nests under `.properties`; `--properties a,b` limits the field set returned.

These are the reshapes you actually use. Skip anything you can derive.

---

## Read → update

```bash
hubspot objects search --type contacts --filter "industry=Tech" \
| jq -c '{id, properties:{lifecyclestage:"marketingqualifiedlead"}}' \
| hubspot objects update --type contacts
```

## Read → delete

```bash
hubspot objects search --type contacts --filter "!email" \
| jq -c '{id}' \
| hubspot objects delete --type contacts --dry-run
```

## Read → batch get (one call, no xargs)

```bash
hubspot associations list --from companies:67890 --to contacts \
| jq -c '{id}' \
| hubspot objects get --type contacts --properties email,firstname
```

## CSV → upsert

```bash
# external.csv: email,firstname,lastname,company
tail -n +2 external.csv \
| jq -R -c 'split(",") | {idProperty:"email", id:.[0], properties:{firstname:.[1], lastname:.[2], company:.[3]}}' \
| hubspot objects upsert --type contacts --dry-run
```

## Read → association create

```bash
hubspot objects search --type contacts --filter "company~acme" \
| jq -c '{from:("contacts:"+.id), to:"companies:456"}' \
| hubspot associations create
```

## Numeric / regex filtering server-side can't express

```bash
# Companies with revenue > 1M
hubspot objects list --type companies \
| jq -c 'select((.properties.annualrevenue // "0") | tonumber > 1000000)'

# Exclude obvious junk emails (server-side ~ is whole-token only)
hubspot objects list --type contacts \
| jq -c 'select(.properties.email | test("test|noreply|placeholder"; "i") | not)'
```

## Union and de-dupe two searches

```bash
( hubspot objects search --type contacts --filter "lifecyclestage=lead"
  hubspot objects search --type contacts --filter "lifecyclestage=marketingqualifiedlead"
) | jq -s -c 'unique_by(.id)[]'
```

## Frequency table (count by field)

```bash
hubspot objects list --type contacts --properties lifecyclestage \
| jq -r '.properties.lifecyclestage // "(unset)"' \
| sort | uniq -c | sort -rn
```

## Export to CSV / TSV

```bash
hubspot objects list --type contacts --properties email,firstname,lastname \
| jq -r '[.properties.email, .properties.firstname, .properties.lastname] | @csv'
```
