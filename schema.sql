-- Coroinhas • execute no SQL Editor de um projeto Supabase NOVO
create extension if not exists pgcrypto;
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null default '', email text, role text not null default 'coroinha' check(role in ('coroinha','coordenadora')),
 approved boolean not null default false, photo_url text, notes text, created_at timestamptz default now()
);
create table if not exists public.masses (
 id uuid primary key default gen_random_uuid(), title text not null, starts_at timestamptz not null,
 location text not null default 'Igreja Matriz', celebrant text, notes text, published boolean default true,
 created_by uuid references public.profiles(id), created_at timestamptz default now()
);
create table if not exists public.assignments (
 id uuid primary key default gen_random_uuid(), mass_id uuid not null references public.masses(id) on delete cascade,
 function_name text not null, server_id uuid references public.profiles(id),
 status text not null default 'escalado' check(status in ('escalado','confirmado','desmarcado','presente','faltou')),
 reason text, created_at timestamptz default now()
);
create table if not exists public.requests (
 id uuid primary key default gen_random_uuid(), mass_id uuid not null references public.masses(id) on delete cascade,
 assignment_id uuid references public.assignments(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 type text not null check(type in ('servir','substituir')),
 status text not null default 'pendente' check(status in ('pendente','aprovado','recusado')),
 created_at timestamptz default now(), unique(assignment_id,user_id,type)
);
create table if not exists public.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 title text not null, body text not null default '', seen boolean not null default false,
 created_at timestamptz default now()
);
create table if not exists public.messages (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id),
 type text not null check(type in ('reclamacao','sugestao')), body text not null,
 created_at timestamptz default now()
);
create table if not exists public.guides (
 id uuid primary key default gen_random_uuid(), function_name text not null unique,
 instructions text not null default '', notes text default ''
);
create table if not exists public.fixed_rules (
 id uuid primary key default gen_random_uuid(), server_id uuid not null references public.profiles(id) on delete cascade,
 weekday int not null check(weekday between 0 and 6), hour int not null check(hour between 0 and 23),
 minute int not null default 0 check(minute between 0 and 59), function_name text not null,
 location text default '', unique(server_id,weekday,hour,minute,function_name,location)
);
create or replace function public.is_coordinator() returns boolean language sql security definer stable set search_path=public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role='coordenadora' and approved);
$$;
create or replace function public.is_approved() returns boolean language sql security definer stable set search_path=public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and approved);
$$;
create or replace function public.on_signup() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.profiles(id,name,email) values(new.id,coalesce(new.raw_user_meta_data->>'name',''),new.email);
 return new;
end $$;
drop trigger if exists create_profile on auth.users;
create trigger create_profile after insert on auth.users for each row execute function public.on_signup();
-- Function for safe profile self-edits: role/approved/notes must remain coordinator-controlled.
create or replace function public.protect_profile() returns trigger language plpgsql set search_path=public as $$
begin
 if not public.is_coordinator() then
  if new.role is distinct from old.role or new.approved is distinct from old.approved or new.notes is distinct from old.notes then
   raise exception 'Somente coordenadora altera permissões e observações';
  end if;
 end if;
 return new;
end $$;
drop trigger if exists guard_profile on public.profiles;
create trigger guard_profile before update on public.profiles for each row execute function public.protect_profile();
-- Assignments and mass changes are managed only by coordinators; coroinhas use a narrow RPC to respond.
create or replace function public.respond_assignment(p_id uuid,p_action text,p_reason text default '') returns void
language plpgsql security definer set search_path=public as $$
declare v public.assignments%rowtype; t timestamptz;
begin
 if not public.is_approved() then raise exception 'Cadastro não aprovado'; end if;
 select * into v from public.assignments where id=p_id and server_id=auth.uid() for update;
 if not found then raise exception 'Escala não encontrada'; end if;
 select starts_at into t from public.masses where id=v.mass_id;
 if p_action='desmarcar' then
  if t <= now() then raise exception 'Missa já começou'; end if;
  if length(trim(p_reason)) < 3 then raise exception 'Informe uma justificativa'; end if;
  if v.status in ('desmarcado','faltou','presente') then raise exception 'Situação não permite desistência'; end if;
  update public.assignments set status='desmarcado',reason=p_reason where id=p_id;
  insert into public.notifications(user_id,title,body)
  select id,'Vaga disponível para substituir','Função '||v.function_name||' disponível em '||to_char(t at time zone 'America/Sao_Paulo','DD/MM HH24:MI')
  from public.profiles where approved and id <> auth.uid();
 elsif p_action='confirmar' then
  if (t at time zone 'America/Sao_Paulo')::date <> (now() at time zone 'America/Sao_Paulo')::date then raise exception 'Confirmação somente no dia da missa'; end if;
  if v.status not in ('escalado','confirmado') then raise exception 'Escala indisponível'; end if;
  update public.assignments set status='confirmado' where id=p_id;
 else raise exception 'Ação inválida'; end if;
end $$;
-- Access control
alter table public.profiles enable row level security;
alter table public.masses enable row level security;
alter table public.assignments enable row level security;
alter table public.requests enable row level security;
alter table public.notifications enable row level security;
alter table public.messages enable row level security;
alter table public.guides enable row level security;
alter table public.fixed_rules enable row level security;
create policy profile_read on public.profiles for select to authenticated using (id=auth.uid() or public.is_coordinator() or public.is_approved() and approved);
create policy profile_self on public.profiles for update to authenticated using (id=auth.uid() or public.is_coordinator()) with check (id=auth.uid() or public.is_coordinator());
create policy mass_read on public.masses for select to authenticated using (public.is_coordinator() or public.is_approved() and published);
create policy mass_manage on public.masses for all to authenticated using(public.is_coordinator()) with check(public.is_coordinator());
create policy assignment_read on public.assignments for select to authenticated using (public.is_coordinator() or public.is_approved() and exists(select 1 from public.masses where id=mass_id and published));
create policy assignment_manage on public.assignments for all to authenticated using(public.is_coordinator()) with check(public.is_coordinator());
create policy requests_read on public.requests for select to authenticated using(public.is_coordinator() or user_id=auth.uid());
create policy requests_insert on public.requests for insert to authenticated with check(public.is_approved() and user_id=auth.uid() and status='pendente');
create policy requests_manage on public.requests for update to authenticated using(public.is_coordinator()) with check(public.is_coordinator());
create policy notes_read on public.notifications for select to authenticated using(user_id=auth.uid());
create policy notes_update on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy notes_insert on public.notifications for insert to authenticated with check(public.is_coordinator());
create policy messages_insert on public.messages for insert to authenticated with check(public.is_approved() and user_id=auth.uid());
create policy messages_read on public.messages for select to authenticated using(public.is_coordinator() or user_id=auth.uid());
create policy guides_read on public.guides for select to authenticated using(public.is_approved());
create policy guides_manage on public.guides for all to authenticated using(public.is_coordinator()) with check(public.is_coordinator());
create policy fixed_read on public.fixed_rules for select to authenticated using(public.is_coordinator() or server_id=auth.uid());
create policy fixed_manage on public.fixed_rules for all to authenticated using(public.is_coordinator()) with check(public.is_coordinator());
grant usage on schema public to authenticated;
grant select,insert,update,delete on public.profiles,public.masses,public.assignments,public.requests,public.notifications,public.messages,public.guides,public.fixed_rules to authenticated;
grant execute on function public.respond_assignment(uuid,text,text) to authenticated;
-- Depois de cadastrar SUA conta no site, troque pelo e-mail real da coordenadora e execute UMA VEZ:
-- update public.profiles set role='coordenadora',approved=true where email='COORDENADORA@EXEMPLO.COM';
