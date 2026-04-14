# Setup do Banco de Dados — Vamos Correr App

Execute os SQLs abaixo no Supabase SQL Editor em ordem:

## 1. Tabela de Perfis de Usuários
```sql
create table public.profiles (
  id uuid references auth.users on delete cascade primary key,
  nome text not null,
  email text not null,
  telefone text,
  avatar_url text,
  cidade text,
  estado text,
  nivel text default 'iniciante' check (nivel in ('iniciante','intermediario','avancado')),
  plano text default 'free' check (plano in ('free','premium','elite')),
  plano_expira_em timestamptz,
  total_km numeric default 0,
  total_corridas integer default 0,
  streak_atual integer default 0,
  streak_maximo integer default 0,
  xp integer default 0,
  criado_em timestamptz default now(),
  atualizado_em timestamptz default now()
);

alter table public.profiles enable row level security;

create policy "Usuário vê apenas seu próprio perfil"
  on public.profiles for select using (auth.uid() = id);

create policy "Usuário atualiza apenas seu próprio perfil"
  on public.profiles for update using (auth.uid() = id);
```

## 2. Tabela de Corridas
```sql
create table public.corridas (
  id uuid default gen_random_uuid() primary key,
  usuario_id uuid references public.profiles on delete cascade not null,
  distancia_km numeric not null check (distancia_km > 0),
  duracao_segundos integer not null check (duracao_segundos > 0),
  pace_medio text,
  calorias integer,
  elevacao_metros numeric,
  percurso jsonb,
  clima text,
  tenis_id uuid,
  notas text,
  criado_em timestamptz default now()
);

create index corridas_usuario_id_idx on public.corridas(usuario_id);
create index corridas_criado_em_idx on public.corridas(criado_em desc);

alter table public.corridas enable row level security;

create policy "Usuário vê apenas suas corridas"
  on public.corridas for select using (auth.uid() = usuario_id);

create policy "Usuário insere suas corridas"
  on public.corridas for insert with check (auth.uid() = usuario_id);
```

## 3. Tabela de Conquistas
```sql
create table public.conquistas_usuario (
  id uuid default gen_random_uuid() primary key,
  usuario_id uuid references public.profiles on delete cascade not null,
  conquista_id text not null,
  desbloqueada_em timestamptz default now(),
  unique(usuario_id, conquista_id)
);

alter table public.conquistas_usuario enable row level security;

create policy "Usuário vê suas conquistas"
  on public.conquistas_usuario for select using (auth.uid() = usuario_id);
```

## 4. Trigger para atualizar stats automaticamente
```sql
create or replace function atualizar_stats_usuario()
returns trigger language plpgsql security definer as $$
begin
  update public.profiles
  set
    total_km = total_km + NEW.distancia_km,
    total_corridas = total_corridas + 1,
    atualizado_em = now()
  where id = NEW.usuario_id;
  return NEW;
end;
$$;

create trigger on_corrida_inserida
  after insert on public.corridas
  for each row execute procedure atualizar_stats_usuario();
```

## 5. Variáveis de ambiente necessárias (.env)
```
VITE_SUPABASE_URL=https://seu-projeto.supabase.co
VITE_SUPABASE_ANON_KEY=sua_anon_key_aqui
```
