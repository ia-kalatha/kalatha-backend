-- ============================================================================
-- MIGRATION 0002: Row Level Security (RLS) Policies
-- Vamos Correr v4.0.0
-- ============================================================================

-- Habilitar RLS em todas as tabelas
alter table public.profiles enable row level security;
alter table public.corridas enable row level security;
alter table public.tenis enable row level security;
alter table public.mascotes enable row level security;
alter table public.conquistas enable row level security;
alter table public.tribos enable row level security;
alter table public.tribo_membros enable row level security;
alter table public.desafios enable row level security;
alter table public.competicoes enable row level security;
alter table public.transacoes_runcoins enable row level security;
alter table public.treinadores enable row level security;
alter table public.contratos enable row level security;
alter table public.metas enable row level security;
alter table public.notificacoes enable row level security;
alter table public.push_tokens enable row level security;
alter table public.audit_log enable row level security;

-- ============================================================================
-- PROFILES
-- ============================================================================
create policy "profiles_select_public"
  on public.profiles for select
  using (not banido);

create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "profiles_admin_all"
  on public.profiles for all
  using (exists (select 1 from public.profiles where id = auth.uid() and admin = true));

-- ============================================================================
-- CORRIDAS
-- ============================================================================
create policy "corridas_select_by_visibility"
  on public.corridas for select
  using (
    visibilidade = 'publico'
    or usuario_id = auth.uid()
    or (visibilidade = 'amigos' and exists (
      select 1 from public.tribo_membros tm1
      join public.tribo_membros tm2 on tm1.tribo_id = tm2.tribo_id
      where tm1.usuario_id = auth.uid() and tm2.usuario_id = corridas.usuario_id
    ))
  );

create policy "corridas_insert_own"
  on public.corridas for insert
  with check (auth.uid() = usuario_id);

create policy "corridas_update_own"
  on public.corridas for update
  using (auth.uid() = usuario_id);

create policy "corridas_delete_own"
  on public.corridas for delete
  using (auth.uid() = usuario_id);

-- ============================================================================
-- TENIS
-- ============================================================================
create policy "tenis_all_own"
  on public.tenis for all
  using (auth.uid() = usuario_id);

-- ============================================================================
-- MASCOTES
-- ============================================================================
create policy "mascotes_all_own"
  on public.mascotes for all
  using (auth.uid() = usuario_id);

-- ============================================================================
-- CONQUISTAS
-- ============================================================================
create policy "conquistas_select_public"
  on public.conquistas for select
  using (true);

create policy "conquistas_insert_own"
  on public.conquistas for insert
  with check (auth.uid() = usuario_id);

-- ============================================================================
-- TRIBOS
-- ============================================================================
create policy "tribos_select_visible"
  on public.tribos for select
  using (
    not privada
    or exists (
      select 1 from public.tribo_membros
      where tribo_id = tribos.id and usuario_id = auth.uid()
    )
  );

create policy "tribos_insert_any"
  on public.tribos for insert
  with check (auth.uid() = admin_id);

create policy "tribos_update_admin"
  on public.tribos for update
  using (auth.uid() = admin_id);

create policy "tribos_delete_admin"
  on public.tribos for delete
  using (auth.uid() = admin_id);

-- ============================================================================
-- TRIBO_MEMBROS
-- ============================================================================
create policy "tribo_membros_select_any"
  on public.tribo_membros for select
  using (true);

create policy "tribo_membros_insert_own"
  on public.tribo_membros for insert
  with check (auth.uid() = usuario_id);

create policy "tribo_membros_delete_own"
  on public.tribo_membros for delete
  using (
    auth.uid() = usuario_id
    or exists (
      select 1 from public.tribos
      where id = tribo_membros.tribo_id and admin_id = auth.uid()
    )
  );

-- ============================================================================
-- DESAFIOS
-- ============================================================================
create policy "desafios_select_participants"
  on public.desafios for select
  using (auth.uid() = criador_id or auth.uid() = desafiado_id);

create policy "desafios_insert_creator"
  on public.desafios for insert
  with check (auth.uid() = criador_id);

create policy "desafios_update_participants"
  on public.desafios for update
  using (auth.uid() = criador_id or auth.uid() = desafiado_id);

-- ============================================================================
-- COMPETICOES
-- ============================================================================
create policy "competicoes_all_own"
  on public.competicoes for all
  using (auth.uid() = usuario_id);

-- ============================================================================
-- TRANSACOES_RUNCOINS
-- ============================================================================
create policy "transacoes_select_own"
  on public.transacoes_runcoins for select
  using (auth.uid() = usuario_id);

create policy "transacoes_insert_own"
  on public.transacoes_runcoins for insert
  with check (auth.uid() = usuario_id);

-- ============================================================================
-- TREINADORES
-- ============================================================================
create policy "treinadores_select_public"
  on public.treinadores for select
  using (true);

create policy "treinadores_insert_own"
  on public.treinadores for insert
  with check (auth.uid() = usuario_id);

create policy "treinadores_update_own"
  on public.treinadores for update
  using (auth.uid() = usuario_id);

-- ============================================================================
-- CONTRATOS
-- ============================================================================
create policy "contratos_select_participants"
  on public.contratos for select
  using (
    auth.uid() = usuario_id
    or exists (select 1 from public.treinadores where id = contratos.treinador_id and usuario_id = auth.uid())
  );

create policy "contratos_insert_student"
  on public.contratos for insert
  with check (auth.uid() = usuario_id);

create policy "contratos_update_participants"
  on public.contratos for update
  using (
    auth.uid() = usuario_id
    or exists (select 1 from public.treinadores where id = contratos.treinador_id and usuario_id = auth.uid())
  );

-- ============================================================================
-- METAS / NOTIFICACOES / PUSH_TOKENS
-- ============================================================================
create policy "metas_all_own"
  on public.metas for all
  using (auth.uid() = usuario_id);

create policy "notificacoes_all_own"
  on public.notificacoes for all
  using (auth.uid() = usuario_id);

create policy "push_tokens_all_own"
  on public.push_tokens for all
  using (auth.uid() = usuario_id);

-- ============================================================================
-- AUDIT_LOG - Apenas admin pode ler
-- ============================================================================
create policy "audit_log_admin_read"
  on public.audit_log for select
  using (exists (select 1 from public.profiles where id = auth.uid() and admin = true));

create policy "audit_log_system_insert"
  on public.audit_log for insert
  with check (true);
