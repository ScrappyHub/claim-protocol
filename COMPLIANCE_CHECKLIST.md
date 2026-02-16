# CLP Compliance Checklist

A system MUST:

[ ] canonical bytes (UTF-8 no BOM, LF, canonical JSON)
[ ] SHA-256 addressing of objects
[ ] ClaimId excludes signature (Option 1)
[ ] ReceiptId excludes signature
[ ] emits Claims and Receipts as immutable objects
[ ] no artifact mutation by verifiers/witnesses
[ ] separation of powers respected
[ ] passes test_vectors

If any fail → NOT CLP compliant
