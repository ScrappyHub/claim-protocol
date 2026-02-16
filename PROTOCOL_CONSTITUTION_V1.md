# Claim Protocol (CLP)
## Constitution v1 (LOCKED)

Status: LOCKED
Version: clp.v1

---

# 0. Purpose

CLP defines a universal protocol for verifiable truth.

Truth is represented as:

- content-addressed objects
- cryptographic signatures
- append-only claims
- independently verifiable receipts

All higher systems compose these primitives.

---

# 1. Canonical Bytes Law

All hashes and signatures operate on canonical bytes only.

Required encoding:

- UTF-8
- no BOM
- LF line endings
- canonical JSON:
  - sorted keys
  - no whitespace
  - stable escaping
  - deterministic numbers (no NaN/Infinity)

Rule:

object_id = SHA-256(canonical_bytes(object))

Byte equality is identity.
No semantic equivalence allowed.

---

# 2. Claim Identity Law (Option 1 — LOCKED)

Claim identity excludes signatures.

ClaimId = SHA-256(canonical_bytes(claim_without_signature))

Implications:

- re-signing does not change identity
- multiple signatures may attach to the same claim
- receipts reference stable ids
- witnesses do not fork identity

---

# 3. Core Objects

CLP defines exactly four primitives:

1. Claim
2. Receipt
3. Packet (delegated to Packet Constitution v1)
4. Decision (specialized Claim)

Nothing else is fundamental.

---

# 3.1 Claim

A producer assertion.

Properties:

- content-addressed
- signed (when signature is present)
- immutable

Claims produce ClaimId.

---

# 3.2 Receipt

A counter-claim about a Claim.

Properties:

- references ClaimId
- signed by witness/verifier/gate
- immutable

Receipt identity excludes signature:

ReceiptId = SHA-256(canonical_bytes(receipt_without_signature))

Types include:

- witness.receipt.v1
- verify.receipt.v1
- ingest.receipt.v1
- decision.receipt.v1

---

# 3.3 Packet

Transport container defined by Packet Constitution v1.

CLP delegates all transport semantics.

---

# 3.4 Decision

A Claim with enforcement semantics.

Represents allow/deny/transform results.

---

# 4. Separation of Powers Law

Roles are independent.

Producer:
  creates claims

Witness:
  attests only that a claim was seen

Verifier:
  verifies hashes, signatures, trust

Gate:
  consumes verified inputs and produces decisions

No role may silently mutate artifacts.

---

# 5. Flow Law

Mandatory:

Produce → Local Pledge

Optional:

Witness
Verify
Enforce
Transport

Local pledge MUST occur first.

---

# 6. Non-Mutation Law

Verifiers and witnesses MUST NOT:

- rewrite
- self-heal
- modify packets

Repairs must be new claims.

History is immutable.

---

# 7. Compliance Definition

A system is CLP-compliant if it:

- uses canonical bytes
- content-addresses objects
- signs claims
- emits receipts
- never mutates artifacts
- respects separation of powers

Compliance is binary.

---

END OF CONSTITUTION
