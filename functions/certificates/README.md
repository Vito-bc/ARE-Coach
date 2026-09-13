# Production Apple trust anchors

Public DER certificates downloaded from [Apple PKI](https://www.apple.com/certificateauthority/)
on 2026-09-12, as required by the [official verifier](https://github.com/apple/app-store-server-library-node#obtaining-apple-root-certificates).
These are public certificates, not credentials. No test CA or private key belongs here.

| File | Source | SHA-256 |
| --- | --- | --- |
| AppleIncRootCertificate.cer | https://www.apple.com/appleca/AppleIncRootCertificate.cer | b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024 |
| AppleRootCA-G2.cer | https://www.apple.com/certificateauthority/AppleRootCA-G2.cer | c2b9b042dd57830e7d117dac55ac8ae19407d38e41d88f3215bc3a890444a050 |
| AppleRootCA-G3.cer | https://www.apple.com/certificateauthority/AppleRootCA-G3.cer | 63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179 |

The worker always enables certificate revocation checks. A 6-second worker deadline
terminates outstanding OCSP/network work. Certificate rotation is a reviewed code
change; there is no environment setting for replacing trust roots or disabling
signature checks. Integration tests create ephemeral independent test PKI outside
this directory and verify that production rejects it.
