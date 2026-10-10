# Data safety review, 10 October 2026

Decision on 10 October 2026: the owner approved retaining Google's scanner and correcting the disclosures. The corrected privacy policy is published and HTTP/browser verified at https://www.tetherly.link/privacy. Play declarations were saved and included in the production review submission on 10 October 2026. Do not select "no data collected" in Play Console.

The current Android app declares `com.google.android.gms:play-services-code-scanner:16.1.0`. Google lists `play-services-code-scanner` in its ML Kit Android disclosure. Its common collection includes device/app information, device or installation identifiers, performance metrics, API configuration, event types, sizes, and error codes for diagnostics and usage analytics. HTTPS protects this SDK telemetry in transit. This is distinct from Tetherly's mutually authenticated, encrypted device-to-device screen/input/clipboard/file path.

Sources verified on 10 October 2026:
- https://developers.google.com/ml-kit/android-data-disclosure
- https://developers.google.com/ml-kit/vision/barcode-scanning/code-scanner
- https://support.google.com/googleplay/android-developer/answer/10787469

## Proposed disclosure worksheet

Current source configures QR-only scanning and does not call `enableAutoZoom()`. Google's documented additional auto-zoom telemetry is therefore not enabled by this source configuration. This does not disable the SDK's common collection. Manual connection remains available; that alone does not prove all SDK diagnostics are optional or absent outside scanner use.

This initial worksheet is retained as review history. The submitted classifications are recorded below.

| Play form topic | Candidate / unresolved evidence |
|---|---|
| Does the app collect data? | Yes while this SDK remains, subject to final dependency and behavior review. Do not choose No solely because Tetherly has no backend. |
| Device or other IDs | SDK device/installation identifiers; usage analytics and diagnostics. Confirm current SDK behavior and form categorization. |
| App activity / app interactions | Scanner initialization, model download/detection/release events and configuration may map here. Confirm exact fields in the current form. |
| App info and performance / diagnostics | SDK latency, errors, hardware/app version metadata. Confirm exact data type mappings. |
| Crash logs | No separate crash-reporting SDK found in reviewed first-party source. Google documents error codes, not a blanket crash-log collection claim. |
| Purpose | Google's stated diagnostics and usage analytics. Do not relabel as only app functionality. |
| Optional / required | Unverified. The scanner is user-initiated, but SDK initialization and telemetry timing need validation. Do not assume scanner telemetry is optional. |
| Shared data | Google says ML Kit does not transfer this collected data to third parties. Confirm service-provider treatment and the complete app dependency graph before choosing form answers. |
| Encryption in transit | SDK uses HTTPS. Tetherly session traffic uses authenticated TLS. No assertion that SDK telemetry is end-to-end encrypted. |
| Deletion | No Tetherly accounts. Local revocation clears paired identities, not necessarily Google's SDK telemetry. Owner must provide a truthful applicable retention/deletion explanation. |
| Screen, text, clipboard, selected files | Device-to-device content uses authenticated TLS between user-approved endpoints. Review the form's end-to-end-encryption and user-initiated-transfer rules against the actual implementation. DataHase has no content relay in reviewed source. |

## Website correction

The public privacy page and metadata observed during preparation make blanket no-collection/no-analytics claims that conflict with the scanner disclosure. Local privacy, homepage, support, README and publishing source has now been corrected following the owner's decision. The corrected policy separates remote content from SDK diagnostics, links Google's documentation, and explains that local deletion does not delete Google's diagnostic records. The following short paragraph remains available for other descriptions:

"Tetherly does not operate an account service, advertising platform, or server that receives your remote desktop content. Screen, input, clipboard, and selected-file traffic travels between your approved devices. The Android QR scanner uses Google Play services. Google documents collection of device and app information, identifiers, performance metrics, and scanner event diagnostics for this SDK. See Google's ML Kit data disclosure for details. This SDK telemetry is separate from your remote desktop content."

SDK retention and exact telemetry timing have not been independently measured. The final Play form classifications are recorded below. Google's policies govern its retention; no specific retention period or deletion guarantee has been invented. The public privacy, homepage and support corrections were deployed on 10 October 2026 and verified. Replacing the scanner is no longer the selected route.

## Console declaration submitted on 10 October 2026

The production submission uses these conservative classifications for Google scanner SDK telemetry: Diagnostics, App interactions, and Device or other IDs. All three are Collected, Required, not ephemeral, and used for Analytics. They are not marked Shared, following Google's documented absence of transfers to third parties. Encryption in transit is Yes. No developer-provided data deletion facility or account creation is claimed. No separate crash-log category is asserted from error codes alone.

These classifications are submitted disclosure choices, not evidence that telemetry timing or retention has been independently measured. Remote desktop content travels directly between the owner's approved devices; no Datahase content backend or relay is present in the reviewed source. The website's separate Google Analytics consent and disclosure are not represented as native-app telemetry.
