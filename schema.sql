-- Ahmed Store: Supabase database setup
-- Run this entire file once in Supabase SQL Editor.

create table if not exists public.store_state (
  id integer primary key default 1,
  state jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id text primary key,
  order_number bigint not null,
  status text not null default 'جديد',
  "order" jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.store_stats (
  id integer primary key default 1,
  stats jsonb not null default '{"visits":0,"cityClicks":{},"typeClicks":{},"categoryClicks":{},"lastVisit":""}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.order_counter (
  id integer primary key default 1,
  next_number bigint not null default 224
);

insert into public.store_stats(id) values (1) on conflict (id) do nothing;
insert into public.order_counter(id,next_number) values (1,224) on conflict (id) do nothing;

alter table public.store_state enable row level security;
alter table public.orders enable row level security;
alter table public.store_stats enable row level security;
alter table public.order_counter enable row level security;

-- Cleanly recreate policies if this script is re-run.
drop policy if exists "Public can read store state" on public.store_state;
drop policy if exists "Admins can insert store state" on public.store_state;
drop policy if exists "Admins can update store state" on public.store_state;
drop policy if exists "Public can create orders" on public.orders;
drop policy if exists "Admins can read orders" on public.orders;
drop policy if exists "Admins can update orders" on public.orders;
drop policy if exists "Admins can delete orders" on public.orders;
drop policy if exists "Admins can read stats" on public.store_stats;

create policy "Public can read store state"
on public.store_state for select
to anon, authenticated
using (true);

create policy "Admins can insert store state"
on public.store_state for insert
to authenticated
with check (true);

create policy "Admins can update store state"
on public.store_state for update
to authenticated
using (true) with check (true);

create policy "Public can create orders"
on public.orders for insert
to anon, authenticated
with check (true);

create policy "Admins can read orders"
on public.orders for select
to authenticated
using (true);

create policy "Admins can update orders"
on public.orders for update
to authenticated
using (true) with check (true);

create policy "Admins can delete orders"
on public.orders for delete
to authenticated
using (true);

create policy "Admins can read stats"
on public.store_stats for select
to authenticated
using (true);

-- Counter: safe order-number allocation for customers.
create or replace function public.reserve_order_number()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare n bigint;
begin
  update public.order_counter
     set next_number = next_number + 1
   where id = 1
  returning next_number - 1 into n;
  return n;
end;
$$;

revoke execute on function public.reserve_order_number() from public;
grant execute on function public.reserve_order_number() to anon, authenticated;

-- Anonymous-safe statistics updates. Visitors cannot directly write store_state.
create or replace function public.record_stat(p_kind text, p_key text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare s jsonb;
        k text := coalesce(p_key,'');
begin
  insert into public.store_stats(id,stats) values
    (1,'{"visits":0,"cityClicks":{},"typeClicks":{},"categoryClicks":{},"lastVisit":""}'::jsonb)
  on conflict (id) do nothing;

  select stats into s from public.store_stats where id=1 for update;

  if p_kind='visit' then
    s := jsonb_set(s,'{visits}',to_jsonb(coalesce((s->>'visits')::bigint,0)+1),true);
    s := jsonb_set(s,'{lastVisit}',to_jsonb(to_char(now(),'YYYY-MM-DD HH24:MI:SS')),true);
  elsif p_kind='city' and k<>'' then
    s := jsonb_set(s, array['cityClicks',k], to_jsonb(coalesce((s->'cityClicks'->>k)::bigint,0)+1), true);
  elsif p_kind='type' and k<>'' then
    s := jsonb_set(s, array['typeClicks',k], to_jsonb(coalesce((s->'typeClicks'->>k)::bigint,0)+1), true);
  elsif p_kind='category' and k<>'' then
    s := jsonb_set(s, array['categoryClicks',k], to_jsonb(coalesce((s->'categoryClicks'->>k)::bigint,0)+1), true);
  else
    return;
  end if;

  update public.store_stats set stats=s, updated_at=now() where id=1;
end;
$$;

revoke execute on function public.record_stat(text,text) from public;
grant execute on function public.record_stat(text,text) to anon, authenticated;

-- Minimal table grants for the Data API.
grant select on public.store_state to anon, authenticated;
grant insert, update on public.store_state to authenticated;
grant insert on public.orders to anon, authenticated;
grant select, update, delete on public.orders to authenticated;
grant select on public.store_stats to authenticated;
