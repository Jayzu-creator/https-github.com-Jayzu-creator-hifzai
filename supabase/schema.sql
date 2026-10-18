create table if not exists public.payment_checkouts (
  checkout_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan text not null,
  amount integer not null,
  status text not null default 'pending' check (status in ('pending', 'completed')),
  created_at timestamptz not null default now()
);

alter table public.payment_checkouts
  drop constraint if exists payment_checkouts_plan_check;
alter table public.payment_checkouts
  add constraint payment_checkouts_plan_check
  check (plan in (
    'monthly_400', 'monthly_700', 'monthly_1000', 'daily_50', 'daily_100',
    'plus_monthly', 'plus_yearly', 'pro_monthly'
  ));
alter table public.payment_checkouts
  drop constraint if exists payment_checkouts_amount_check;
alter table public.payment_checkouts
  add constraint payment_checkouts_amount_check
  check (amount in (19900, 29900, 39900, 3999, 8999, 149900));

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
  amount integer not null,
  starts_at timestamptz not null,
  expires_at timestamptz not null,
  monthly_recitations integer not null default 0
    check (monthly_recitations between 0 and 1000),
  created_at timestamptz not null default now()
);

alter table public.subscription_payments
  drop constraint if exists subscription_payments_amount_check;
alter table public.subscription_payments
  add constraint subscription_payments_amount_check
  check (amount in (19900, 29900, 39900, 149900));
alter table public.subscription_payments
  add column if not exists monthly_recitations integer not null default 0;
alter table public.subscription_payments
  drop constraint if exists subscription_payments_monthly_recitations_check;
alter table public.subscription_payments
  add constraint subscription_payments_monthly_recitations_check
  check (monthly_recitations between 0 and 1000);

create table if not exists public.recitation_packs (
  checkout_id text primary key references public.payment_checkouts(checkout_id),
  user_id uuid not null references auth.users(id) on delete cascade,
  checks_total integer not null check (checks_total in (50, 100)),
  checks_remaining integer not null check (checks_remaining between 0 and checks_total),
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists public.recitation_usage (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'completed', 'failed')),
  source text not null default 'monthly'
    check (source in ('free', 'monthly', 'daily_pack')),
  pack_checkout_id text references public.recitation_packs(checkout_id),
  constraint recitation_usage_pack_source_check
    check ((source = 'daily_pack') = (pack_checkout_id is not null)),
  created_at timestamptz not null default now()
);

alter table public.recitation_usage
  add column if not exists source text not null default 'free';
alter table public.recitation_usage
  alter column source set default 'monthly';
alter table public.recitation_usage
  drop constraint if exists recitation_usage_source_check;
alter table public.recitation_usage
  add constraint recitation_usage_source_check
  check (source in ('free', 'monthly', 'daily_pack'));
alter table public.recitation_usage
  add column if not exists pack_checkout_id text
    references public.recitation_packs(checkout_id);
update public.recitation_usage as usage_row
set source = 'monthly'
where usage_row.source = 'free'
  and exists (
    select 1
    from public.subscription_payments as payment
    where payment.user_id = usage_row.user_id
      and usage_row.created_at >= payment.starts_at
      and usage_row.created_at < payment.expires_at
  );
alter table public.recitation_usage
  drop constraint if exists recitation_usage_pack_source_check;
alter table public.recitation_usage
  add constraint recitation_usage_pack_source_check
  check ((source = 'daily_pack') = (pack_checkout_id is not null));

create index if not exists recitation_usage_user_created_idx
  on public.recitation_usage(user_id, created_at desc);
create index if not exists recitation_packs_user_expiry_idx
  on public.recitation_packs(user_id, expires_at);

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
alter table public.recitation_packs enable row level security;
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

drop function if exists public.activate_yoco_subscription(text, uuid, text, integer, integer);

create or replace function public.activate_yoco_subscription(
  p_checkout_id text,
  p_user_id uuid,
  p_plan text,
  p_amount integer,
  p_months integer,
  p_monthly_recitations integer
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
    or checkout_row.plan not in (
      'monthly_400', 'monthly_700', 'monthly_1000',
      'plus_monthly', 'plus_yearly', 'pro_monthly'
    )
    or (checkout_row.plan like 'monthly_%' and p_plan <> 'plus')
    or (checkout_row.plan like 'plus_%' and p_plan <> 'plus')
    or (checkout_row.plan = 'pro_monthly' and p_plan <> 'pro')
    or p_months not in (1, 12)
    or p_monthly_recitations not between 1 and 1000
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
      (checkout_row.plan = 'monthly_400' and p_plan = 'plus' and p_amount = 19900 and p_months = 1 and p_monthly_recitations = 400)
      or (checkout_row.plan = 'monthly_700' and p_plan = 'plus' and p_amount = 29900 and p_months = 1 and p_monthly_recitations = 700)
      or (checkout_row.plan = 'monthly_1000' and p_plan = 'plus' and p_amount = 39900 and p_months = 1 and p_monthly_recitations = 1000)
      or (checkout_row.plan = 'plus_monthly' and p_plan = 'plus' and p_amount = 19900 and p_months = 1 and p_monthly_recitations = 50)
      or (checkout_row.plan = 'plus_yearly' and p_plan = 'plus' and p_amount = 149900 and p_months = 12 and p_monthly_recitations = 50)
      or (checkout_row.plan = 'pro_monthly' and p_plan = 'pro' and p_amount = 29900 and p_months = 1 and p_monthly_recitations = 150)
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
    checkout_id, user_id, plan, amount, starts_at, expires_at,
    monthly_recitations
  ) values (
    p_checkout_id, p_user_id, p_plan, p_amount, next_start, next_expiry,
    p_monthly_recitations
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

create or replace function public.get_recitation_status(
  p_user_id uuid,
  p_period_start timestamptz,
  p_period_end timestamptz,
  p_is_free boolean
)
returns table(used integer, pack_remaining integer, pack_expires_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_count integer;
  available_packs integer;
  nearest_expiry timestamptz;
begin
  if p_period_start is null then
    raise exception 'Usage period start is required';
  end if;

  select count(*)::integer into current_count
  from public.recitation_usage
  where user_id = p_user_id
    and created_at >= p_period_start
    and (p_period_end is null or created_at < p_period_end)
    and source = case when p_is_free then 'free' else 'monthly' end
    and (
      status = 'completed'
      or (status = 'pending' and created_at >= now() - interval '15 minutes')
    );

  select coalesce(sum(checks_remaining), 0)::integer, min(expires_at)
    into available_packs, nearest_expiry
  from public.recitation_packs
  where user_id = p_user_id
    and checks_remaining > 0
    and expires_at > now();

  return query select current_count, available_packs, nearest_expiry;
end;
$$;

create or replace function public.reserve_recitation_check(
  p_user_id uuid,
  p_limit integer,
  p_period_start timestamptz,
  p_period_end timestamptz,
  p_is_free boolean
)
returns table(
  accepted boolean,
  used integer,
  usage_id bigint,
  source text,
  pack_remaining integer,
  pack_expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_count integer;
  new_id bigint;
  used_source text;
  selected_pack public.recitation_packs%rowtype;
  available_packs integer;
  nearest_expiry timestamptz;
begin
  if p_limit not between 1 and 1000 or p_period_start is null then
    raise exception 'Invalid recitation allowance';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_user_id::text));

  used_source := case when p_is_free then 'free' else 'monthly' end;
  select count(*)::integer into current_count
  from public.recitation_usage
  where user_id = p_user_id
    and created_at >= p_period_start
    and (p_period_end is null or created_at < p_period_end)
    and public.recitation_usage.source = used_source
    and (
      status = 'completed'
      or (status = 'pending' and created_at >= now() - interval '15 minutes')
    );

  if current_count >= p_limit then
    select * into selected_pack
    from public.recitation_packs
    where user_id = p_user_id
      and checks_remaining > 0
      and expires_at > now()
    order by expires_at, created_at
    limit 1
    for update skip locked;

    if found then
      update public.recitation_packs
      set checks_remaining = checks_remaining - 1
      where checkout_id = selected_pack.checkout_id
      returning * into selected_pack;

      insert into public.recitation_usage(
        user_id, status, source, pack_checkout_id
      ) values (
        p_user_id, 'pending', 'daily_pack', selected_pack.checkout_id
      )
      returning id into new_id;

      select coalesce(sum(checks_remaining), 0)::integer, min(expires_at)
        into available_packs, nearest_expiry
      from public.recitation_packs
      where user_id = p_user_id
        and checks_remaining > 0
        and expires_at > now();

      return query select
        true, current_count, new_id, 'daily_pack',
        available_packs, nearest_expiry;
      return;
    end if;

    select coalesce(sum(checks_remaining), 0)::integer, min(expires_at)
      into available_packs, nearest_expiry
    from public.recitation_packs
    where user_id = p_user_id
      and checks_remaining > 0
      and expires_at > now();

    return query select
      false, current_count, null::bigint, used_source,
      available_packs, nearest_expiry;
    return;
  end if;

  insert into public.recitation_usage(user_id, status, source)
  values (p_user_id, 'pending', used_source)
  returning id into new_id;

  select coalesce(sum(checks_remaining), 0)::integer, min(expires_at)
    into available_packs, nearest_expiry
  from public.recitation_packs
  where user_id = p_user_id
    and checks_remaining > 0
    and expires_at > now();

  return query select
    true, current_count + 1, new_id, used_source,
    available_packs, nearest_expiry;
end;
$$;

create or replace function public.activate_yoco_recitation_pack(
  p_checkout_id text,
  p_user_id uuid,
  p_checks integer,
  p_amount integer
)
returns table(checkout_id text, checks_remaining integer, expires_at timestamptz, already_activated boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  checkout_row public.payment_checkouts%rowtype;
  existing_pack public.recitation_packs%rowtype;
begin
  perform pg_advisory_xact_lock(hashtext(p_user_id::text));

  select * into checkout_row
  from public.payment_checkouts
  where payment_checkouts.checkout_id = p_checkout_id
  for update;

  if not found
    or checkout_row.user_id <> p_user_id
    or checkout_row.amount <> p_amount
    or not (
      (checkout_row.plan = 'daily_50' and p_checks = 50 and p_amount = 3999)
      or (checkout_row.plan = 'daily_100' and p_checks = 100 and p_amount = 8999)
    )
  then
    raise exception 'Verified payment does not match a daily recitation pack';
  end if;

  select * into existing_pack
  from public.recitation_packs
  where recitation_packs.checkout_id = p_checkout_id;
  if found then
    return query select existing_pack.checkout_id,
      existing_pack.checks_remaining, existing_pack.expires_at, true;
    return;
  end if;

  if checkout_row.status <> 'pending' then
    raise exception 'The checkout is not pending activation';
  end if;

  insert into public.recitation_packs(
    checkout_id, user_id, checks_total, checks_remaining, expires_at
  ) values (
    p_checkout_id, p_user_id, p_checks, p_checks, now() + interval '24 hours'
  )
  returning * into existing_pack;

  update public.payment_checkouts
  set status = 'completed'
  where payment_checkouts.checkout_id = p_checkout_id;

  return query select existing_pack.checkout_id,
    existing_pack.checks_remaining, existing_pack.expires_at, false;
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
declare
  usage_source text;
  usage_pack text;
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

  if p_status = 'failed' then
    select source, pack_checkout_id into usage_source, usage_pack
    from public.recitation_usage
    where id = p_usage_id;
    if usage_source = 'daily_pack' then
      update public.recitation_packs
      set checks_remaining = least(checks_total, checks_remaining + 1)
      where checkout_id = usage_pack
        and expires_at > now();
    end if;
  end if;
end;
$$;

revoke all on function public.activate_yoco_subscription(text, uuid, text, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.activate_yoco_recitation_pack(text, uuid, integer, integer) from public, anon, authenticated;
revoke all on function public.get_recitation_status(uuid, timestamptz, timestamptz, boolean) from public, anon, authenticated;
drop function if exists public.reserve_recitation_check(uuid, integer, timestamptz);
revoke all on function public.reserve_recitation_check(uuid, integer, timestamptz, timestamptz, boolean) from public, anon, authenticated;
revoke all on function public.finish_recitation_check(bigint, text) from public, anon, authenticated;
grant execute on function public.activate_yoco_subscription(text, uuid, text, integer, integer, integer) to service_role;
grant execute on function public.activate_yoco_recitation_pack(text, uuid, integer, integer) to service_role;
grant execute on function public.get_recitation_status(uuid, timestamptz, timestamptz, boolean) to service_role;
grant execute on function public.reserve_recitation_check(uuid, integer, timestamptz, timestamptz, boolean) to service_role;
grant execute on function public.finish_recitation_check(bigint, text) to service_role;

grant select on public.subscriptions to authenticated;
grant select, insert, update, delete on public.ayah_progress to authenticated;
grant all on public.payment_checkouts, public.subscriptions,
  public.subscription_payments, public.recitation_packs,
  public.recitation_usage to service_role;
grant usage, select on sequence public.recitation_usage_id_seq to service_role;
