-- Kwnchwkcha Sung — production starter database
-- Run this in Supabase SQL Editor AFTER creating your project.

create extension if not exists pgcrypto;

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique default 'KWSADMIN',
  created_at timestamptz not null default now()
);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 100),
  mobile text not null check (mobile ~ '^[0-9]{10}$'),
  show_time text not null check (show_time in ('5:00 PM – 8:00 PM','8:30 PM – 11:30 PM')),
  qty integer not null check (qty between 1 and 20),
  total integer not null check (total = qty * 100),
  txn_ref text not null check (char_length(trim(txn_ref)) between 3 and 100),
  status text not null default 'pending' check (status in ('pending','approved','cancelled')),
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  approved_by uuid references auth.users(id)
);

create table if not exists public.tickets (
  ticket_no integer primary key check (ticket_no between 1 and 500),
  booking_id uuid unique references public.bookings(id) on delete set null,
  allocated_at timestamptz
);

insert into public.tickets(ticket_no)
select g from generate_series(1,500) g
on conflict do nothing;

create index if not exists bookings_created_at_idx on public.bookings(created_at desc);
create index if not exists bookings_status_idx on public.bookings(status);
create index if not exists tickets_booking_id_idx on public.tickets(booking_id);

alter table public.admin_users enable row level security;
alter table public.bookings enable row level security;
alter table public.tickets enable row level security;

revoke all on public.admin_users from anon, authenticated;
revoke all on public.bookings from anon, authenticated;
revoke all on public.tickets from anon, authenticated;

grant select, update on public.bookings to authenticated;
grant select on public.tickets to authenticated;
grant select on public.admin_users to authenticated;

-- Helper used by RLS. Security definer avoids recursive policy checks.
create or replace function public.is_kws_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admin_users a where a.user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_kws_admin() from public;
grant execute on function public.is_kws_admin() to authenticated;

create policy "admins can read bookings"
on public.bookings for select to authenticated
using (public.is_kws_admin());

create policy "admins can update bookings"
on public.bookings for update to authenticated
using (public.is_kws_admin())
with check (public.is_kws_admin());

create policy "admins can read tickets"
on public.tickets for select to authenticated
using (public.is_kws_admin());

create policy "admins can read their admin row"
on public.admin_users for select to authenticated
using (user_id = (select auth.uid()));

-- Public booking RPC. It allocates KWS-001 ... KWS-500 atomically.
create or replace function public.submit_booking(
  p_name text,
  p_mobile text,
  p_show_time text,
  p_qty integer,
  p_txn_ref text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking_id uuid;
  v_numbers integer[];
  v_count integer;
begin
  p_name := trim(p_name);
  p_mobile := trim(p_mobile);
  p_txn_ref := trim(p_txn_ref);

  if char_length(p_name) < 2 or char_length(p_name) > 100 then
    raise exception 'Invalid name';
  end if;
  if p_mobile !~ '^[0-9]{10}$' then
    raise exception 'Invalid mobile number';
  end if;
  if p_show_time not in ('5:00 PM – 8:00 PM','8:30 PM – 11:30 PM') then
    raise exception 'Invalid show time';
  end if;
  if p_qty < 1 or p_qty > 20 then
    raise exception 'Ticket quantity must be 1 to 20';
  end if;
  if char_length(p_txn_ref) < 3 or char_length(p_txn_ref) > 100 then
    raise exception 'Invalid transaction reference';
  end if;

  select array_agg(ticket_no order by ticket_no), count(*)
  into v_numbers, v_count
  from (
    select ticket_no from public.tickets
    where booking_id is null
    order by ticket_no
    limit p_qty
    for update skip locked
  ) q;

  if coalesce(v_count,0) <> p_qty then
    raise exception 'Not enough tickets available';
  end if;

  insert into public.bookings(name,mobile,show_time,qty,total,txn_ref)
  values (p_name,p_mobile,p_show_time,p_qty,p_qty*100,p_txn_ref)
  returning id into v_booking_id;

  update public.tickets
  set booking_id = v_booking_id, allocated_at = now()
  where ticket_no = any(v_numbers);

  return jsonb_build_object(
    'id', v_booking_id,
    'ticket_numbers', (select jsonb_agg('KWS-' || lpad(n::text,3,'0') order by n) from unnest(v_numbers) n),
    'name', p_name,
    'mobile', p_mobile,
    'show_time', p_show_time,
    'qty', p_qty,
    'total', p_qty*100,
    'txn_ref', p_txn_ref,
    'status', 'pending'
  );
end;
$$;

revoke all on function public.submit_booking(text,text,text,integer,text) from public;
grant execute on function public.submit_booking(text,text,text,integer,text) to anon, authenticated;

-- Approve/cancel functions so the browser never needs a service_role key.
create or replace function public.set_booking_status(p_booking_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings;
begin
  if not public.is_kws_admin() then raise exception 'Not authorized'; end if;
  if p_status not in ('approved','cancelled') then raise exception 'Invalid status'; end if;

  update public.bookings
  set status = p_status,
      approved_at = case when p_status='approved' then now() else null end,
      approved_by = case when p_status='approved' then (select auth.uid()) else null end
  where id = p_booking_id
  returning * into v_booking;

  if not found then raise exception 'Booking not found'; end if;

  if p_status='cancelled' then
    update public.tickets set booking_id=null, allocated_at=null where booking_id=p_booking_id;
  end if;

  return jsonb_build_object('id',v_booking.id,'status',v_booking.status);
end;
$$;

revoke all on function public.set_booking_status(uuid,text) from public;
grant execute on function public.set_booking_status(uuid,text) to authenticated;

-- IMPORTANT: create the Auth user in Supabase Dashboard first, then run the line below
-- replacing YOUR_EMAIL with the email used for the admin login.
-- insert into public.admin_users(user_id, username)
-- select id, 'KWSADMIN' from auth.users where email='YOUR_EMAIL'
-- on conflict (user_id) do update set username='KWSADMIN';
