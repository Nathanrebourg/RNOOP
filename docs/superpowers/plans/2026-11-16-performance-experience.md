# Dated iPhone Performance Experience Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan inline, with focused review of the completed patch. The user has approved the visual prototype and explicitly requested coding.

**Goal:** Integrate the approved premium daily experience and contextual coach into the real iPhone app, using actual repository data.
**Architecture:** iOS-only presentation views share existing repositories and calculation engines. A Foundation-only dated context policy anchors reads and trends, while isolated in-memory coach sessions reuse the configured provider without overwriting the existing saved conversation. Existing advanced screens remain reachable.
**Tech Stack:** SwiftUI, Swift Charts, WhoopStore, StrandDesign and the existing AICoachEngine.
**Spec:** The approved NROOP-maquette-interactive.html and NROOP-analyse-video-et-refonte.md in the chat outputs; visual refinement and contextual coach approved in the chat.

## Global Constraints
- Keep analytics, BLE commands and stored schemas unchanged.
- No invented physiological values or zeros for missing data; no silent prior-day carry.
- Preserve the coach master switch, provider configuration and data consent; opening a coach never sends a request.
- No extra network or cloud service. Context only leaves through an explicitly requested existing coach send.
- iPhone presentation only in this change; Android and macOS retain their UI. Shared coach additions must preserve default behavior and macOS compilation.
- Design tokens and shared components supply colors, typography and spacing. Keep iOS 17 and macOS 13 compatibility.
- Work in the isolated source copy /private/tmp/nroop-ui-dev/noop-nathan. The previous delivered source archive remains the baseline.

## Review Focus
- A past date must not consume future points or today's measurements, including in coach prompts.
- A selected day without data must remain empty even when newer or older rows exist.
- Available vitals are not automatically within a personal reference range.
- A contextual chat must not load, replace or delete the existing persisted conversation.
- Navigation must preserve access to advanced tools, workouts, journal and coach setup when the top-level tabs change.

### Task 1: Dated presentation and coach policy
- [x] Add focused tests for strict dates, cutoff windows, missing values, stable context identities and consent redaction; run them before implementation.
- [x] Add PerformanceContext.swift (Foundation-only) and a repository-backed dated snapshot loader; compute no new physiological scores.
- [x] Verify historical anchoring and handling of non-finite values.

### Task 2: Native presentation
- [x] Add PerformanceDesign tokens/components to StrandDesign and iOS PerformanceTodayView, PerformancePillarView and PerformanceTrendView.
- [x] Resolve scores through existing repository series and provenance, never prototype fixtures.
- [x] Add actual-date health availability/reference display, sleep durations/stages, effort/activity rows and existing action links.
- [x] Add the user-supplied sensor cutout as an iOS asset for activity preparation; actual session controls remain the existing workout flow.

### Task 3: Coach integration and navigation
- [x] Add nonpersistent conversation mode to AICoachEngine with the existing persistent behavior as its default.
- [x] Add explicit dated screen context to send; redact all data with consent off and exclude future metrics/workouts.
- [x] Add contextual coach sheet/session coordinator with explicit send, setup link, real streaming messages, suggested questions, errors and per-context memory.
- [x] Rework RootTabView to Today / Health / Activities / More with a contextual coach launcher. Retain quick actions, deep links and advanced trends access.

### Task 4: Verification and delivery
- [x] Run focused native context/coach tests and required source checks; build iOS and macOS targets.
- [x] Inspect the iPhone simulator with real empty states and existing demonstration data only if explicitly enabled; do not report fixtures as user measurements.
- [x] Review the complete patch, resolve material findings and rebuild after fixes.
- [x] Export the installable unsigned IPA, reproducible sources, patch and a concise French guide with actual validation evidence. Update active source metadata only after final verification.

Delivery evidence is recorded in the execution ledger and the accompanying NROOP-Interface-verification.txt. The exported IPA is unsigned; simulator measurements are synthetic demonstration data. Hardware and live AI-provider validation remain outside this verification.
