// send-emergency-alert — Supabase Edge Function
//
// Cloud half of the emergency alerting system (docs/sms/emergency-alerting-system.md):
//   1. Logs the alert into `emergency_alerts` (ledger + 15-min cooldown anchor).
//   2. Sends an SMS to EVERY listed contact via Twilio (guarded by env — skipped,
//      and recorded as such, when Twilio is not configured).
//   3. Sends an FCM push notification ONLY to contacts who have an ACCEPTED
//      `caregiver_links` row with the wearer (two-sided consent) and a registered
//      token in `user_push_tokens`.
//   4. Records every attempt in `emergency_alert_deliveries` — real delivery proof.
//
// Auth: caller must be the authenticated wearer (Bearer <access_token>); the same
// JWT the native app already caches in SupabaseConfig.accessToken.
//
// Request body:
// {
//   "reason": "fall" | "prediction" | "manual",
//   "message": "optional override text",
//   "triggeredBy": "device" | "manual" | "cloud_fallback",
//   "location": { "lat": 12.97, "lng": 77.59, "accuracy": 8.5 },   // optional
//   "contacts": [ { "name": "Anna", "phone": "+91..." }, ... ]
// }
//
// Required secrets (supabase secrets set ...):
//   TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN / TWILIO_FROM_NUMBER   — cloud SMS
//   FCM_PROJECT_ID / GOOGLE_SERVICE_ACCOUNT_JSON                  — FCM push
// Both are optional at runtime; missing providers degrade gracefully and are
// logged as `skipped` delivery rows.

import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const COOLDOWN_MS = 15 * 60 * 1000;

interface Contact {
  name: string;
  phone: string;
}

interface AlertRequest {
  reason?: string;
  message?: string;
  triggeredBy?: string;
  location?: { lat?: number; lng?: number; accuracy?: number };
  contacts: Contact[];
}

// ── helpers ──────────────────────────────────────────────────────────────────

export function normalizePhone(phone: string): string {
  return (phone ?? "").replace(/[^0-9+]/g, "");
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function mapsLink(location?: { lat?: number; lng?: number }): string | null {
  if (
    location &&
    typeof location.lat === "number" &&
    typeof location.lng === "number" &&
    Math.abs(location.lat) <= 90 &&
    Math.abs(location.lng) <= 180
  ) {
    return `https://maps.google.com/?q=${location.lat.toFixed(6)},${location.lng.toFixed(6)}`;
  }
  return null;
}

const REASON_LABELS: Record<string, string> = {
  fall: "possible fall detected",
  prediction: "fall risk alert",
  manual: "needs help",
};

function buildMessage(
  wearerName: string,
  reason: string,
  override: string | undefined,
  link: string | null,
): string {
  if (override && override.trim().length > 0) {
    return link ? `${override.trim()} ${link}` : override.trim();
  }
  const label = REASON_LABELS[reason] ?? "needs help";
  let msg = `${wearerName} — ${label}. Please check on them. Sent by SUNDR`;
  if (link) msg += `. Live location: ${link}`;
  return msg;
}

// ── FCM HTTP v1 (RS256 service-account flow, no external deps) ───────────────

interface ServiceAccount {
  client_email: string;
  private_key: string;
}

function base64UrlEncode(data: Uint8Array | string): string {
  const bytes =
    typeof data === "string" ? new TextEncoder().encode(data) : data;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

let cachedAccessToken: { token: string; expiresAt: number } | null = null;

async function getFcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Date.now();
  if (cachedAccessToken && cachedAccessToken.expiresAt > now + 60_000) {
    return cachedAccessToken.token;
  }
  const iat = Math.floor(now / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64UrlEncode(
    JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat,
      exp: iat + 3600,
    }),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const assertion = `${header}.${claims}.${base64UrlEncode(new Uint8Array(sig))}`;

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!resp.ok) {
    throw new Error(`FCM token exchange failed: HTTP ${resp.status}`);
  }
  const data = await resp.json();
  cachedAccessToken = {
    token: data.access_token,
    expiresAt: now + (data.expires_in ?? 3500) * 1000,
  };
  return cachedAccessToken.token;
}

async function sendFcmPush(
  sa: ServiceAccount,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<{ ok: boolean; detail: string }> {
  try {
    const accessToken = await getFcmAccessToken(sa);
    const resp = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data,
            android: {
              priority: "HIGH",
              notification: { channel_id: "companion_alerts" },
            },
          },
        }),
      },
    );
    if (!resp.ok) {
      const text = await resp.text();
      return { ok: false, detail: `HTTP ${resp.status}: ${text.slice(0, 200)}` };
    }
    return { ok: true, detail: "accepted" };
  } catch (e) {
    return { ok: false, detail: String(e).slice(0, 200) };
  }
}

// ── Twilio SMS ───────────────────────────────────────────────────────────────

async function sendTwilioSms(
  accountSid: string,
  authToken: string,
  fromNumber: string,
  toPhone: string,
  body: string,
): Promise<{ ok: boolean; status: string; detail: string }> {
  try {
    const resp = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`,
      {
        method: "POST",
        headers: {
          Authorization: `Basic ${btoa(`${accountSid}:${authToken}`)}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({ To: toPhone, From: fromNumber, Body: body }),
      },
    );
    const data = await resp.json();
    if (!resp.ok) {
      return {
        ok: false,
        status: "failed",
        detail: String(data?.message ?? `HTTP ${resp.status}`).slice(0, 200),
      };
    }
    // Twilio status: queued/accepted/sent → provider will attempt delivery.
    return { ok: true, status: data.status ?? "queued", detail: `sid=${data.sid ?? ""}` };
  } catch (e) {
    return { ok: false, status: "failed", detail: String(e).slice(0, 200) };
  }
}

// ── main handler ─────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Missing bearer token" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    // User-scoped client — verifies the caller's JWT via auth.getUser().
    const userClient: SupabaseClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
      auth: { persistSession: false },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser(jwt);
    if (userError || !userData?.user) {
      return json({ error: "Unauthorized" }, 401);
    }
    const wearerId = userData.user.id;

    // Service-role client for cross-user reads/writes (links, tokens, ledger).
    const admin: SupabaseClient = createClient(
      supabaseUrl,
      serviceKey ?? anonKey,
      { auth: { persistSession: false } },
    );

    const payload = (await req.json()) as AlertRequest;
    const contacts = (payload.contacts ?? [])
      .map((c) => ({ name: c.name ?? "", phone: normalizePhone(c.phone ?? "") }))
      .filter((c) => c.phone.length > 0);
    if (contacts.length === 0) {
      return json({ error: "No valid contacts provided" }, 400);
    }

    // Cooldown — mirrors the device-side 15-min anti-spam window. Manual sends bypass it.
    const triggeredBy = payload.triggeredBy ?? "manual";
    if (triggeredBy !== "manual") {
      const since = new Date(Date.now() - COOLDOWN_MS).toISOString();
      const { data: recent } = await admin
        .from("emergency_alerts")
        .select("id")
        .eq("wearer_user_id", wearerId)
        .gte("triggered_at", since)
        .limit(1);
      if (recent && recent.length > 0) {
        return json({
          ok: true,
          skipped: "cooldown",
          detail: "An alert was already sent within the last 15 minutes",
        });
      }
    }

    // Wearer profile for message personalization.
    const { data: profile } = await admin
      .from("user_profiles")
      .select("full_name, phone")
      .eq("id", wearerId)
      .maybeSingle();
    const wearerName = profile?.full_name || "A SUNDR user";
    const wearerPhone = normalizePhone(profile?.phone ?? "");

    const reason = payload.reason ?? "manual";
    const link = mapsLink(payload.location);
    const message = buildMessage(wearerName, reason, payload.message, link);

    // Ledger row first — everything below references it.
    const { data: alertRow, error: alertError } = await admin
      .from("emergency_alerts")
      .insert({
        wearer_user_id: wearerId,
        reason,
        message,
        location_lat: payload.location?.lat ?? null,
        location_lng: payload.location?.lng ?? null,
        location_accuracy_m: payload.location?.accuracy ?? null,
        triggered_by: triggeredBy,
      })
      .select("id")
      .single();
    if (alertError || !alertRow) {
      return json(
        { error: `Failed to log alert: ${alertError?.message ?? "unknown"}` },
        500,
      );
    }
    const alertId = alertRow.id as string;

    // Accepted caregivers of this wearer (push recipients).
    const { data: links } = await admin
      .from("caregiver_links")
      .select("caregiver_user_id, contact_phone")
      .eq("wearer_user_id", wearerId);
    const linkedCaregiverIds = new Set(
      (links ?? []).map((l) => l.caregiver_user_id as string),
    );

    // Resolve each contact phone → Sundr account (for push eligibility).
    const resolvedUsers = new Map<string, string>(); // normalized phone → user id
    for (const c of contacts) {
      const { data: match } = await admin.rpc("resolve_sundr_user", {
        p_phone: c.phone,
      });
      const userId = match?.[0]?.user_id as string | undefined;
      if (userId) resolvedUsers.set(c.phone, userId);
    }

    // Push tokens for eligible caregivers.
    const eligibleCaregiverIds = [...new Set([...resolvedUsers.values()])]
      .filter((uid) => linkedCaregiverIds.has(uid));
    const tokensByUser = new Map<string, string[]>();
    if (eligibleCaregiverIds.length > 0) {
      const { data: tokenRows } = await admin
        .from("user_push_tokens")
        .select("user_id, fcm_token")
        .in("user_id", eligibleCaregiverIds);
      for (const row of tokenRows ?? []) {
        const list = tokensByUser.get(row.user_id) ?? [];
        list.push(row.fcm_token);
        tokensByUser.set(row.user_id, list);
      }
    }

    // Providers (optional — degrade gracefully).
    const twilioSid = Deno.env.get("TWILIO_ACCOUNT_SID");
    const twilioToken = Deno.env.get("TWILIO_AUTH_TOKEN");
    const twilioFrom = Deno.env.get("TWILIO_FROM_NUMBER");
    const twilioReady = Boolean(twilioSid && twilioToken && twilioFrom);

    const fcmProjectId = Deno.env.get("FCM_PROJECT_ID");
    const saRaw = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
    let sa: ServiceAccount | null = null;
    if (fcmProjectId && saRaw) {
      try {
        sa = JSON.parse(saRaw) as ServiceAccount;
      } catch {
        sa = null;
      }
    }

    const title = "SUNDR emergency alert";
    const pushBody = link ? `${message}` : message;
    const deliveries: Array<Record<string, unknown>> = [];
    let smsSent = 0;
    let smsFailed = 0;
    let pushSent = 0;
    let pushFailed = 0;

    for (const c of contacts) {
      // 1. Cloud SMS → every listed contact.
      if (twilioReady) {
        const result = await sendTwilioSms(
          twilioSid!,
          twilioToken!,
          twilioFrom!,
          c.phone,
          message,
        );
        if (result.ok) smsSent++;
        else smsFailed++;
        deliveries.push({
          alert_id: alertId,
          contact_name: c.name,
          contact_phone: c.phone,
          channel: "cloud_sms",
          status: result.ok ? "sent" : "failed",
          detail: result.detail,
        });
      } else {
        deliveries.push({
          alert_id: alertId,
          contact_name: c.name,
          contact_phone: c.phone,
          channel: "cloud_sms",
          status: "skipped",
          detail: "Twilio not configured",
        });
      }

      // 2. FCM push → only accepted, linked Sundr users.
      const sundrUserId = resolvedUsers.get(c.phone);
      const isLinkedCaregiver =
        sundrUserId !== undefined && linkedCaregiverIds.has(sundrUserId);
      if (!isLinkedCaregiver) continue;

      const tokens = tokensByUser.get(sundrUserId!) ?? [];
      if (tokens.length === 0) {
        deliveries.push({
          alert_id: alertId,
          caregiver_user_id: sundrUserId!,
          contact_name: c.name,
          contact_phone: c.phone,
          channel: "fcm_push",
          status: "skipped",
          detail: "No registered device tokens",
        });
        continue;
      }
      if (!sa) {
        deliveries.push({
          alert_id: alertId,
          caregiver_user_id: sundrUserId!,
          contact_name: c.name,
          contact_phone: c.phone,
          channel: "fcm_push",
          status: "skipped",
          detail: "FCM not configured",
        });
        continue;
      }
      for (const token of tokens) {
        const result = await sendFcmPush(sa, fcmProjectId!, token, title, pushBody, {
          alertId,
          reason,
          wearerName,
          wearerId,
          wearerPhone,
          mapsUrl: link ?? "",
        });
        if (result.ok) pushSent++;
        else pushFailed++;
        deliveries.push({
          alert_id: alertId,
          caregiver_user_id: sundrUserId!,
          contact_name: c.name,
          contact_phone: c.phone,
          channel: "fcm_push",
          status: result.ok ? "sent" : "failed",
          detail: result.detail,
        });
      }
    }

    if (deliveries.length > 0) {
      await admin.from("emergency_alert_deliveries").insert(deliveries);
    }

    return json({
      ok: true,
      alertId,
      sms: { sent: smsSent, failed: smsFailed, providerReady: twilioReady },
      push: { sent: pushSent, failed: pushFailed, providerReady: sa !== null },
    });
  } catch (e) {
    return json({ error: String(e)?.slice(0, 300) }, 500);
  }
});
