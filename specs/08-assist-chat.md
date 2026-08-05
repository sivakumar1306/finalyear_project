# 08 — AI Assist (Chat)

| Field | Value |
|-------|-------|
| **Status** | Partial (client shipped; depends on external chat API) |
| **Key code** | `lib/screens/assist/*`, `lib/services/chat_api_service.dart`, `lib/config.dart` |

---

## 1. Purpose

Provide a free-text health Q&A assistant (“Assist” tab) that can discuss vitals-oriented questions and show conversation history.

---

## 2. Backend

- **Not** Supabase chat tables as the primary runtime path for messages (unless dual-written).  
- **REST API** configured via `AppConfig.chatApiBaseUrl` (`CHAT_API_BASE_URL` define or default Railway URL).  
- Endpoints (conceptual):  
  - `POST /chat` — send message, return assistant reply (+ conversation id).  
  - `GET /history/{userId}` — list conversations.  
  - `GET /history/messages/{conversationId}` — transcript.

Backend implementation lives **outside** this Flutter repo.

---

## 3. Functional requirements

| ID | Requirement |
|----|-------------|
| CHAT-01 | Assist tab opens chat UI for authenticated users. |
| CHAT-02 | User can send free-text messages and receive assistant replies. |
| CHAT-03 | Conversation id threads multi-turn context server-side. |
| CHAT-04 | History screen lists past conversations and opens read-only transcripts. |
| CHAT-05 | Voice input sheet may capture speech-to-text when permissions allow (`speech_to_text`). |
| CHAT-06 | Optional vital “chat cards” (HR, SpO2, BP, HRV, steps, sleep highlights) can summarize ring/provider data inside Assist context. |
| CHAT-07 | Errors (timeout, 5xx) surface a user-visible failure state without crashing the tab. |
| CHAT-08 | API base URL must be environment-configurable for prod vs local. |

---

## 4. UX notes

- Session message list may be local to the screen instance; durable history is server-side.  
- Design: same dark glass system; gold accent for primary send/voice actions (`DESIGN.md`).  
- Insights header / key-change cards are presentational helpers, not separate product modules.

---

## 5. Non-functional

| ID | Requirement |
|----|-------------|
| CHAT-20 | Do not send ring firmware secrets or raw auth refresh tokens to chat API beyond agreed user identity. |
| CHAT-21 | Prefer user id already known from Supabase session. |
| CHAT-22 | Assistant is **not** a doctor; UI or backend should avoid definitive medical diagnosis claims where feasible. |

---

## 6. Acceptance criteria

- [ ] With reachable chat API, user can complete a multi-turn conversation.  
- [ ] Conversation appears in history list after refresh.  
- [ ] Unreachable API shows error, not infinite spinner.  
- [ ] Voice sheet requests mic permission before listening.

---

## 7. Open items

- Confirm production base URL ownership and SLA.  
- Whether messages also land in Supabase `conversations`/`messages` (migration exists for account deletion) for unified GDPR delete.

---

## 8. Related

- [12-non-functional.md](./12-non-functional.md)  
- `lib/config.dart`  
