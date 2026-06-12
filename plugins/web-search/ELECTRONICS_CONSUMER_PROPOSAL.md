# Electronics Evidence Consumer Proposal

This proposal applies the generic Web Search Domain Consumer Contract to Merlin's electronics domain. It is a contract proposal only. It does not change electronics behavior, schemas, gates, or part-selection rules.

## Goal

Allow a future electronics workflow to request web-search evidence through the generic web-search plugin when local/catalog evidence is insufficient or when a user explicitly asks for broader source discovery.

The electronics domain remains responsible for deciding whether evidence is acceptable. The web-search plugin only supplies bounded, cited search and extraction results with diagnostics.

## Non-Goals

- No automatic electronics workflow changes in this proposal.
- No changes to component selection, KiCad gates, SPICE gates, fabrication readiness, or completion criteria.
- No substitution of web evidence for required catalog/provider evidence.
- No silent public-web lookup during electronics flows.
- No electronics-specific ranking inside the generic web-search plugin.
- No credential or provider setting owned by the electronics domain.

## Opt-In Registration

A future electronics consumer should register its own bus-facing capability, for example:

```json
{
  "id": "plugin.electronics.web_evidence_lookup",
  "display_name": "Electronics Web Evidence Lookup",
  "kind": "tool",
  "address": {
    "namespace": "plugin.electronics",
    "capability": "web_evidence_lookup"
  },
  "required_permission_scope": "externalSideEffect"
}
```

Registration must remain electronics-plugin scoped. If the electronics plugin is unloaded or absent, this consumer capability must not appear in Merlin's global tool registry or settings UI.

## Request Shape

```json
{
  "consumer_id": "plugin.electronics",
  "purpose": "component_evidence_lookup",
  "query": "LM358 replacement lifecycle manufacturer datasheet",
  "evidence_target": {
    "kind": "component",
    "mpn": "LM358",
    "manufacturer": "Texas Instruments",
    "design_role": "dual op amp"
  },
  "allowed_domains": [
    "ti.com",
    "analog.com",
    "onsemi.com",
    "mouser.com",
    "digikey.com"
  ],
  "blocked_domains": [],
  "max_results": 5,
  "extract_top_results": true,
  "required_evidence": [
    "source_url",
    "canonical_url",
    "provider_id",
    "retrieved_at",
    "title",
    "snippet",
    "diagnostics"
  ]
}
```

## Response Shape

```json
{
  "consumer_id": "plugin.electronics",
  "purpose": "component_evidence_lookup",
  "query": "LM358 replacement lifecycle manufacturer datasheet",
  "evidence_target": {
    "kind": "component",
    "mpn": "LM358",
    "manufacturer": "Texas Instruments",
    "design_role": "dual op amp"
  },
  "results": [
    {
      "title": "LM358 data sheet, product information and support",
      "url": "https://www.ti.com/product/LM358",
      "canonical_url": "https://www.ti.com/product/LM358",
      "snippet": "Manufacturer page excerpt.",
      "provider_id": "brave",
      "rank": 1,
      "score": 94.2,
      "retrieved_at": "2026-06-12T00:00:00Z",
      "extraction": {
        "strategy": "urlsession-html",
        "text": "Bounded extracted text.",
        "truncated": false
      }
    }
  ],
  "diagnostics": [
    {
      "provider_id": "brave",
      "state": "ok",
      "message": "Brave returned 1 results",
      "retrieved_at": "2026-06-12T00:00:00Z",
      "source_url": "https://api.search.brave.com/res/v1/web/search"
    }
  ],
  "cached": false
}
```

## Acceptable Evidence Uses

Future electronics code may use this consumer contract only for supporting evidence such as:

- finding manufacturer pages or datasheets when a part number is already known,
- finding lifecycle or availability context to supplement catalog results,
- finding application notes or reference-design context,
- finding public errata, advisories, or migration notes,
- gathering user-requested background sources for review.

## Prohibited Evidence Uses

Future electronics code must not use web-search evidence to:

- bypass required catalog-provider gates,
- approve a component without required structured catalog/manufacturer evidence,
- mark a design complete,
- replace ERC/DRC/SPICE/fabrication checks,
- select cheaper substitutes without existing electronics approval rules,
- suppress diagnostics from first-party electronics tools.

## Provenance And Citation Requirements

Each electronics-visible evidence item must preserve:

- source URL,
- canonical URL,
- provider id,
- retrieved timestamp,
- extraction strategy if extracted text is included,
- diagnostic state,
- cache status,
- query and evidence target.

An electronics workflow must treat evidence as advisory unless it can map the source to an allowed evidence class. Unknown-source web results must be surfaced to the user or reviewer instead of being silently treated as authoritative.

## Diagnostics Handling

The electronics consumer must pass through web-search diagnostics without rewriting them as electronics success states.

Required handling:

- `ok`: evidence may be considered advisory input.
- `empty`: continue only if the electronics workflow does not require web evidence.
- `blocked`, `bot_policy_blocked`, `captcha`, `login_wall`, `javascript_required`, `provider_terms_blocked`: do not retry automatically; surface as blocked/degraded evidence.
- `rate_limited`, `timeout`: allow normal electronics work to continue only if web evidence is optional.
- `disabled`: report provider configuration status; do not treat as a component-selection failure by itself.

## Permission Scope

Live electronics evidence lookup requires `externalSideEffect`.

Read-only cached evidence may use `readOnly` only if the implementation guarantees no provider request or page extraction will be issued.

## Cache And Privacy Rules

- Workspace cache remains the default.
- Global cache may be used only for non-secret public evidence.
- API keys and provider credentials must stay in web-search plugin settings or environment variables.
- Electronics workflows must not store provider credentials.
- Cache provenance must include query, evidence target, provider set, relevant settings, and result/extraction version.

## Proposed Future Implementation Steps

1. Add an electronics-scoped consumer request/response DTO in the electronics plugin.
2. Register `plugin.electronics/web_evidence_lookup` only when the electronics plugin is loaded.
3. Route requests to the generic `plugin.web_search` bus capabilities.
4. Preserve all web-search diagnostics in the electronics response.
5. Add fixture tests showing web evidence remains advisory and cannot satisfy completion gates.
6. Add focused unload tests proving the electronics consumer capability disappears with the electronics plugin.

## Decision Required Before Implementation

Before any electronics-domain code changes, decide whether electronics web evidence is:

1. user-invoked only, or
2. allowed as an explicit workflow step when catalog/provider evidence is insufficient.

Recommendation: start user-invoked only. That keeps current electronics gates stable while still allowing reviewed source gathering.
