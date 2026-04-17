# Vamos Correr — Backend (Supabase)

Backend do app Vamos Correr: banco Postgres, políticas RLS, auth, edge functions, seeds.

## Supabase Project

- **Project ID:** `pvwlwiicsmfyogznqazm`
- **URL:** `https://pvwlwiicsmfyogznqazm.supabase.co`
- **Auth:** email/senha + Google OAuth. O cliente também suporta modo teste (qualquer credencial, sem backend).

## Estrutura

```
supabase/
  migrations/
    0001_initial_schema.sql    # 16 tabelas + extensões + checks
    0002_rls_policies.sql      # RLS em todas as tabelas
    0003_triggers_functions.sql # Triggers (stats, audit_log)
  functions/
    server/                    # Edge function legada (Hono + kv_store)
    verificar-midia/           # Análise de mídia (verificação de perfil)
    send-push/                 # Envio de FCM push
  seed/                        # Dados de teste
```

## Tabelas (16)

| Tabela | Finalidade |
|---|---|
| `profiles` | Perfil: nome, cpf, plano, stats (total_km, total_corridas, streak, xp) |
| `corridas` | Atividades de corrida (distância, duração, percurso GeoJSON) |
| `tenis` | Calçados do usuário |
| `mascotes` | Pets/mascotes gamificados |
| `conquistas` | Conquistas desbloqueadas |
| `tribos` | Comunidades |
| `tribo_membros` | Relação N:M usuário↔tribo |
| `desafios` | Desafios 1v1 |
| `competicoes` | Competições organizadas |
| `transacoes_runcoins` | Ledger de runCoins |
| `treinadores` | Treinadores disponíveis |
| `contratos` | Contratos usuário↔treinador |
| `metas` | Objetivos pessoais |
| `notificacoes` | Fila de notificações (via Realtime) |
| `push_tokens` | Tokens APNS/FCM por dispositivo |
| `audit_log` | Trilha de auditoria |

## RLS

**Ativado em todas as tabelas.** Políticas em `migrations/0002_rls_policies.sql`. Padrão:

- `select`: `auth.uid() = usuario_id` (ou owner equivalente)
- `insert`: `with check (auth.uid() = usuario_id)`
- `update`: `using (auth.uid() = usuario_id)`
- `delete`: geralmente restrito ou cascata via FK

Exceções documentadas:
- `tribos`/`tribo_membros`: leitura pública de tribos abertas, escrita apenas por membros
- `audit_log`: insert via trigger, select apenas admin

## Triggers

- `on_corrida_inserida` → atualiza `profiles.total_km`, `total_corridas` e `atualizado_em`
- `on_auth_user_created` → cria row em `profiles` ao registrar (se configurado)

## Storage Buckets

Três buckets públicos:
- `avatars` — fotos de perfil
- `shoes` — fotos de tênis
- `activities` — mídia de corridas

## Edge Functions

`functions/` — cada subpasta é uma Deno edge function independente.

| Função | Propósito | Secrets |
|---|---|---|
| `server/` | Função legada (Hono + kv_store) | — |
| `verificar-midia/` | Valida foto/vídeo enviado (3 slots verificação perfil). Mock 80% aprovado, TODO: plugar Vision AI real | `ANTHROPIC_API_KEY` (quando plugar) |
| `send-push/` | FCM HTTP v1 com OAuth2 JWT RS256, cache token, audit log, auto-deactivate UNREGISTERED | `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_JSON` |

Deploy:
```bash
supabase functions deploy verificar-midia
supabase functions deploy send-push
```

Logs:
```bash
supabase functions logs send-push --tail
```

Setup Firebase completo em `functions/send-push/README.md`.

## Campos adicionais (opcionais, retrocompatíveis)

Colunas **opcionais** introduzidas para features futuras — podem estar ausentes em deployments antigos e o cliente faz fallback:

- `corridas.elevacao_m` (numeric) — ganho de elevação
- `corridas.fc_media` (smallint) — FC média em bpm
- `corridas.fc_maxima` (smallint)
- `corridas.horario_inicio` (text) — formato "HH:MM"
- `desafios.plano_minimo` (text check in 'FREE','PRO','ELITE')
- `desafios.titulo` (text)
- `profiles.criado_em` (já existe) — consumido como "Membro desde {data}"

Quando for adicionar, criar migration `0004_*` incremental — não editar `0001`.

## Comandos

```bash
# CLI Supabase (requer `supabase login` e `supabase link --project-ref pvwlwiicsmfyogznqazm`)
supabase db push                  # aplica migrations pendentes
supabase db reset                 # reset local + re-run migrations
supabase db diff -f nova_feature  # gera nova migration a partir do schema local
supabase functions deploy server
supabase functions logs server --tail

# Testar SQL sem CLI: Supabase Dashboard → SQL Editor
```

## Convenções

1. **Nomes em português snake_case** (ex: `total_km`, `criado_em`, `atualizado_em`).
2. **Timestamps**: `criado_em timestamptz default now()` e `atualizado_em timestamptz default now()`.
3. **IDs**: `uuid default gen_random_uuid() primary key`, exceto `profiles.id` que é FK para `auth.users`.
4. **Checks** para enums em vez de tipos ENUM (ex: `plano text check (plano in ('free','pro','elite'))`).
5. **Migrations numeradas**: `NNNN_descricao.sql`, nunca editar migration já aplicada em produção — criar nova.
6. **Toda nova tabela** já nasce com RLS e policies na mesma migration (ou na seguinte antes de qualquer insert).
7. **Mudança de coluna consumida pelo cliente** deve ser retrocompatível durante janela de publicação nas stores (apps antigos ainda rodando).

## Checklist de Aceite

- [ ] Migration numerada corretamente (próximo N disponível)
- [ ] RLS ativada na tabela nova
- [ ] Policies cobrem select/insert/update (delete se aplicável)
- [ ] Índices para colunas usadas em `WHERE`/`ORDER BY`
- [ ] `supabase db reset` roda sem erro localmente
- [ ] Se mudou tipo/nome de coluna: compatibilidade com cliente em produção verificada

## Armadilhas

- **`security definer` em trigger**: cuidado — roda com privilégios de superuser, bypassa RLS. Usar só quando necessário (ex: atualizar stats em outra tabela).
- **`on delete cascade`**: aparência inofensiva mas pode apagar dados relacionados em massa — conferir antes.
- **Realtime**: requer `alter publication supabase_realtime add table X` — caso contrário cliente não recebe eventos.
- **Edge function + CORS**: toda resposta, incluindo erros, precisa de headers CORS completos.
- **Índice em coluna GPS (`percurso jsonb`)**: usar GIN com `jsonb_path_ops` só se realmente consultado.
