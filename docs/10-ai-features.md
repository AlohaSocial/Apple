# 10 — Intelligence features

## 1. Principles

1. **On-device only.** Everything runs through Apple's `FoundationModels` and
   `Translation` frameworks. No API keys, no accounts, no network, no cost, no
   third-party terms. Nothing a person writes leaves the device because of a
   feature in this section.
2. **Opt-in per feature.** Every one is off until switched on. There is no
   master switch that turns on things the person has not seen.
3. **Never automatic.** No feature acts without an explicit gesture. Nothing is
   posted, rewritten, or replaced without review.
4. **Always removable.** With every toggle off, the app has no Intelligence UI
   at all — no buttons, no menu items, no sparkle icons.
5. **Honest labelling.** Generated text is marked as generated in the UI where
   it is presented for review, in wording that survives translation.

## 2. Availability

```swift
switch SystemLanguageModel.default.availability {
case .available:                       // full feature set
case .unavailable(.deviceNotEligible): // hide the section entirely
case .unavailable(.appleIntelligenceNotEnabled),
     .unavailable(.modelNotReady):     // show the section, disabled, with why
@unknown default:                      // treat as unavailable
}
```

The Intelligence settings section is **hidden** on ineligible devices and
**shown disabled with an explanation** where the model exists but is not ready.
Every call site checks availability again at use time; a model that becomes
unavailable mid-session degrades to the feature simply not being offered, never
an error dialog.

All of it lives behind protocols in `AlohaIntelligence`, so `AlohaUI` compiles
and tests without `FoundationModels`.

## 3. Rewrite and proofread

In the composer, behind the ✨ toolbar button. Available only when there is text.

| Action | Prompt intent |
|---|---|
| Proofread | Fix spelling, grammar and punctuation. Change nothing else — not tone, not word choice, not length. |
| Shorten | Reduce to fit the remaining character budget, preserving meaning, mentions, hashtags and links verbatim. |
| Rephrase | Same meaning, different wording. |
| Make friendlier / more formal / more concise | Tone shifts. |

Rules:

- Results are presented in a **diff sheet** — original above, proposal below,
  changes highlighted — with Replace / Copy / Cancel. Never applied in place.
- Mentions (`@…`), hashtags (`#…`) and URLs are extracted before the call,
  replaced with placeholders, and restored afterwards. A rewrite that loses a
  mention is a rewrite that sends a post to the wrong person.
- Output is length-checked against the server's `max_characters` and the
  proposal is rejected (with "That didn't fit") rather than shown over-length.
- Guardrail refusals from the model are shown plainly: "Apple Intelligence
  didn't want to rewrite that." No retry loop, no prompt gymnastics.
- Streaming output is rendered progressively; a cancel stops the generation.

## 4. Alt text generation

The highest-value feature here, and the one most worth getting right.

- Invoked from the ALT badge on any image attachment, or from the
  "some images have no description" warning before posting.
- Uses the multimodal path: the image plus a system prompt describing what good
  alt text is — objective description of content and function, no "image of",
  no speculation about who people are, no invented text, 1–2 sentences,
  under 400 characters.
- The result lands in the alt-text field **as an editable draft**, with a
  clearly-labelled "Generated — please check" note above it that disappears once
  the person edits or confirms.
- **Never posted unreviewed.** If the person posts without opening the field,
  the generated text is used, but the pre-post warning has already told them it
  is there and unreviewed. A setting can make review mandatory.
- Batch generation for a multi-image post processes sequentially with progress,
  and is cancellable.
- Images with faces: the prompt explicitly instructs against identifying or
  describing individuals by name, age, race or presumed gender. Output is
  scanned for obvious violations before presentation.

## 5. Summarise

- On a long thread: "Summarise this thread" in the thread view's menu.
  Input is the plain-text projection of each status plus its author's handle,
  in order, capped at the model's context; longer threads are summarised in
  chunks and the chunk summaries summarised.
- On a long status: "Summarise" in the status menu, shown only for statuses over
  1200 characters.
- Output is presented in a sheet, clearly labelled as a generated summary, with
  a "Read the full thread" action. It is never cached, never shared, and never
  shown inline in the timeline.

## 6. Translation

Two paths, and the server's comes first.

1. **Server translation** where `capabilities.translation` — Nextcloud Social
   implements `POST /api/v1/statuses/{nid}/translate` through Nextcloud's own
   translation provider, and advertises the language pairs at
   `/api/v1/instance/translation_languages`. This is a real translation, it is
   the instance's own provider, and it is what the Translate button uses when
   available. A server with no provider answers **503**, which is presented as
   "Your server can't translate that right now" and falls through to path 2.
2. **On-device** via the `Translation` framework, using
   `TranslationSession` with the detected source language and the device
   language as target. Requires the language pair to be downloaded; the first
   use offers the system download prompt.

- The Translate action appears on any status whose `language` differs from the
  reader's preferred languages.
- Translated text replaces the body in place with an undo affordance and an
  attribution line naming which path produced it ("Translated by your server" /
  "Translated on this device").
- A per-account setting: "Translate automatically" — off by default, and when
  on, only for languages the person has listed.

## 7. Smart features that are deliberately absent

- No AI-generated posts, replies, or DMs. Rewriting what a person wrote is one
  thing; writing for them is another, and this app does not.
- No AI ranking, re-ordering, or "for you" feed. Ordering is the server's.
- No sentiment analysis, no content scoring, no automated moderation decisions.
- No AI-generated images.
- No "explain this post" for content the person can read themselves.

## 8. Privacy statement

The app's privacy screen states, in these terms:

> Intelligence features run entirely on this device using Apple Intelligence.
> Your posts, drafts, images and threads are not sent to Aloha Social, to
> Anthropic, to OpenAI, or to any other company. They are not sent to your
> server either, except when you tap Translate and your server offers
> translation — in which case the post's text goes to your own server's
> translation provider, and nowhere else.

This claim is load-bearing and must stay true. Any change that would make it
false requires the statement to change first.
