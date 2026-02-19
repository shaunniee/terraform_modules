# IAM Companion Guide

This guide defines how IAM should be handled across modules in this repository.

## Recommendation

Use **separated IAM** by default:

- Keep infrastructure modules focused on service resources.
- Keep IAM roles/policies in dedicated IAM modules or root stacks.
- Pass role/policy ARNs into service modules via inputs.

Use **embedded IAM** only when:

- It is required for module usability,
- The scope is tightly bounded,
- It can be disabled with a toggle/input.

## Why separated IAM is better

- Easier least-privilege reviews and approvals.
- Avoids permission sprawl hidden inside many modules.
- Supports org-level controls (SCPs, permission boundaries, policy-as-code).
- Easier reuse across dev/stage/prod with different security rules.

## Pattern to use in modules

When IAM is needed in a service module, prefer this model:

- `create_<thing>_role` boolean (default `false` for shared modules)
- `existing_<thing>_role_arn` input
- `precondition` ensuring one mode is selected
- Outputs exposing selected role ARN/name

Example decision logic:

- If `create_*_role = true`, module creates role/policies.
- Else, caller must provide `existing_*_role_arn`.

## Deploy role vs runtime role

Treat these separately:

1. **Terraform deploy role**
   - Permissions to create/update AWS resources (CloudWatch alarms, CloudTrail, etc.)
   - Scoped to account/environment where Terraform runs.

2. **Service runtime roles**
   - Permissions used by Lambda/API Gateway/EventBridge/CloudFront integrations at runtime.
   - Scoped to each service action path.

## Module matrix (current repo)

- `aws_lambda`
  - Supports module-managed role **or** external role (`execution_role_arn`).
  - Good hybrid pattern.
- `aws_eventbridge`
  - Supports optional Lambda permission creation for targets.
  - Keep broader IAM external.
- `aws_api_gateway_rest_api`
  - Logging/tracing settings are configurable; account-level roles may still need external setup.
- `aws_cloudfront`
  - Logging/metrics/alarms are configurable; Kinesis role for realtime logs should stay external.
- `aws_dynamodb`
  - Alarms/Contributor Insights/CloudTrail observability configurable; IAM for CloudTrail destination and org controls should stay external.

## Practical defaults for this repository

- Keep IAM **separate by default** for all modules.
- Allow optional in-module IAM only where it materially improves first-run UX.
- For optional in-module IAM, always provide explicit toggle + external ARN override.
- Document required permissions in each module `usage.md`.

## Pull request checklist (IAM)

- Does this change add or broaden IAM permissions?
- Can permissions be moved to caller/root IAM instead?
- Is there a least-privilege resource scope?
- Is there a toggle to disable embedded IAM?
- Are required permissions documented in module usage docs?
