# 08 — AI Assist (Chat) (INTEGRATED)

| Field | Value |
|-------|-------|
| **Status** | Partial (client shipped; depends on external Railway chat API) |
| **Key code** | `lib/screens/assist/*` (`chat_screen.dart`, `chat_vital_shell.dart`, `insights_header.dart`, `key_change_card.dart`, `*_chat_card.dart`, `voice_listening_sheet.dart`), `lib/services/chat_api_service.dart` (`chat`/`getConversations`/`getMessages`/`getInsights`), `lib/services/insights_service.dart` (`InsightsService`, `HeadlineSpan`, `InsightsResult`), `lib/services/health_engine/health_engine.dart` (`assessBloodPressure`, `noteFor`), `lib/screens/health/vital_note_screen.dart` (`VitalNoteScreen.fromData`/`fromMetric`), `lib/config.dart` (`AppConfig.chatApiBaseUrl`) |
| **Backend** | External REST (Railway) — **not** Supabase chat tables as primary runtime path |

---

## 1. Purpose

Free-text health Q&A assistant ("Assist" tab) for vitals-oriented questions + conversation history + server-computed insights header + optional vital chat cards + voice input.

---

## 2. Backend & API contracts (keep table)

- Base URL: `AppConfig.chatApiBaseUrl` = `String.fromEnvironment('CHAT_API_BASE_URL', defaultValue: 'https://vtialringbackendversion1-production-a3e4.up.railway.app/api/v1')`. Environment-configurable for prod vs local. Implementation lives outside Flutter repo.
- Auth: `SupabaseService.currentUser?.id` as `user_id`; `SupabaseService.accessToken` as `Authorization: Bearer` in `_authHeaders` (`Content-Type: application/json`).
- Timeouts (verified in code; eval 05.9 quoted older 20 s for insights — code is truth):

| Constant | Value | Covers |
|----------|-------|--------|
| `_timeout` | `Duration(seconds: 15)` | `getConversations`, `getMessages`, others |
| `_chatTimeout` | `Duration(seconds: 60)` | `POST /chat` (LLM agent tool-routing legitimately 20–30+ s; 15 s cut off successes; see `graph.py [TIMING]` logs) |
| `_insightsTimeout` | `Duration(seconds: 120)` | `GET /insights` (7/30/90-day server aggregation; backend caps at `MAX_INSIGHT_DAYS`) |

| Endpoint | Method | Contract |
|----------|--------|----------|
| `/chat` | `POST` body `{message, user_id (or 'anonymous'), conversation_id}` → `{reply, conversation_id}` | `ChatApiService.chat(message, conversationId)` with `.timeout(_chatTimeout)`; `_decodeOrThrow` requires 2xx + `Map<String,dynamic>` else `Exception('Request failed (status): body')` / `('Unexpected response shape')` |
| `/history/{userId}` | `GET` with `_authHeaders`, `.timeout(_timeout)` | `getConversations()`; null user → `{'conversations': []}`; catch-all → `{'conversations': []}` (never hang/crash) |
| `/history/messages/{conversationId}` | `GET` with `_authHeaders`, `.timeout(_timeout)` | `getMessages(conversationId)`; catch-all → `{'messages': []}` |
| `/insights/{userId}` | `GET` with `_authHeaders`, `.timeout(_insightsTimeout)` | `getInsights()`; null user/token → fallback headline `Sign in to see your trends`; catch (dead/renamed Railway 404 "Application not found") → fallback `Your trends will appear here once we have enough recent readings.` + `error` string (resilient, no `app_incidents` flood via FutureBuilder zone) |

---

## 3. Functional requirements

| ID | Requirement |
|----|-------------|
| CHAT-01 | Assist tab opens chat UI for authenticated users (`chat_screen.dart`); anonymous still sends with `user_id='anonymous'` but backend never saves history for anonymous. |
| CHAT-02 | User sends free-text (`_sendMessage([suggestion])`, `_controller.text.trim()`) and receives assistant reply via `ChatApiService.chat(payloadText, _conversationId)`; updates `_conversationId = result['conversation_id']`. |
| CHAT-03 | Conversation id threads multi-turn server-side; persisted per-user in prefs `chat_conversation_id_{userId}` (`_conversationPrefsKey`); survives app restart; `_restoreConversation()` prefers cached id, else most-recent server conversation (`conversations.first['id']`), then loads transcript. `NEW_CHAT` sentinel means user started new chat — do not restore. |
| CHAT-04 | History lists past conversations and opens read-only transcripts (`getConversations`/`getMessages`); `_startNewChat()` clears view with note "This clears the current conversation from view. Your history isn't deleted." |
| CHAT-05 | Voice input sheet captures speech-to-text when permissions allow: `VoiceListeningSheet.show(context)` → transcript; `speech_to_text` `SpeechToText.listen` with `SpeechListenOptions(listenFor: 30s, ListenMode.confirmation)`, `_isListening` state, `_onListenError`, mic-permission pill "Microphone permission is needed for voice input." Permission `RECORD_AUDIO` justified (`speech_to_text` voice sheet `lib/screens/assist/voice_listening_sheet.dart`; manifest + `main.dart` request). |
| CHAT-06 | Optional vital chat cards summarize ring/provider data inside Assist context: `heart_rate_chat_card`, `blood_oxygen_chat_card`, `blood_pressure_chat_card`, `hrv_chat_card`, `stress_chat_card`, `temperature_chat_card`, `steps_chat_card`, `sleep_highlights_card`, `cycle_chat_card`, `chat_vital_shell.dart`. Presentational helpers, not separate modules. |
| CHAT-07 | Errors (timeout, 5xx, Railway 404) surface user-visible failure/fallback state without crashing tab; `_decodeOrThrow` exceptions shown, not infinite spinner. |
| CHAT-08 | API base URL environment-configurable (`CHAT_API_BASE_URL` define or default Railway URL). |
| CHAT-09 | Insights header (`insights_header.dart`, `InsightsHeader`) renders server `headline_parts[{text,highlight}]` (highlight in gold), `subtext`, `updates` key-change cards (`key_change_card.dart`); fallback card when backend dead. |
| CHAT-10 | Local `InsightsService` (`HeadlineSpan(text,highlight)`, `InsightMetric`, `InsightsResult{headline,subtext,...}`, `HistoryService.splitDelta` half-split delta, `_buildHeadline(sleepTrend,bpTrend)`) composes e.g. "Your sleep is improving, but blood pressure is high" / "Your blood pressure is {high} this period" / "Your sleep is improving, keep it up" / "Your vitals look stable". BP wording delegates to `HealthEngine.instance.assessBloodPressure(recentAvgSystolic,80)` so headline never disagrees with card staging (Elevated/Stage1/2 → "high"; <90 → "low"). |
| CHAT-11 | Vital explainer deep-link: `VitalNoteScreen.fromData(note)` / `fromMetric` where `note = HealthEngine.instance.noteFor(HealthMetric.*)` (`VitalNoteData{title,heading,intro,ranges,tips,didYouKnow}`, `colorKey → AppTheme`); no screen owns copy (see health-eng `advice.md`). |
| CHAT-12 | Suggestion chips (`_SuggestionChip(text,onTap)`) send canned prompts; disclaimer `This is just a suggestion, not medical advice.` always visible. |
| CHAT-13 | New-chat, restore, and per-user isolation: prefs key includes userId so one user's conversation never leaks into another's screen. |

---

## 4. UX notes

- Session message list may be local to screen instance; durable history server-side.
- Design: same dark glass system; gold accent for primary send/voice actions (`DESIGN.md`); `InsightsHeaderState` headline highlight in gold.
- Insights header / key-change cards are presentational helpers, not separate product modules.
- Voice sheet: "listening..." + "Speak now... listening for your voice" states; 30 s cap; confirmation mode.
- Suggestion disclaimer is a safety requirement, not decoration (see CHAT-22).

---

## 5. Non-functional

| ID | Requirement |
|----|-------------|
| CHAT-20 | Do not send ring firmware secrets or raw auth refresh tokens beyond agreed user identity (`user_id` + Bearer access token only). |
| CHAT-21 | Prefer user id from Supabase session (`SupabaseService.currentUser?.id`); `anonymous` fallback sends but saves nothing. |
| CHAT-22 | Assistant is **not** a doctor; UI + backend avoid definitive diagnosis claims where feasible; suggestion disclaimer (CHAT-12) + "not medical advice" copy mandatory. |
| CHAT-23 | No secrets committed for chat backend; explicit timeouts on every call (60/120/15 s); failures return fallback payloads, never throw to zone (`app_incidents` flood guard). |
| CHAT-24 | `RECORD_AUDIO` permission justified solely by voice sheet; denial handled gracefully (pill, no crash). |

---

## 6. Data & sync notes (integrated)

- Supabase `conversations`/`messages` legacy tables are **intentionally not created** (eval 05.1): no current code reads/writes them; chat history lives on Railway. They are only referenced by old `delete_user_account()` which now skips missing tables via `to_regclass` + `information_schema` checks (eval 05.10 ✅ fixed). Open item below tracks whether to dual-write for unified GDPR delete.
- Chat Railway timeouts feed spec 11 incident hygiene: fallback cards prevent `app_incidents` spam; `IncidentService` rate 10/60 s, dedupe 60 s, caps 2000/8000, PII scrub apply if chat errors are ever reported.

---

## 7. Acceptance criteria

- [ ] With reachable chat API, multi-turn conversation completes; conversation persists via `chat_conversation_id_{userId}` after restart.
- [ ] Conversation appears in history list after refresh; transcript opens read-only.
- [ ] Unreachable API (timeout/404/5xx) shows error/fallback card, not infinite spinner; no `app_incidents` flood.
- [ ] Voice sheet requests mic permission before listening; 30 s cap; transcript inserts into composer.
- [ ] Insights header shows server `headline_parts` with gold highlights, or fallback text when offline.
- [ ] Suggestion chips + disclaimer visible; disclaimer states not medical advice.
- [ ] Anonymous send works but saves no history; signed-in save threads by `conversation_id`.

---

## 8. Open items

- Confirm production Railway base URL ownership and SLA (`https://vtialringbackendversion1-production-a3e4.up.railway.app/api/v1` vs local define).
- Whether messages also land in Supabase `conversations`/`messages` for unified GDPR delete (migration exists for account deletion; dual-write undecided).
- Backend `MAX_INSIGHT_DAYS` cap vs app `days_used` display contract (backend reports real days used).
- Eval timeout drift: 05.9 documented `_insightsTimeout 20 s`; code is now 120 s — keep code as truth, update eval reference.

---

## 9. Related

- [12-non-functional.md](./12-non-functional.md) (permissions, privacy)
- [11-data-sync-storage.md](./11-data-sync-storage.md) (delete wipe, incidents)
- `lib/config.dart` (`CHAT_API_BASE_URL`, Supabase URL/anon)
- `docs/health-eng/advice.md` (`noteFor`, `VitalNoteScreen.fromData`), `docs/archive/eval/05-BACKEND-DATA-PERSISTENCE.md` §5.9
