# Claim Protocol (CLP) Surface Spec v1

## Status

Draft for lock

## Scope

This document extends the sealed CLP Tier-0 identity core into a complete protocol surface suitable for ecosystem integration. It defines:

* object law
* media/storage law
* verifier law
* entitlement boundary

This document does **not** replace the already sealed identity derivation law. It layers on top of it.

---

# 0. Canonical Status Language

Use these terms precisely:

* **Sealed**: deterministic implementation and proofs exist, with green selftests and frozen expected outputs.
* **Locked**: normative spec text is frozen for the named boundary.
* **Draft**: proposed but not yet frozen.
* **Out of scope**: intentionally excluded from this version.

For CLP as of this document:

* identity core: sealed
* full protocol surface: draft until all sections below are frozen

---

# 1. What CLP Is

Claim Protocol (CLP) is a deterministic protocol for canonicalizing, identifying, packaging, verifying, and referencing claims and receipts.

CLP defines:

* canonical object forms for claims and receipts
* immutable ClaimId and ReceiptId derivation
* payload/media binding rules
* verifier conformance behavior
* integration boundaries for surrounding ecosystem tools

CLP does **not** itself define trust policy, authorization policy, or transport reliability. Those belong to adjacent layers such as NeverLost, NFL, WatchTower, Echo Transport, and Covenant Gate.

---

# 2. Boundary Statement

## 2.1 CLP core responsibilities

CLP owns:

* object schemas and required fields
* canonical bytes rules for claims and receipts
* ClaimId and ReceiptId derivation
* payload/media binding semantics
* verifier input/output rules
* conformance vectors

## 2.2 CLP does not own

CLP does not own:

* principal identity issuance
* trust graph management
* witness network behavior
* transport packet routing
* policy enforcement semantics
* hosted registry UX

---

# 3. Object Law

## 3.1 Object families

CLP v1 defines the following canonical object families:

1. `clp.claim.v1`
2. `clp.receipt.v1`
3. `clp.decision.v1` (specialized claim)
4. `clp.bundle.manifest.v1` (optional grouping manifest; not required for Tier-0 verifier)

## 3.2 General object rules

All CLP objects must:

* be valid JSON objects
* be serialized to canonical bytes before hashing
* be UTF-8 without BOM on disk
* use LF line endings on disk
* reject NaN/Infinity numeric forms
* reject duplicate keys
* reject non-object top-level values for canonical CLP artifacts

## 3.3 Claim object: `clp.claim.v1`

### Required fields

* `schema`
* `claim_type`
* `producer`
* `timestamp`
* `payload`

### Optional fields

* `signature`
* `prev_links`
* `meta`
* `strength`
* `labels`

### Required field meanings

`schema`
: must equal `clp.claim.v1`

`claim_type`
: producer-defined, namespaced, versioned claim kind, e.g. `core.commit.v1`

`producer`
: stable producer identifier string, not necessarily a trust principal by itself

`timestamp`
: timestamp string exactly as emitted by producer; CLP hashes it as-is and does not reinterpret timezone semantics

`payload`
: must be one of the payload forms defined in section 4

### Identity derivation

`ClaimId = SHA-256(canonical_bytes(claim_without_signature))`

`signature` is excluded from ClaimId derivation.

## 3.4 Receipt object: `clp.receipt.v1`

### Required fields

* `schema`
* `receipt_type`
* `for_claim`
* `result`
* `timestamp`

### Optional fields

* `signature`
* `meta`
* `producer`
* `inputs`

### Required field meanings

`schema`
: must equal `clp.receipt.v1`

`receipt_type`
: namespaced, versioned receipt kind, e.g. `watchtower.verify.receipt.v1`

`for_claim`
: ClaimId referenced by this receipt

`result`
: structured JSON object describing the outcome

`timestamp`
: timestamp string hashed as-is

### Identity derivation

`ReceiptId = SHA-256(canonical_bytes(receipt_without_signature))`

`signature` is excluded from ReceiptId derivation.

## 3.5 Decision object: `clp.decision.v1`

A decision is a claim with enforcement semantics.

### Required fields

* `schema`
* `decision_type`
* `inputs`
* `result`
* `producer`
* `timestamp`
* `payload`

### Identity derivation

Decision identity follows claim identity law unless a later version says otherwise.

## 3.6 Unknown fields policy

CLP v1 allows unknown extension fields only if:

* they do not shadow required fields
* they are canonical JSON compatible
* verifiers preserve them during non-mutating parse/rehash

Unknown fields are hashed as part of the object.

## 3.7 Invalid object conditions

A CLP object is invalid if:

* required fields are missing
* `schema` value is wrong
* top-level type is not object
* duplicate keys are present
* canonical serializer cannot represent a value deterministically
* payload form is invalid for the declared schema

---

# 4. Media / Storage Law

## 4.1 Purpose

CLP must support claims over more than inline text JSON. It needs a stable way to bind media, binary payloads, packets, and storage overlays.

## 4.2 Payload forms

`payload` in `clp.claim.v1` and `clp.decision.v1` must use exactly one of these forms.

### A. Inline JSON payload

```json
{
  "mode": "inline_json",
  "value": {"...": "..."}
}
```

Use when the payload is small structured JSON.

### B. Inline text payload

```json
{
  "mode": "inline_text",
  "media_type": "text/plain",
  "text": "..."
}
```

Use for deterministic text claims.

### C. Blob reference payload

```json
{
  "mode": "blob_ref",
  "media_type": "image/png",
  "digest": "sha256:<hex>",
  "length": 12345,
  "filename": "optional-name.png"
}
```

Use when the actual bytes live outside the claim object but are bound by digest.

### D. Packet reference payload

```json
{
  "mode": "packet_ref",
  "packet_id": "<packet id>",
  "manifest_digest": "sha256:<hex>",
  "path": "payload/file.bin"
}
```

Use when the payload is carried by an Echo Transport / Packet Constitution packet.

## 4.3 Blob law

For `blob_ref`:

* `digest` is mandatory
* `length` is mandatory
* verifier must be able to compare observed bytes to `digest` and `length`
* missing bytes do not invalidate object identity; they invalidate full verification status

## 4.4 Packet law

For `packet_ref`:

* `packet_id` is mandatory
* `path` is optional if the whole packet is the payload object
* verifier may resolve packet content through Echo Transport or local packet stores
* CLP does not redefine packet verification; it only binds the packet reference into claim identity

## 4.5 Storage overlay model

CLP storage overlay is content-addressed and non-authoritative by itself.

Meaning:

* storage may cache objects by ClaimId/ReceiptId
* blob/media stores may map digests to bytes
* packet stores may map packet_id to packet directories
* object identity is still computed from object bytes, not storage path

### Recommended local layout

* `objects/claims/<claim_id>.json`
* `objects/receipts/<receipt_id>.json`
* `blobs/sha256/<hex>`
* `packets/<packet_id>/...`

This layout is recommended, not mandatory.

## 4.6 Upload contract

A host or tool may accept user uploads, but uploaded JSON becomes a CLP object only if:

* it validates against the CLP object law
* canonicalization succeeds
* the declared payload form is valid

So “upload any JSON” is **not** the rule. The rule is “upload a valid CLP object.”

---

# 5. Verifier Law

## 5.1 Verifier purpose

A CLP verifier checks that a supplied claim/receipt/media reference matches canonical rules and produces stable outcomes.

## 5.2 Verifier classes

CLP v1 defines:

* **identity verifier**: computes ClaimId/ReceiptId and validates object structure
* **payload verifier**: checks blob or packet payload bindings
* **conformance verifier**: runs vectors and asserts exact outputs

Tier-0 requires only identity verifier + conformance verifier.

## 5.3 Required verifier inputs

For claim verification:

* claim JSON path or bytes

For receipt verification:

* receipt JSON path or bytes

Optional:

* blob bytes or path
* packet path

## 5.4 Required verifier outputs

Verifier outputs must include, at minimum:

* `schema`
* `ok`
* `object_type`
* `computed_id`
* `reason_token`
* `details`

### Example output schema

```json
{
  "schema": "clp.verify.result.v1",
  "ok": true,
  "object_type": "claim",
  "computed_id": "sha256:...",
  "reason_token": "OK",
  "details": {}
}
```

## 5.5 Stable reason tokens

Tier-0 reason tokens must be deterministic and exact. Minimum required set:

* `OK`
* `INVALID_JSON`
* `INVALID_TOP_LEVEL_TYPE`
* `MISSING_REQUIRED_FIELD`
* `INVALID_SCHEMA`
* `INVALID_PAYLOAD_MODE`
* `CANON_FAIL_DUPLICATE_KEY`
* `CANON_FAIL_INVALID_NUMBER`
* `CLAIM_ID_MISMATCH`
* `RECEIPT_ID_MISMATCH`
* `BLOB_DIGEST_MISMATCH`
* `BLOB_LENGTH_MISMATCH`
* `PACKET_REF_UNRESOLVED`

## 5.6 Non-mutation law

A verifier must not:

* rewrite the source claim/receipt
* normalize the source file on disk in-place
* fill missing fields silently
* strip unknown fields silently

Verification must be non-mutating.

## 5.7 Conformance vectors

A conforming verifier must eventually pass:

* minimal positive claim vector
* minimal positive receipt vector
* key-ordering vector
* unicode escaping vector
* invalid number vector
* duplicate key negative vector
* invalid schema negative vector
* invalid payload mode negative vector

Tier-0 seal currently proves only the minimal positive claim + receipt vectors. Additional vectors remain post-seal work.

---

# 6. Integration Contracts

## 6.1 Echo Transport integration

Echo Transport should treat CLP objects as canonical payload artifacts.

Recommended packet contents:

* claim JSON or receipt JSON as files
* optional associated blobs
* packet manifest references packet payloads, while CLP object references blob or packet digests

## 6.2 NFL integration

NFL witness receipts should reference `for_claim = <ClaimId>` using CLP identity law.

## 6.3 WatchTower integration

WatchTower should recompute ClaimId/ReceiptId using CLP canonicalization and then layer trust/signature analysis on top.

## 6.4 Covenant Gate integration

Covenant Gate should consume ClaimIds and ReceiptIds as immutable policy references, not mutable user blobs.

---

# 7. Licensing / Entitlement Boundary

## 7.1 Why this section exists

A protocol should not be called broadly “locked” as a product surface unless its commercial / entitlement boundary is explicit.

## 7.2 Proposed CLP v1 product boundary

### Open core (recommended)

Open and freely usable:

* spec docs
* canonical JSON rules
* claim/receipt identity derivation
* reference hash tools
* local selftest + vectors

### Premium / hosted boundary (recommended)

Commercial / entitled offerings may include:

* hosted CLP registry
* hosted conformance verification at scale
* enterprise object index/search
* signed release bundles and managed witness services
* OEM integration kits

## 7.3 Entitlement law

Local identity derivation should remain unrestricted, because ecosystem conformance depends on universal reproducibility.

Hosted services, scale tooling, registries, and enterprise management layers may be entitled separately.

## 7.4 Required repository licensing artifacts before broad “locked” claim

To claim the product surface is fully locked, repo should include:

* `LICENSE`
* `NOTICE` if needed
* `docs/LICENSING.md`
* explicit statement of OSS core vs hosted / OEM / enterprise layers

---

# 8. WBS to Full Surface Lock

## CLP-SURFACE-01 Object Contract

* define final required/optional fields — DRAFT
* define invalid conditions — DRAFT
* define extension field law — DRAFT

## CLP-SURFACE-02 Media / Storage Contract

* lock payload modes — DRAFT
* lock blob_ref semantics — DRAFT
* lock packet_ref semantics — DRAFT
* add media vectors — DRAFT

## CLP-SURFACE-03 Verifier Contract

* lock verifier output schema — DRAFT
* lock reason tokens — DRAFT
* add negative vectors — DRAFT
* add conformance runner — DRAFT

## CLP-SURFACE-04 Licensing / Entitlements

* choose license model — DRAFT
* add LICENSE/LICENSING docs — DRAFT
* define entitled hosted boundaries — DRAFT

---

# 9. Definition of Done for “Full CLP Protocol Surface Locked”

CLP full surface is locked only when:

* object law is frozen
* media/storage law is frozen
* verifier law is frozen
* licensing / entitlement boundary is frozen
* vectors exist for positive + negative object/media cases
* verifier outputs stable reason tokens
* reference implementation passes all vectors deterministically
* repository contains required licensing artifacts

Until then, only the **identity core** should be described as sealed.

---

# 10. Current Truth Statement

As of this draft:

* CLP identity core is sealed
* CLP full object/media/verifier/licensing surface is not yet locked

This document exists to close that gap.
