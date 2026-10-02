create table if not exists public.payment_checkouts (
  checkout_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan text not null check (plan in ('plus_monthly', 'plus_yearly', 'pro_monthly')),
  amount integer not null check (amount in (19900, 149900, 29900)),
  status text not null default 'pending' check (status in ('pending', 'completed')),
  created_at timestamptz not null default now()
);

create table if not exists public.subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan text not null check (plan in ('plus', 'pro')),
  starts_at timestamptz not null,
  expires_at timestamptz not null,
  last_checkout_id text not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.subscription_payments (
  checkout_id text primary key references public.payment_checkouts(checkout_id),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan text not null check (plan in ('plus', 'pro')),
  amount integer not null check (amount in (19900, 149900, 29900)),
  starts_at timestamptz not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists public.recitation_usage (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'completed', 'failed')),
  created_at timestamptz not null default now()
);

create index if not exists recitation_usage_user_created_idx
  on public.recitation_usage(user_id, created_at desc);

create table if not exists public.ayah_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  surah_id integer not null check (surah_id between 1 and 114),
  ayah_number integer not null check (ayah_number between 1 and 286),
  status text not null check (status in ('remembered', 'needs_revision')),
  updated_at timestamptz not null default now(),
  primary key (user_id, surah_id, ayah_number)
);

alter table public.payment_checkouts enable row level security;
alter table public.subscriptions enable row level security;
alter table public.subscription_payments enable row level security;
alter table public.recitation_usage enable row level security;
alter table public.ayah_progress enable row level security;

drop policy if exists "Users can read their own active plan"
  on public.subscriptions;
create policy "Users can read their own active plan"
  on public.subscriptions for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can manage their own ayah progress"
  on public.ayah_progress;
create policy "Users can manage their own ayah progress"
  on public.ayah_progress for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.activate_yoco_subscription(
  p_checkout_id text,
  p_user_id uuid,
  p_plan text,
  p_amount integer,
  p_months integer
)
returns table(plan text, starts_at timestamptz, expires_at timestamptz, already_activated boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  checkout_row public.payment_checkouts%rowtype;
  prior_payment public.subscription_payments%rowtype;
  current_subscription public.subscriptions%rowtype;
  next_start timestamptz;
  next_expiry timestamptz;
begin
  perform pg_advisory_xact_lock(hashtext(p_user_id::text));

  select * into checkout_row
  from public.payment_checkouts
  where checkout_id = p_checkout_id
  for update;

  if not found
    or checkout_row.user_id <> p_user_id
    or checkout_row.amount <> p_amount
    or checkout_row.plan not in ('plus_monthly', 'plus_yearly', 'pro_monthly')
    or (checkout_row.plan like 'plus_%' and p_plan <> 'plus')
    or (checkout_row.plan = 'pro_monthly' and p_plan <> 'pro')
    or p_months not in (1, 12)
  then
    raise exception 'Verified payment does not match the pending checkout';
  end if;

  select * into prior_payment
  from public.subscription_payments
  where checkout_id = p_checkout_id;
  if found then
    return query select prior_payment.plan, prior_payment.starts_at,
      prior_payment.expires_at, true;
    return;
  end if;
  if checkout_row.status <> 'pending'
    or not (
      (checkout_row.plan = 'plus_monthly' and p_plan = 'plus' and p_amount = 19900 and p_months = 1)
      or (checkout_row.plan = 'plus_yearly' and p_plan = 'plus' and p_amount = 149900 and p_months = 12)
      or (checkout_row.plan = 'pro_monthly' and p_plan = 'pro' and p_amount = 29900 and p_months = 1)
    )
  then
    raise exception 'Checkout plan, amount, or duration is invalid';
  end if;

  select * into current_subscription
  from public.subscriptions
  where user_id = p_user_id
  for update;

  next_start := greatest(now(), coalesce(current_subscription.expires_at, now()));
  next_expiry := next_start + make_interval(months => p_months);

  insert into public.subscription_payments(
    checkout_id, user_id, plan, amount, starts_at, expires_at
  ) values (
    p_checkout_id, p_user_id, p_plan, p_amount, next_start, next_expiry
  );

  insert into public.subscriptions(
    user_id, plan, starts_at, expires_at, last_checkout_id, updated_at
  ) values (
    p_user_id, p_plan, next_start, next_expiry, p_checkout_id, now()
  )
  on conflict (user_id) do update set
    plan = excluded.plan,
    starts_at = case
      when public.subscriptions.expires_at > now()
        then public.subscriptions.starts_at
      else excluded.starts_at
    end,
    expires_at = excluded.expires_at,
    last_checkout_id = excluded.last_checkout_id,
    updated_at = now();

  update public.payment_checkouts
  set status = 'completed'
  where checkout_id = p_checkout_id;

  return query select p_plan, next_start, next_expiry, false;
end;
$$;

create or replace function public.reserve_recitation_check(
  p_user_id uuid,
  p_limit integer,
  p_period_start timestamptz
)
returns table(accepted boolean, used integer, usage_id bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_count integer;
  new_id bigint;
begin
  if p_limit not between 1 and 200 then
    raise exception 'Invalid usage limit';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_user_id::text));

  select count(*)::integer into current_count
  from public.recitation_usage
  where user_id = p_user_id
    and created_at >= p_period_start
    and (
      status = 'completed'
      or (status = 'pending' and created_at >= now() - interval '15 minutes')
    );

  if current_count >= p_limit then
    return query select false, current_count, null::bigint;
    return;
  end if;

  insert into public.recitation_usage(user_id, status)
  values (p_user_id, 'pending')
  returning id into new_id;
  return query select true, current_count + 1, new_id;
end;
$$;

create or replace function public.finish_recitation_check(
  p_usage_id bigint,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_status not in ('completed', 'failed') then
    raise exception 'Invalid usage status';
  end if;
  update public.recitation_usage
  set status = p_status
  where id = p_usage_id and status = 'pending';
  if not found then
    raise exception 'Recitation usage reservation not found';
  end if;
end;
$$;

revoke all on function public.activate_yoco_subscription(text, uuid, text, integer, integer) from public, anon, authenticated;
revoke all on function public.reserve_recitation_check(uuid, integer, timestamptz) from public, anon, authenticated;
revoke all on function public.finish_recitation_check(bigint, text) from public, anon, authenticated;
grant execute on function public.activate_yoco_subscription(text, uuid, text, integer, integer) to service_role;
grant execute on function public.reserve_recitation_check(uuid, integer, timestamptz) to service_role;
grant execute on function public.finish_recitation_check(bigint, text) to service_role;

grant select on public.subscriptions to authenticated;
grant select, insert, update, delete on public.ayah_progress to authenticated;
grant all on public.payment_checkouts, public.subscriptions,
  public.subscription_payments, public.recitation_usage to service_role;
grant usage, select on sequence public.recitation_usage_id_seq to service_role;
