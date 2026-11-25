# Deduplication guidelines

The selected [Sherlock judging guidelines, §4](judging-guidelines.md#4-duplication-guidelines), govern duplication. Engagement context cannot override these rules. The section below preserves their requirements and consequences.

The duplication guidelines assume we have a "target issue", and the "potential duplicate" of that issue needs to meet the following requirements to be considered a duplicate.

1. Identify the root cause
2. Identify at least a Low impact
3. Identify a valid attack path or vulnerability path

Only when the "potential duplicate" meets all three requirements will the "potential duplicate" be duplicated with the "target issue", and all duplicates will be awarded the highest severity identified among the duplicates.

If the report does not meet all three requirements, do not group it with the target issue. Assess whether it duplicates another issue separately. Assess its True Finding, scope, known, and severity verdicts under their respective rules.

**Root cause groupings**

Issues that appear in multiple places, even in different components, may have the same root cause:

1. Issues with the same logic mistake.
2. Issues with the same conceptual mistake.

   > Example: different untrusted external admins can steal funds.

If the underlying code implementations, impact or fixes are different, then they may be treated separately.

**Identifies the core issue:** In case of issues that have a large number of duplicates, Issues that identify the core issue and show a valid impact should be grouped.

Source: [selected judging guidelines, §4](judging-guidelines.md#4-duplication-guidelines), including “Root cause groupings” and “Identifies the core issue.”

“Root Cause,” “Attack Path,” and “Vulnerability Path” are defined in the [guidelines' glossary, §6](judging-guidelines.md#6-glossary). Apply the Low-impact requirement using the complete [severity set](severity-set.json) and the [severity measurement rules, §3.4](judging-guidelines.md#34-severity).

The [statements file](statements.json) and [disclosure source map](source-map.md) provide the engagement's accepted-behavior and known-status references. Those verdicts are assessed under [§2 and §§3.1–3.3](judging-guidelines.md#2-order-of-authority); they supply no replacement for the three duplication requirements above. The [finding report standard](finding-report-standard.md) guides report writing; duplication assesses the report's content.
