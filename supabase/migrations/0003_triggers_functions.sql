-- ============================================================================
-- MIGRATION 0003: Triggers, Functions & Views
-- Vamos Correr v4.0.0
-- ============================================================================

-- ============================================================================
-- Function: Atualizar updated_at automaticamente
-- ============================================================================
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  NEW.atualizado_em := now();
  return NEW;
end;
$$;

drop trigger if exists trg_profiles_updated on public.profiles;
create trigger trg_profiles_updated
  before update on public.profiles
  for each row execute procedure public.set_updated_at();

-- ============================================================================
-- Function: Criar profile automaticamente ao registrar
-- ============================================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, nome, email)
  values (
    NEW.id,
    coalesce(NEW.raw_user_meta_data->>'nome', split_part(NEW.email, '@', 1)),
    NEW.email
  )
  on conflict (id) do nothing;
  return NEW;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================================
-- Function: Atualizar stats do usuário ao inserir corrida
-- ============================================================================
create or replace function public.atualizar_stats_corrida()
returns trigger language plpgsql security definer as $$
declare
  ultimo_dia date;
  hoje date := current_date;
  novo_streak integer;
begin
  -- Pega último dia que o usuário correu
  select (max(criado_em)::date) into ultimo_dia
  from public.corridas
  where usuario_id = NEW.usuario_id and id != NEW.id;

  -- Calcula novo streak
  if ultimo_dia is null then
    novo_streak := 1;
  elsif ultimo_dia = hoje then
    select streak_atual into novo_streak from public.profiles where id = NEW.usuario_id;
  elsif ultimo_dia = hoje - interval '1 day' then
    select streak_atual + 1 into novo_streak from public.profiles where id = NEW.usuario_id;
  else
    novo_streak := 1;
  end if;

  update public.profiles
  set
    total_km = total_km + NEW.distancia_km,
    total_corridas = total_corridas + 1,
    streak_atual = novo_streak,
    streak_maximo = greatest(streak_maximo, novo_streak),
    atualizado_em = now()
  where id = NEW.usuario_id;

  return NEW;
end;
$$;

drop trigger if exists trg_corrida_stats on public.corridas;
create trigger trg_corrida_stats
  after insert on public.corridas
  for each row execute procedure public.atualizar_stats_corrida();

-- ============================================================================
-- Function: Atualizar km do tênis ao inserir corrida
-- ============================================================================
create or replace function public.atualizar_km_tenis()
returns trigger language plpgsql security definer as $$
begin
  if NEW.tenis_id is not null then
    update public.tenis
    set km_atual = km_atual + NEW.distancia_km
    where id = NEW.tenis_id;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_tenis_km on public.corridas;
create trigger trg_tenis_km
  after insert on public.corridas
  for each row execute procedure public.atualizar_km_tenis();

-- ============================================================================
-- Function: Atualizar RunCoins ao transação
-- ============================================================================
create or replace function public.processar_transacao_runcoin()
returns trigger language plpgsql security definer as $$
begin
  if NEW.tipo = 'credit' then
    update public.profiles
    set run_coins = run_coins + NEW.valor
    where id = NEW.usuario_id;
  else
    update public.profiles
    set run_coins = greatest(0, run_coins - NEW.valor)
    where id = NEW.usuario_id;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_runcoin on public.transacoes_runcoins;
create trigger trg_runcoin
  after insert on public.transacoes_runcoins
  for each row execute procedure public.processar_transacao_runcoin();

-- ============================================================================
-- Function: Atualizar contador de membros da tribo
-- ============================================================================
create or replace function public.atualizar_membros_tribo()
returns trigger language plpgsql security definer as $$
begin
  if TG_OP = 'INSERT' then
    update public.tribos set membros = membros + 1 where id = NEW.tribo_id;
  elsif TG_OP = 'DELETE' then
    update public.tribos set membros = greatest(0, membros - 1) where id = OLD.tribo_id;
  end if;
  return coalesce(NEW, OLD);
end;
$$;

drop trigger if exists trg_membros_tribo on public.tribo_membros;
create trigger trg_membros_tribo
  after insert or delete on public.tribo_membros
  for each row execute procedure public.atualizar_membros_tribo();

-- ============================================================================
-- Function: Exportar dados do usuário (LGPD)
-- ============================================================================
create or replace function public.exportar_dados_usuario(p_usuario_id uuid)
returns jsonb language plpgsql security definer as $$
declare
  resultado jsonb;
begin
  -- Só o próprio usuário ou admin pode exportar
  if p_usuario_id != auth.uid() and not exists (select 1 from public.profiles where id = auth.uid() and admin) then
    raise exception 'Sem permissão';
  end if;

  select jsonb_build_object(
    'profile', (select row_to_json(p) from public.profiles p where id = p_usuario_id),
    'corridas', (select jsonb_agg(row_to_json(c)) from public.corridas c where usuario_id = p_usuario_id),
    'mascotes', (select jsonb_agg(row_to_json(m)) from public.mascotes m where usuario_id = p_usuario_id),
    'tenis', (select jsonb_agg(row_to_json(t)) from public.tenis t where usuario_id = p_usuario_id),
    'conquistas', (select jsonb_agg(row_to_json(co)) from public.conquistas co where usuario_id = p_usuario_id),
    'metas', (select jsonb_agg(row_to_json(me)) from public.metas me where usuario_id = p_usuario_id),
    'transacoes', (select jsonb_agg(row_to_json(tr)) from public.transacoes_runcoins tr where usuario_id = p_usuario_id),
    'exportado_em', now()
  ) into resultado;

  return resultado;
end;
$$;

-- ============================================================================
-- Function: Excluir conta (direito ao esquecimento - LGPD)
-- ============================================================================
create or replace function public.excluir_conta(p_usuario_id uuid)
returns void language plpgsql security definer as $$
begin
  if p_usuario_id != auth.uid() and not exists (select 1 from public.profiles where id = auth.uid() and admin) then
    raise exception 'Sem permissão';
  end if;

  -- Registra no audit log antes de deletar
  insert into public.audit_log (usuario_id, acao, recurso)
  values (p_usuario_id, 'conta_excluida', 'profile');

  -- Cascata deletará tudo via FK
  delete from auth.users where id = p_usuario_id;
end;
$$;

-- ============================================================================
-- VIEW: Ranking global
-- ============================================================================
create or replace view public.ranking_global as
select
  id,
  nome,
  avatar_url,
  plano,
  nivel,
  total_km,
  total_corridas,
  streak_atual,
  xp,
  row_number() over (order by total_km desc) as posicao
from public.profiles
where not banido;

-- ============================================================================
-- VIEW: Estatísticas administrativas
-- ============================================================================
create or replace view public.admin_stats as
select
  (select count(*) from public.profiles) as total_usuarios,
  (select count(*) from public.profiles where plano = 'pro') as total_pro,
  (select count(*) from public.profiles where plano = 'elite') as total_elite,
  (select count(*) from public.profiles where ultimo_acesso >= now() - interval '1 day') as dau,
  (select count(*) from public.profiles where ultimo_acesso >= now() - interval '30 days') as mau,
  (select count(*) from public.corridas) as total_corridas,
  (select count(*) from public.corridas where criado_em >= now() - interval '7 days') as corridas_semana,
  (select coalesce(sum(distancia_km), 0) from public.corridas) as total_km_plataforma,
  (select count(*) from public.tribos) as total_tribos,
  (select count(*) from public.desafios where status = 'pendente') as desafios_pendentes;

-- ============================================================================
-- VIEW: Ranking da tribo
-- ============================================================================
create or replace view public.ranking_tribos as
select
  t.id as tribo_id,
  t.nome as tribo_nome,
  p.id as usuario_id,
  p.nome as usuario_nome,
  p.avatar_url,
  tm.km_contribuidos,
  row_number() over (partition by t.id order by tm.km_contribuidos desc) as posicao_tribo
from public.tribos t
join public.tribo_membros tm on tm.tribo_id = t.id
join public.profiles p on p.id = tm.usuario_id
where not p.banido;
