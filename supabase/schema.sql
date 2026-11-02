create table if not exists public.payment_checkouts (
  checkout_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan text not null,
  amount integer not null,
  payment_provider text not null default 'yoco'
    check (payment_provider in ('yoco', 'google_play')),
  status text not null default 'pending' check (status in ('pending', 'completed')),
  created_at timestamptz not null default now()
);

alter table public.payment_checkouts
  add column if not exists payment_provider text not null default 'yoco';
alter table public.payment_checkouts
  drop constraint if exists payment_checkouts_payment_provider_check;
alter table public.payment_checkouts
  add constraint payment_checkouts_payment_provider_check
  check (payment_provider in ('yoco', 'google_play'));
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
  check (amount in (0, 19900, 29900, 39900, 3999, 8999, 149900));

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
  check (amount in (0, 19900, 29900, 39900, 149900));
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
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.recitation_packs
  add column if not exists revoked_at timestamptz;

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
    and revoked_at is null
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
      and revoked_at is null
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
        and revoked_at is null
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
      and revoked_at is null
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
    and revoked_at is null
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
        and revoked_at is null
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

create table if not exists public.google_play_purchases (
  token_hash text primary key check (token_hash ~ '^[0-9a-f]{64}$'),
  encrypted_purchase_token text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null check (product_id in (
    'monthly_400', 'monthly_700', 'monthly_1000', 'daily_50', 'daily_100'
  )),
  purchase_kind text not null check (purchase_kind in ('subscription', 'daily_pack')),
  purchase_state text not null,
  expires_at timestamptz,
  last_order_id text,
  revoked_at timestamptz,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.google_play_orders (
  order_id text primary key,
  checkout_id text not null unique references public.payment_checkouts(checkout_id)
    on delete cascade,
  token_hash text not null references public.google_play_purchases(token_hash),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null,
  order_kind text not null check (order_kind in ('subscription', 'daily_pack')),
  starts_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.google_play_orders
  add column if not exists revoked_at timestamptz;

alter table public.google_play_purchases enable row level security;
alter table public.google_play_orders enable row level security;
revoke all on public.google_play_purchases, public.google_play_orders
  from public, anon, authenticated;
grant all on public.google_play_purchases, public.google_play_orders
  to service_role;
create index if not exists google_play_purchases_user_expiry_idx
  on public.google_play_purchases(user_id, expires_at desc);
create index if not exists google_play_orders_token_idx
  on public.google_play_orders(token_hash);

create or replace function public.activate_google_play_subscription(
  p_order_id text,
  p_checkout_id text,
  p_token_hash text,
  p_encrypted_purchase_token text,
  p_user_id uuid,
  p_product_id text,
  p_purchase_state text,
  p_expires_at timestamptz
)
returns table(plan text, starts_at timestamptz, expires_at timestamptz, already_activated boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  product_plan text := 'plus';
  monthly_limit integer;
  existing_purchase public.google_play_purchases%rowtype;
  prior_order public.google_play_orders%rowtype;
  current_subscription public.subscriptions%rowtype;
  current_product_id text;
  period_start timestamptz;
begin
  perform pg_advisory_xact_lock(hashtext(p_user_id::text));

  if p_product_id = 'monthly_400' then
    monthly_limit := 400;
  elsif p_product_id = 'monthly_700' then
    monthly_limit := 700;
  elsif p_product_id = 'monthly_1000' then
    monthly_limit := 1000;
  else
    raise exception 'Unknown Google Play subscription product';
  end if;

  if p_token_hash !~ '^[0-9a-f]{64}$'
    or p_order_id = ''
    or p_checkout_id !~ '^gp_sub_[0-9a-f]{64}$'
    or p_purchase_state not in (
      'SUBSCRIPTION_STATE_ACTIVE',
      'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
      'SUBSCRIPTION_STATE_CANCELED'
    )
    or p_expires_at <= now()
  then
    raise exception 'Google Play subscription is not entitled';
  end if;

  select * into existing_purchase
  from public.google_play_purchases
  where token_hash = p_token_hash
  for update;
  if found and (
    existing_purchase.user_id <> p_user_id
    or existing_purchase.purchase_kind <> 'subscription'
  ) then
    raise exception 'Google Play purchase token is already assigned';
  end if;

  select * into prior_order
  from public.google_play_orders
  where order_id = p_order_id;
  if found then
    if prior_order.user_id <> p_user_id
      or prior_order.token_hash <> p_token_hash
      or prior_order.product_id <> p_product_id
    then
      raise exception 'Google Play order is already assigned';
    end if;
    return query select 'plus'::text, prior_order.starts_at,
      prior_order.expires_at, true;
    return;
  end if;

  insert into public.google_play_purchases(
    token_hash, encrypted_purchase_token, user_id, product_id,
    purchase_kind, purchase_state, expires_at, last_order_id,
    revoked_at, updated_at
  ) values (
    p_token_hash, p_encrypted_purchase_token, p_user_id, p_product_id,
    'subscription', p_purchase_state, p_expires_at, p_order_id,
    null, now()
  )
  on conflict (token_hash) do update set
    encrypted_purchase_token = excluded.encrypted_purchase_token,
    product_id = excluded.product_id,
    purchase_state = excluded.purchase_state,
    expires_at = excluded.expires_at,
    last_order_id = excluded.last_order_id,
    revoked_at = null,
    updated_at = now();

  select * into current_subscription
  from public.subscriptions
  where user_id = p_user_id
  for update;
  select product_id into current_product_id
  from public.google_play_orders
  where checkout_id = current_subscription.last_checkout_id;
  if current_subscription.expires_at > now()
    and current_product_id is distinct from p_product_id
  then
    period_start := now();
  else
    period_start := greatest(now(), coalesce(current_subscription.expires_at, now()));
  end if;

  insert into public.payment_checkouts(
    checkout_id, user_id, plan, amount, payment_provider, status
  ) values (
    p_checkout_id, p_user_id, p_product_id, 0, 'google_play', 'completed'
  );
  insert into public.subscription_payments(
    checkout_id, user_id, plan, amount, starts_at, expires_at,
    monthly_recitations
  ) values (
    p_checkout_id, p_user_id, product_plan, 0,
    period_start, p_expires_at, monthly_limit
  );
  insert into public.google_play_orders(
    order_id, checkout_id, token_hash, user_id, product_id,
    order_kind, starts_at, expires_at
  ) values (
    p_order_id, p_checkout_id, p_token_hash, p_user_id, p_product_id,
    'subscription', period_start, p_expires_at
  );
  insert into public.subscriptions(
    user_id, plan, starts_at, expires_at, last_checkout_id, updated_at
  ) values (
    p_user_id, product_plan, period_start, p_expires_at, p_checkout_id, now()
  )
  on conflict (user_id) do update set
    plan = excluded.plan,
    starts_at = excluded.starts_at,
    expires_at = excluded.expires_at,
    last_checkout_id = excluded.last_checkout_id,
    updated_at = now();

  return query select product_plan, period_start, p_expires_at, false;
end;
$$;

create or replace function public.activate_google_play_recitation_pack(
  p_order_id text,
  p_checkout_id text,
  p_token_hash text,
  p_encrypted_purchase_token text,
  p_user_id uuid,
  p_product_id text
)
returns table(checkout_id text, checks_remaining integer, expires_at timestamptz, already_activated boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  product_checks integer;
  existing_purchase public.google_play_purchases%rowtype;
  prior_order public.google_play_orders%rowtype;
  existing_pack public.recitation_packs%rowtype;
begin
  perform pg_advisory_xact_lock(hashtext(p_user_id::text));

  if p_product_id = 'daily_50' then
    product_checks := 50;
  elsif p_product_id = 'daily_100' then
    product_checks := 100;
  else
    raise exception 'Unknown Google Play add-on product';
  end if;

  if p_token_hash !~ '^[0-9a-f]{64}$'
    or p_order_id = ''
    or p_checkout_id !~ '^gp_pack_[0-9a-f]{64}$'
  then
    raise exception 'Invalid Google Play add-on purchase';
  end if;

  select * into existing_purchase
  from public.google_play_purchases
  where token_hash = p_token_hash
  for update;
  if found and (
    existing_purchase.user_id <> p_user_id
    or existing_purchase.purchase_kind <> 'daily_pack'
    or existing_purchase.product_id <> p_product_id
  ) then
    raise exception 'Google Play purchase token is already assigned';
  end if;

  select * into prior_order
  from public.google_play_orders
  where order_id = p_order_id;
  if found then
    if prior_order.user_id <> p_user_id
      or prior_order.token_hash <> p_token_hash
      or prior_order.product_id <> p_product_id
    then
      raise exception 'Google Play order is already assigned';
    end if;
    select * into existing_pack
    from public.recitation_packs
    where recitation_packs.checkout_id = prior_order.checkout_id;
    return query select existing_pack.checkout_id,
      existing_pack.checks_remaining, existing_pack.expires_at, true;
    return;
  end if;

  insert into public.google_play_purchases(
    token_hash, encrypted_purchase_token, user_id, product_id,
    purchase_kind, purchase_state, last_order_id, revoked_at, updated_at
  ) values (
    p_token_hash, p_encrypted_purchase_token, p_user_id, p_product_id,
    'daily_pack', 'PURCHASED', p_order_id, null, now()
  )
  on conflict (token_hash) do update set
    encrypted_purchase_token = excluded.encrypted_purchase_token,
    purchase_state = excluded.purchase_state,
    last_order_id = excluded.last_order_id,
    revoked_at = null,
    updated_at = now();

  insert into public.payment_checkouts(
    checkout_id, user_id, plan, amount, payment_provider, status
  ) values (
    p_checkout_id, p_user_id, p_product_id, 0, 'google_play', 'completed'
  );
  insert into public.recitation_packs(
    checkout_id, user_id, checks_total, checks_remaining, expires_at
  ) values (
    p_checkout_id, p_user_id, product_checks, product_checks,
    now() + interval '24 hours'
  )
  returning * into existing_pack;
  insert into public.google_play_orders(
    order_id, checkout_id, token_hash, user_id, product_id, order_kind
  ) values (
    p_order_id, p_checkout_id, p_token_hash, p_user_id, p_product_id, 'daily_pack'
  );

  return query select existing_pack.checkout_id,
    existing_pack.checks_remaining, existing_pack.expires_at, false;
end;
$$;

create or replace function public.update_google_play_purchase_state(
  p_token_hash text,
  p_purchase_state text,
  p_expires_at timestamptz,
  p_revoked boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  purchase public.google_play_purchases%rowtype;
begin
  select * into purchase
  from public.google_play_purchases
  where token_hash = p_token_hash
  for update;
  if not found then
    raise exception 'Google Play purchase was not registered';
  end if;

  update public.google_play_purchases
  set purchase_state = p_purchase_state,
      expires_at = p_expires_at,
      revoked_at = case when p_revoked then now() else null end,
      updated_at = now()
  where token_hash = p_token_hash;

  if purchase.purchase_kind = 'subscription' and p_revoked then
    update public.subscriptions
    set expires_at = least(expires_at, now()), updated_at = now()
    where user_id = purchase.user_id
      and last_checkout_id in (
        select checkout_id
        from public.google_play_orders
        where token_hash = p_token_hash
      );
  elsif purchase.purchase_kind = 'daily_pack' and p_revoked then
    update public.recitation_packs
    set checks_remaining = 0, revoked_at = now()
    where checkout_id in (
      select checkout_id
      from public.google_play_orders
      where token_hash = p_token_hash
    );
  end if;
end;
$$;

create or replace function public.get_google_play_subscription_to_reconcile(
  p_user_id uuid
)
returns table(token_hash text, encrypted_purchase_token text, product_id text)
language sql
security definer
set search_path = public
as $$
  select purchase.token_hash, purchase.encrypted_purchase_token, purchase.product_id
  from public.subscriptions as subscription
  join public.google_play_orders as purchase_order
    on purchase_order.checkout_id = subscription.last_checkout_id
    and purchase_order.order_kind = 'subscription'
  join public.google_play_purchases as purchase
    on purchase.token_hash = purchase_order.token_hash
    and purchase.user_id = subscription.user_id
  where subscription.user_id = p_user_id
  limit 1;
$$;

create or replace function public.revoke_google_play_recitation_pack(
  p_order_id text,
  p_token_hash text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  purchase public.google_play_purchases%rowtype;
begin
  select * into purchase
  from public.google_play_purchases
  where token_hash = p_token_hash
  for update;
  if not found or purchase.purchase_kind <> 'daily_pack' then
    raise exception 'Google Play add-on purchase was not registered';
  end if;
  if not exists (
    select 1
    from public.google_play_orders
    where token_hash = p_token_hash and order_id = p_order_id
  ) then
    raise exception 'Google Play add-on order does not match the purchase';
  end if;

  update public.google_play_purchases
  set purchase_state = 'VOIDED', revoked_at = now(), updated_at = now()
  where token_hash = p_token_hash;

  update public.recitation_packs
  set checks_remaining = 0, revoked_at = now()
  where checkout_id in (
    select checkout_id from public.google_play_orders
    where token_hash = p_token_hash and order_id = p_order_id
  );
end;
$$;

create or replace function public.revoke_google_play_subscription_order(
  p_order_id text,
  p_token_hash text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  order_row public.google_play_orders%rowtype;
begin
  select * into order_row
  from public.google_play_orders
  where order_id = p_order_id
    and token_hash = p_token_hash
    and order_kind = 'subscription'
  for update;
  if not found then
    raise exception 'Google Play subscription order does not match the purchase';
  end if;

  update public.google_play_orders
  set revoked_at = coalesce(revoked_at, now())
  where order_id = p_order_id;
  update public.subscription_payments
  set expires_at = least(expires_at, now())
  where checkout_id = order_row.checkout_id;
  update public.subscriptions
  set expires_at = least(expires_at, now()), updated_at = now()
  where user_id = order_row.user_id
    and last_checkout_id = order_row.checkout_id;
end;
$$;

revoke all on function public.activate_google_play_subscription(text, text, text, text, uuid, text, text, timestamptz) from public, anon, authenticated;
revoke all on function public.activate_google_play_recitation_pack(text, text, text, text, uuid, text) from public, anon, authenticated;
revoke all on function public.update_google_play_purchase_state(text, text, timestamptz, boolean) from public, anon, authenticated;
revoke all on function public.get_google_play_subscription_to_reconcile(uuid) from public, anon, authenticated;
revoke all on function public.revoke_google_play_recitation_pack(text, text) from public, anon, authenticated;
revoke all on function public.revoke_google_play_subscription_order(text, text) from public, anon, authenticated;
grant execute on function public.activate_google_play_subscription(text, text, text, text, uuid, text, text, timestamptz) to service_role;
grant execute on function public.activate_google_play_recitation_pack(text, text, text, text, uuid, text) to service_role;
grant execute on function public.update_google_play_purchase_state(text, text, timestamptz, boolean) to service_role;
grant execute on function public.get_google_play_subscription_to_reconcile(uuid) to service_role;
grant execute on function public.revoke_google_play_recitation_pack(text, text) to service_role;
grant execute on function public.revoke_google_play_subscription_order(text, text) to service_role;
