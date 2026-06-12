# Web Search Domain Consumer Contract

This contract defines how downstream Merlin domains may request web-search evidence without coupling provider implementation details into those domains.

## Registration

Downstream consumers opt in by registering their own workspace-bus capability that calls the generic web-search plugin tools. The web-search plugin does not push results into domains automatically.

Consumer registration must declare:

- consumer id
- domain id
- capability address
- required permission scope
- accepted evidence types
- cache policy
- citation/provenance requirements

## Request Shape

```json
{
  "consumer_id": "domain.example",
  "purpose": "evidence_lookup",
  "query": "search terms",
  "allowed_domains": ["example.com"],
  "blocked_domains": [],
  "max_results": 5,
  "extract_top_results": true,
  "freshness_hint": "recent",
  "required_evidence": ["source_url", "title", "snippet", "retrieved_at"]
}
```

Rules:

- `consumer_id` is required.
- `purpose` must describe the downstream evidence use.
- `query` is required and must be user/workflow derived.
- `allowed_domains` and `blocked_domains` are optional filters.
- `extract_top_results` may request page extraction, but extraction remains bounded by web-search settings.

## Response Shape

```json
{
  "consumer_id": "domain.example",
  "query": "search terms",
  "results": [
    {
      "title": "Result title",
      "url": "https://example.com/page",
      "canonical_url": "https://example.com/page",
      "snippet": "Relevant source text.",
      "provider_id": "wikipedia",
      "rank": 1,
      "score": 92.1,
      "retrieved_at": "2026-06-12T00:00:00Z",
      "extraction": {
        "strategy": "urlsession-html",
        "text": "Extracted bounded text",
        "truncated": false
      }
    }
  ],
  "diagnostics": [
    {
      "provider_id": "wikipedia",
      "state": "ok",
      "message": "Wikipedia returned 1 results",
      "retrieved_at": "2026-06-12T00:00:00Z",
      "source_url": "https://en.wikipedia.org/w/api.php"
    }
  ],
  "cached": false
}
```

## Provenance Requirements

Every consumer-visible evidence item must preserve:

- source URL
- canonical URL
- provider id
- retrieved timestamp
- extraction strategy when extraction is used
- diagnostic state for failed or partial-provider work
- cache status

Consumers must not treat a result as verified evidence unless source URL and retrieved timestamp are present.

## Diagnostics

Consumers must handle all web-search diagnostic states:

- `ok`
- `empty`
- `blocked`
- `bot_policy_blocked`
- `rate_limited`
- `captcha`
- `login_wall`
- `javascript_required`
- `unsupported_content`
- `provider_terms_blocked`
- `parse_failed`
- `timeout`
- `disabled`

Partial success is valid only when failed providers are surfaced in diagnostics.

## Permission Scope

Consumer calls that can reach the network require `externalSideEffect`.

Consumer calls that only read cached results may use `readOnly` if the implementation can prove no provider or extraction request will be issued.

## Cache And Privacy Rules

- Workspace cache is the default behavior.
- Global cache is opt-in and must use provenance-bearing keys.
- Secret-bearing requests or credentialed/private responses must not be cached globally.
- Cache keys must include provider id, query or URL, relevant settings, and result/extraction version.

## Electronics Contract Status

Electronics evidence consumption is intentionally contract-only here. No electronics behavior, schemas, gates, or part-selection rules are wired by this document.

The electronics-specific proposal is documented in `ELECTRONICS_CONSUMER_PROPOSAL.md`.
