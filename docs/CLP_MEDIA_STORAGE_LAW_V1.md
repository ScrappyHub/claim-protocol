# Claim Protocol (CLP) Media / Storage Law v1

## Status

DRAFT FOR LOCK

This document defines the canonical payload, media binding, and storage overlay rules for Claim Protocol (CLP) v1.

This law extends:

- the sealed CLP identity core
- the CLP Object Law v1 draft

It defines what `payload` means for canonical CLP claim and decision objects.

It does not redefine ClaimId or ReceiptId identity rules. It defines the media/storage forms those identities may carry or reference.

---

# 0. Purpose

CLP cannot become a full standalone instrument unless it can express payloads in a stable and verifiable way.

This law defines:

- canonical payload modes
- inline payload rules
- external blob reference rules
- packet reference rules
- storage overlay guidance
- invalid payload conditions

Until this law is locked, CLP can describe objects structurally, but it cannot yet claim a fully locked payload/media surface.

---

# 1. Payload Law Scope

This law applies to:

- `clp.claim.v1`
- `clp.decision.v1`

For both object families, `payload` MUST be a JSON object.

That payload object MUST contain:

- `mode`

The `mode` value determines which payload law branch applies.

---

# 2. Canonical Payload Modes

CLP v1 defines exactly four canonical payload modes:

1. `inline_json`
2. `inline_text`
3. `blob_ref`
4. `packet_ref`

No other payload mode is canonical under this law.

Future payload modes require a new law version or an explicit extension law.

---

# 3. Global Payload Rules

All CLP payload objects MUST satisfy all of the following:

- payload MUST be a JSON object
- payload MUST contain `mode`
- `mode` MUST be a string
- `mode` MUST be one of the canonical payload modes
- payload fields are hashed exactly as present after canonical serialization
- verifier behavior is non-mutating
- payload references do not change ClaimId or DecisionId rules; they participate in canonical object hashing exactly as present

CLP does not “fill in” missing media fields during verification.

---

# 4. Payload Mode: `inline_json`

## 4.1 Purpose

`inline_json` is used when structured JSON data is directly embedded in the claim or decision payload.

## 4.2 Required fields

A valid `inline_json` payload MUST contain:

- `mode`
- `value`

## 4.3 Required values

- `mode` MUST equal `inline_json`
- `value` MUST be a JSON object or array

## 4.4 Optional fields

A valid `inline_json` payload MAY contain:

- `media_type`

If present, `media_type` MUST be a string.

Recommended value:

- `application/json`

## 4.5 Invalid conditions

An `inline_json` payload is invalid if:

- `value` is missing
- `value` is null
- `value` is not an object or array
- `mode` is not exactly `inline_json`

---

# 5. Payload Mode: `inline_text`

## 5.1 Purpose

`inline_text` is used when deterministic text content is embedded directly into the payload object.

## 5.2 Required fields

A valid `inline_text` payload MUST contain:

- `mode`
- `media_type`
- `text`

## 5.3 Required values

- `mode` MUST equal `inline_text`
- `media_type` MUST be a string
- `text` MUST be a string

Recommended `media_type` values include:

- `text/plain`
- `text/markdown`
- `application/sql`

## 5.4 Invalid conditions

An `inline_text` payload is invalid if:

- `media_type` is missing
- `text` is missing
- `media_type` is not a string
- `text` is not a string
- `mode` is not exactly `inline_text`

---

# 6. Payload Mode: `blob_ref`

## 6.1 Purpose

`blob_ref` is used when the payload bytes live outside the CLP object but are bound by deterministic metadata.

## 6.2 Required fields

A valid `blob_ref` payload MUST contain:

- `mode`
- `media_type`
- `digest`
- `length`

## 6.3 Optional fields

A valid `blob_ref` payload MAY contain:

- `filename`

## 6.4 Required values

- `mode` MUST equal `blob_ref`
- `media_type` MUST be a string
- `digest` MUST be a string
- `length` MUST be an integer number
- if `filename` is present, it MUST be a string

## 6.5 Digest format

For CLP v1, `digest` MUST begin with:

- `sha256:`

The remainder MUST be lowercase hexadecimal.

## 6.6 Length law

`length` MUST represent the external blob length in bytes.

`length` participates in hashing if present.

## 6.7 Blob verification meaning

A verifier may compute:

- digest match
- length match

A missing external blob does not change ClaimId or DecisionId for the CLP object itself.

It does prevent successful full payload verification.

## 6.8 Invalid conditions

A `blob_ref` payload is invalid if:

- `media_type` is missing
- `digest` is missing
- `length` is missing
- `media_type` is not a string
- `digest` is not a string
- `length` is not numeric
- `digest` does not begin with `sha256:`
- `mode` is not exactly `blob_ref`

---

# 7. Payload Mode: `packet_ref`

## 7.1 Purpose

`packet_ref` is used when payload content is carried through a packet store or packet transport layer and CLP references it.

## 7.2 Required fields

A valid `packet_ref` payload MUST contain:

- `mode`
- `packet_id`

## 7.3 Optional fields

A valid `packet_ref` payload MAY contain:

- `manifest_digest`
- `path`

## 7.4 Required values

- `mode` MUST equal `packet_ref`
- `packet_id` MUST be a string
- if `manifest_digest` is present, it MUST be a string
- if `path` is present, it MUST be a string

## 7.5 Packet law boundary

CLP does not redefine packet verification.

CLP only binds packet references into object identity.

Packet verification remains owned by the packet law / packet verifier layer.

## 7.6 Invalid conditions

A `packet_ref` payload is invalid if:

- `packet_id` is missing
- `packet_id` is not a string
- `manifest_digest` is present but not a string
- `path` is present but not a string
- `mode` is not exactly `packet_ref`

---

# 8. Storage Overlay Law

## 8.1 Purpose

Storage layout does not define identity.

Identity comes from canonical object bytes.

Storage exists only as an overlay for retrieval and verification.

## 8.2 Recommended local layout

Recommended local overlay layout:

- `objects/claims/<claim_id>.json`
- `objects/receipts/<receipt_id>.json`
- `blobs/sha256/<hex>`
- `packets/<packet_id>/...`

This layout is recommended, not mandatory.

## 8.3 Overlay rule

A storage path MUST NOT be treated as identity.

A filename MUST NOT be treated as identity.

Only canonical bytes and canonical reference fields define identity.

## 8.4 Upload rule

Uploading arbitrary JSON or media does not automatically make it canonical CLP payload.

A payload becomes canonical only if it satisfies:

- CLP Object Law v1
- this Media / Storage Law v1

---

# 9. Invalid Payload Conditions (Global)

A payload is globally invalid if:

- payload is not an object
- `mode` is missing
- `mode` is not a string
- `mode` is not one of the canonical payload modes
- required fields for the specific mode are missing
- required fields for the specific mode have wrong top-level type

---

# 10. Canonical Truth Statement

This law defines the canonical CLP payload/media surface.

A CLP object may reference media and packet content, but those references must conform to one of the canonical payload modes.

Until this law is locked and verified with vectors, the CLP payload/media surface remains draft.

---

# 11. Definition of Done for Media / Storage Law Lock

This law is ready to lock when:

- this document is frozen
- schema files match this document exactly
- positive vectors exist for all four payload modes
- negative vectors exist for bad mode and missing required payload fields
- verifier failure tokens for payload-law failures are frozen
- media/storage vector runner passes deterministically

Until then, this law remains DRAFT FOR LOCK.