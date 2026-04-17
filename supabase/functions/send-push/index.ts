/**
 * Edge Function: send-push
 *
 * Envia push notifications via Firebase Cloud Messaging (FCM HTTP v1 API)
 * para usuários autenticados do Vamos Correr.
 *
 * Entrada (POST JSON):
 *   {
 *     "userId":   "uuid"            // um único usuário OU
 *     "userIds":  ["uuid", ...]     // lista de usuários (um dos dois é obrigatório)
 *     "title":    "string",         // título da notificação
 *     "body":     "string",         // corpo da notificação
 *     "data"?:    { [k:string]: string }, // payload custom (deep links, ids, etc.)
 *     "imageUrl"?: "string"         // URL de imagem opcional
 *   }
 *
 * Saída (JSON):
 *   {
 *     "sent":    number,                 // quantos envios com sucesso
 *     "failed":  number,                 // quantos falharam
 *     "results": Array<{ token: string, success: boolean, error?: string }>,
 *     "simulated"?: boolean              // true se FCM_* não configurado (modo mock)
 *   }
 *
 * Secrets esperadas (Supabase Dashboard → Project → Edge Functions → Secrets):
 *   - FCM_PROJECT_ID            ID do projeto Firebase (ex: vamoscorrer-abc123)
 *   - FCM_SERVICE_ACCOUNT_JSON  Conteúdo do service-account.json (string)
 *   - SUPABASE_URL              (injetada pelo Supabase)
 *   - SUPABASE_SERVICE_ROLE_KEY (injetada pelo Supabase)
 *
 * Se FCM_PROJECT_ID ou FCM_SERVICE_ACCOUNT_JSON não estiverem configurados,
 * a função roda em modo MOCK: faz lookup dos tokens e loga "send simulado",
 * sem chamar o FCM.
 */

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2.49.8';

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info',
  'Access-Control-Max-Age': '86400',
};

interface SendPushRequest {
  userId?: string;
  userIds?: string[];
  title: string;
  body: string;
  data?: Record<string, string>;
  imageUrl?: string;
}

interface SendResult {
  token: string;
  success: boolean;
  error?: string;
}

interface SendPushResponse {
  sent: number;
  failed: number;
  results: SendResult[];
  simulated?: boolean;
}

interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

// ────────────────────────────────────────────────────────────────
// OAuth2: gera access_token a partir da service account (JWT RS256).
// Cache em memória: reutiliza o token enquanto válido (~55 minutos).
// ────────────────────────────────────────────────────────────────
let cachedAccessToken: { token: string; expiresAt: number } | null = null;

async function getAccessToken(serviceAccount: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  if (cachedAccessToken && cachedAccessToken.expiresAt - 60 > now) {
    return cachedAccessToken.token;
  }

  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: serviceAccount.token_uri ?? 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };

  const encoder = new TextEncoder();
  const base64url = (buf: ArrayBuffer | Uint8Array): string => {
    const bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
    let str = '';
    for (let i = 0; i < bytes.byteLength; i++) str += String.fromCharCode(bytes[i]);
    return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  };

  const headerB64 = base64url(encoder.encode(JSON.stringify(header)));
  const payloadB64 = base64url(encoder.encode(JSON.stringify(payload)));
  const toSign = `${headerB64}.${payloadB64}`;

  // Importa a chave PEM como CryptoKey para RS256
  const pem = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');
  const pemBytes = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    encoder.encode(toSign),
  );
  const jwt = `${toSign}.${base64url(signature)}`;

  const tokenRes = await fetch(
    serviceAccount.token_uri ?? 'https://oauth2.googleapis.com/token',
    {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt,
      }),
    },
  );

  if (!tokenRes.ok) {
    const errText = await tokenRes.text();
    throw new Error(`OAuth2 token request failed (${tokenRes.status}): ${errText}`);
  }

  const tokenJson = (await tokenRes.json()) as {
    access_token: string;
    expires_in: number;
  };

  cachedAccessToken = {
    token: tokenJson.access_token,
    expiresAt: now + tokenJson.expires_in,
  };

  return tokenJson.access_token;
}

// ────────────────────────────────────────────────────────────────
// Envia 1 push via FCM HTTP v1.
// ────────────────────────────────────────────────────────────────
async function sendFcmMessage(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data?: Record<string, string>,
  imageUrl?: string,
): Promise<SendResult> {
  try {
    const message: Record<string, unknown> = {
      token,
      notification: {
        title,
        body,
        ...(imageUrl ? { image: imageUrl } : {}),
      },
      ...(data ? { data } : {}),
      android: {
        priority: 'HIGH',
        notification: {
          sound: 'default',
          ...(imageUrl ? { image: imageUrl } : {}),
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            'mutable-content': imageUrl ? 1 : undefined,
          },
        },
        ...(imageUrl
          ? { fcm_options: { image: imageUrl } }
          : {}),
      },
    };

    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          authorization: `Bearer ${accessToken}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify({ message }),
      },
    );

    if (!res.ok) {
      const errText = await res.text();
      return { token, success: false, error: `FCM ${res.status}: ${errText}` };
    }

    return { token, success: true };
  } catch (err) {
    return {
      token,
      success: false,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Método não permitido' }), {
      status: 405,
      headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
    });
  }

  // Parse body
  let body: SendPushRequest;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'JSON inválido' }), {
      status: 400,
      headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
    });
  }

  const { userId, userIds, title, body: msgBody, data, imageUrl } = body;

  if ((!userId && (!userIds || userIds.length === 0)) || !title || !msgBody) {
    return new Response(
      JSON.stringify({
        error: 'Campos obrigatórios: (userId | userIds), title, body',
      }),
      { status: 400, headers: { ...CORS_HEADERS, 'content-type': 'application/json' } },
    );
  }

  const targetUserIds: string[] = userIds && userIds.length > 0 ? userIds : [userId as string];

  // Supabase admin client (injetado pelo runtime)
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(
      JSON.stringify({ error: 'Supabase credentials missing in runtime' }),
      { status: 500, headers: { ...CORS_HEADERS, 'content-type': 'application/json' } },
    );
  }
  const admin = createClient(supabaseUrl, serviceRoleKey);

  // Busca tokens ativos (Android por enquanto; iOS também se existir)
  const { data: tokenRows, error: tokenErr } = await admin
    .from('push_tokens')
    .select('token, plataforma, usuario_id')
    .in('usuario_id', targetUserIds)
    .eq('ativo', true);

  if (tokenErr) {
    return new Response(
      JSON.stringify({ error: `Erro ao buscar tokens: ${tokenErr.message}` }),
      { status: 500, headers: { ...CORS_HEADERS, 'content-type': 'application/json' } },
    );
  }

  const fcmTokens = (tokenRows ?? []).filter(
    (r) => r.plataforma === 'android' || r.plataforma === 'ios',
  );

  if (fcmTokens.length === 0) {
    return new Response(
      JSON.stringify({ sent: 0, failed: 0, results: [] } satisfies SendPushResponse),
      { status: 200, headers: { ...CORS_HEADERS, 'content-type': 'application/json' } },
    );
  }

  // Modo MOCK: se não há credenciais FCM, apenas loga.
  const fcmProjectId = Deno.env.get('FCM_PROJECT_ID') ?? '';
  const fcmServiceAccountRaw = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON') ?? '';

  if (!fcmProjectId || !fcmServiceAccountRaw) {
    console.log(
      `[send-push] SIMULADO (FCM secrets ausentes): ${fcmTokens.length} tokens, title="${title}"`,
    );
    const results: SendResult[] = fcmTokens.map((r) => ({
      token: r.token,
      success: true,
      error: 'simulated',
    }));

    // Audit log não bloqueante
    try {
      await admin.from('audit_log').insert({
        usuario_id: targetUserIds[0],
        acao: 'send_push',
        recurso: 'push_notification',
        dados_depois: {
          simulated: true,
          sent: results.length,
          title,
          body: msgBody,
          targetUserIds,
        },
      });
    } catch (err) {
      console.error('audit_log falhou (não bloqueante):', err);
    }

    return new Response(
      JSON.stringify({
        sent: results.length,
        failed: 0,
        results,
        simulated: true,
      } satisfies SendPushResponse),
      { status: 200, headers: { ...CORS_HEADERS, 'content-type': 'application/json' } },
    );
  }

  // Modo REAL: chama FCM HTTP v1
  let serviceAccount: ServiceAccount;
  try {
    serviceAccount = JSON.parse(fcmServiceAccountRaw) as ServiceAccount;
  } catch (err) {
    return new Response(
      JSON.stringify({
        error: `FCM_SERVICE_ACCOUNT_JSON inválido: ${
          err instanceof Error ? err.message : String(err)
        }`,
      }),
      { status: 500, headers: { ...CORS_HEADERS, 'content-type': 'application/json' } },
    );
  }

  let accessToken: string;
  try {
    accessToken = await getAccessToken(serviceAccount);
  } catch (err) {
    return new Response(
      JSON.stringify({
        error: `Falha ao obter access token FCM: ${
          err instanceof Error ? err.message : String(err)
        }`,
      }),
      { status: 500, headers: { ...CORS_HEADERS, 'content-type': 'application/json' } },
    );
  }

  // Envio paralelo (com limite implícito de ~N tokens por request)
  const results = await Promise.all(
    fcmTokens.map((r) =>
      sendFcmMessage(accessToken, fcmProjectId, r.token, title, msgBody, data, imageUrl),
    ),
  );

  const sent = results.filter((r) => r.success).length;
  const failed = results.length - sent;

  // Marca tokens inválidos (UNREGISTERED / INVALID_ARGUMENT) como inativos
  const invalidTokens = results
    .filter(
      (r) =>
        !r.success &&
        (r.error?.includes('UNREGISTERED') ||
          r.error?.includes('INVALID_ARGUMENT') ||
          r.error?.includes('NOT_FOUND')),
    )
    .map((r) => r.token);

  if (invalidTokens.length > 0) {
    try {
      await admin
        .from('push_tokens')
        .update({ ativo: false })
        .in('token', invalidTokens);
    } catch (err) {
      console.error('Erro ao desativar tokens inválidos (não bloqueante):', err);
    }
  }

  // Audit log não bloqueante
  try {
    await admin.from('audit_log').insert({
      usuario_id: targetUserIds[0],
      acao: 'send_push',
      recurso: 'push_notification',
      dados_depois: {
        sent,
        failed,
        title,
        body: msgBody,
        targetUserIds,
        invalidTokens: invalidTokens.length,
      },
    });
  } catch (err) {
    console.error('audit_log falhou (não bloqueante):', err);
  }

  return new Response(
    JSON.stringify({ sent, failed, results } satisfies SendPushResponse),
    { status: 200, headers: { ...CORS_HEADERS, 'content-type': 'application/json' } },
  );
});
