# Claim Protocol (CLP)

Claim Protocol (CLP) is a deterministic claim + receipt identity instrument.

It defines how claims and receipts are canonicalized into stable bytes and how immutable IDs are derived from them using SHA-256.

## Current Canonical Status

**Status:** Negative Tier (-1) sealed identity core  
**Not yet:** Tier-0 standalone instrument

That means CLP currently proves:

- deterministic canonical claim identity
- deterministic canonical receipt identity
- frozen minimal golden vectors
- selftest evidence emission
- double-run determinism proof

CLP does **not yet** claim that the full protocol surface is locked.

The full standalone instrument surface still requires:

- object law
- media / storage law
- verifier law
- licensing / entitlement boundary
- expanded positive and negative conformance vectors

## What CLP Is

CLP is the identity derivation layer for claims and receipts.

At its sealed core, it provides:

- canonical JSON handling
- deterministic ClaimId derivation
- deterministic ReceiptId derivation
- reproducible selftests
- deterministic evidence bundles

## What CLP Is Not

CLP is not yet:

- a full hosted registry
- a witness network
- a trust authority
- a transport protocol
- a policy engine
- a complete Tier-0 standalone instrument

Those belong to adjacent layers or future CLP tiers.

## Canonical Tier Semantics

In the Constellation ecosystem:

- **Negative Tier (-1)** = substrate / engine correctness
- **Tier-0** = full standalone instrument
- **Tier-1+** = integrations and broader ecosystem operation

Nothing integrates until the project proves itself as a standalone instrument.

## Frozen Proofs

Current frozen proofs:

- minimal claim expected id
- minimal receipt expected id
- `_selftest_clp_v1.ps1`
- `_RUN_clp_freeze_tier0_v1.ps1`
- double-run determinism proof

Frozen outputs:

- `claim_id = 52a2b139dcf0b0f44bec850dcd121d3be3092988a50a15e112c06f51b78b84fd`
- `receipt_id = ee1ec699389f6fae72c032cbb7086c0c962cb4f050e515a48461a0b95f7b10c8`
- `root_hash = c756bfa7fd323246659229a11563550f7691360c84e72d52f8bbd9e7071c4b28`

## Repository Layout

```text
schemas/
laws/
reference/
scripts/
test_vectors/
docs/
proofs/
Current Tooling

Implemented now:

scripts/_lib_clp_v1.ps1

scripts/clp_hash_claim_v1.ps1

scripts/clp_hash_receipt_v1.ps1

scripts/clp_run_test_vectors_v1.ps1

scripts/_selftest_clp_v1.ps1

scripts/_RUN_clp_freeze_tier0_v1.ps1

Current Goal

The next goal is to elevate CLP from a sealed identity core to a true Tier-0 standalone instrument by locking:

object contract

payload/media contract

verifier contract

entitlement boundary

expanded conformance vectors

License

Apache-2.0. See LICENSE and docs/LICENSING.md.

Current Truth Statement

CLP identity core is sealed.

CLP full standalone protocol surface is still under construction.
