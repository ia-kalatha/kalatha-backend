# send-push — FCM HTTP v1

Edge function que envia push notifications via **Firebase Cloud Messaging HTTP v1 API** para usuários autenticados do Vamos Correr.

- Busca tokens ativos em `push_tokens` filtrando por `usuario_id`.
- Gera OAuth2 access token a partir da service account (JWT RS256, cache in-memory).
- Envia POST para `https://fcm.googleapis.com/v1/projects/{PROJECT_ID}/messages:send`.
- Marca automaticamente como `ativo=false` tokens que retornarem `UNREGISTERED` / `INVALID_ARGUMENT` / `NOT_FOUND`.
- Grava trilha de auditoria em `audit_log` (não bloqueante).
- **Modo mock**: se `FCM_PROJECT_ID` ou `FCM_SERVICE_ACCOUNT_JSON` não estiverem configurados, a função loga `[send-push] SIMULADO` e responde `{ simulated: true }` — útil enquanto Firebase ainda não foi provisionado.

## Contrato

**Request (POST JSON):**

```json
{
  "userId": "uuid",              // um dos dois é obrigatório
  "userIds": ["uuid", "uuid"],   // quando broadcast a múltiplos usuários
  "title": "string",
  "body": "string",
  "data": { "screen": "detalhe-desafio", "desafioId": "..." },
  "imageUrl": "https://..."
}
```

**Response:**

```json
{
  "sent": 3,
  "failed": 1,
  "results": [
    { "token": "...", "success": true },
    { "token": "...", "success": false, "error": "FCM 404: UNREGISTERED" }
  ],
  "simulated": false
}
```

## Setup Firebase (FCM) — Android

Estes passos **não são programáveis**: precisam ser feitos manualmente no console.

1. Acessar <https://console.firebase.google.com> e criar um novo projeto (ou usar existente).
2. Dentro do projeto: **Add app → Android**.
3. Package name: `com.vamoscorrer.app` (deve bater com `applicationId` em `android/app/build.gradle`).
4. Baixar `google-services.json` e colocar em `android/app/google-services.json`.
   - **Este arquivo NÃO deve ser commitado.** O repo já tem um placeholder e a entrada no `.gitignore`.
5. **Project Settings → Cloud Messaging**: habilitar **FCM API (V1)** (legacy pode ficar desabilitado).
6. **Project Settings → Service Accounts → Firebase Admin SDK → Generate new private key** → baixa JSON.
7. No **Supabase Dashboard → Project → Edge Functions → Secrets**, adicionar:
   - `FCM_PROJECT_ID` → ID do projeto Firebase (ex: `vamoscorrer-abc123`, visível em Project Settings → General).
   - `FCM_SERVICE_ACCOUNT_JSON` → conteúdo **completo e cru** do JSON baixado no passo 6 (como string).

   Pela CLI:
   ```bash
   supabase secrets set FCM_PROJECT_ID=vamoscorrer-abc123
   supabase secrets set FCM_SERVICE_ACCOUNT_JSON="$(cat ~/Downloads/firebase-service-account.json)"
   ```

8. Deploy da função:
   ```bash
   cd backend
   supabase functions deploy send-push
   ```

9. Teste manual:
   ```bash
   curl -X POST "https://pvwlwiicsmfyogznqazm.supabase.co/functions/v1/send-push" \
     -H "Authorization: Bearer <ANON_KEY>" \
     -H "Content-Type: application/json" \
     -d '{ "userId": "<uuid>", "title": "Teste", "body": "Olá do FCM!" }'
   ```

## Setup iOS (APNs) — para depois

Android vem primeiro. Quando for a hora do iOS, os passos adicionais são:

1. **Apple Developer Account** ($99/ano).
2. No portal Apple Developer: criar **App ID** com **Push Notifications** habilitado (bundle id `com.vamoscorrer.app`).
3. **Keys → + → Apple Push Notifications service (APNs)** → baixar `.p8` (guardar em lugar seguro, download único).
4. Anotar **Key ID** e **Team ID**.
5. No Firebase: **Project Settings → Cloud Messaging → Apple app configuration → APNs authentication key → Upload**:
   - arquivo `.p8`
   - Key ID
   - Team ID
6. No Xcode, no target `App`:
   - **Signing & Capabilities → + Capability → Push Notifications**.
   - **Signing & Capabilities → + Capability → Background Modes → Remote notifications**.
7. A função edge **não muda** — mesmo endpoint `messages:send` serve iOS via FCM. A distinção é só pelo campo `plataforma` na tabela `push_tokens`.

## Observações

- A cache do access token OAuth2 vive no escopo do worker (cold start zera). Não é um problema prático: tokens duram 1h.
- Para broadcast massivo (>500 tokens), considerar migrar para `sendEachForMulticast` ou chunking. A implementação atual é `Promise.all` de até algumas centenas de tokens, suficiente para uso atual.
- FCM HTTP v1 não suporta "topic" neste endpoint simples — isto é envio direto ao token. Topics exigem outro path (`/topics/{topic}`) e são um TODO futuro.
