# Task 452b: Vendor Evidence Enrichment

## Goal

Use vendor evidence more effectively while preserving truthfulness: combine
same-part evidence across providers, normalize Nexar electrical fields, and
resolve only deterministic candidate ties.

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN vendor evidence is enriched THE electronics workflow SHALL preserve provenance and block unresolved or ambiguous candidate ties.

## Scope

1. Merge same-MPN candidate evidence after category/constraint filtering and
   before validation.
2. Preserve all provider provenance and datasheet references during merge.
3. Route Nexar fixtures through the Nexar GraphQL adapter instead of the generic
   aggregator adapter.
4. Normalize Nexar `Vce`, `Ic`, power, and polarity specs into canonical
   selection rating fields.
5. Prefer exact rating matches over excessive overspecification when multiple
   valid candidates remain.
6. Keep blocked/ambiguous behavior when required evidence is still missing or
   candidates remain tied.

## Verify

Run task 452a plus the focused component-selection suite and AmpDemo live
catalog slice.
