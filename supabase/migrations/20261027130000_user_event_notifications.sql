-- Recipient-scoped in-app event notifications for the reconciled GoCart schema.
-- Merchant registration remains in admin_merchant_notifications; this table
-- covers status decisions, reinstatement, order events, and captured payments.
begin;

do $preflight$
begin
  if to_regclass('public.profiles') is null
     or to_regclass('public.merchant_status_audit') is null
     or to_regclass('public.merchant_reinstatement_requests') is null
     or to_regclass('public.orders') is null
     or to_regclass('public.order_items') is null
     or to_regclass('public.razorpay_payment_attempts') is null
     or to_regprocedure('public.has_verified_razorpay_capture(uuid)') is null then
    raise exception 'USER_NOTIFICATION_SCHEMA_PREREQUISITE_MISSING';
  end if;

  if exists (
    select 1 from (values
      ('public.profiles','id'), ('public.profiles','role'),
      ('public.merchant_status_audit','id'),
      ('public.merchant_status_audit','merchant_id'),
      ('public.merchant_status_audit','old_status'),
      ('public.merchant_status_audit','new_status'),
      ('public.merchant_reinstatement_requests','id'),
      ('public.merchant_reinstatement_requests','merchant_id'),
      ('public.merchant_reinstatement_requests','request_status'),
      ('public.orders','id'), ('public.orders','user_id'),
      ('public.orders','status'), ('public.orders','payment_status'),
      ('public.orders','razorpay_order_id'),
      ('public.order_items','order_id'), ('public.order_items','merchant_id'),
      ('public.razorpay_payment_attempts','order_id'),
      ('public.razorpay_payment_attempts','provider_payment_id'),
      ('public.razorpay_payment_attempts','state')
    ) required(table_name,column_name)
    where not exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(required.table_name)
        and a.attname = required.column_name
        and a.attnum > 0 and not a.attisdropped
    )
  ) then
    raise exception 'USER_NOTIFICATION_SCHEMA_CONTRACT_MISMATCH';
  end if;

  if to_regclass('public.user_notifications') is not null
     or to_regprocedure('public.mark_my_user_notification_read(bigint)') is not null
     or exists (
       select 1 from pg_catalog.pg_trigger t
       where not t.tgisinternal and t.tgname in (
         'user_notifications_from_merchant_status_audit',
         'user_notifications_from_reinstatement_request',
         'user_notifications_from_order_items',
         'user_notifications_from_order_updates',
         'user_notifications_from_verified_payment'
       )
     ) then
    raise exception 'USER_NOTIFICATION_OBJECT_CONFLICT';
  end if;
end;
$preflight$;

create table public.user_notifications (
  id bigint generated always as identity primary key,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null check (event_type in (
    'merchant_approved', 'merchant_rejected', 'merchant_suspended', 'merchant_reinstated',
    'reinstatement_requested', 'reinstatement_rejected',
    'order_placed', 'order_received', 'order_status_changed', 'payment_verified'
  )),
  entity_type text not null check (entity_type in (
    'merchant_status_audit', 'reinstatement_request', 'order', 'payment'
  )),
  entity_id text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint user_notifications_event_key
    unique (recipient_id, event_type, entity_type, entity_id)
);

create index user_notifications_recipient_created_idx
  on public.user_notifications (recipient_id, created_at desc, id desc);

alter table public.user_notifications enable row level security;
revoke all privileges on table public.user_notifications
  from public, anon, authenticated, service_role;
grant select on table public.user_notifications to authenticated;
create policy user_notifications_read_own
  on public.user_notifications for select to authenticated
  using (recipient_id = (select auth.uid()));

create function public.emit_user_notification(
  p_recipient_id uuid,
  p_event_type text,
  p_entity_type text,
  p_entity_id text
)
returns void
language sql
security definer
set search_path = ''
as $function$
  insert into public.user_notifications
    (recipient_id,event_type,entity_type,entity_id)
  values (p_recipient_id,p_event_type,p_entity_type,p_entity_id)
  on conflict (recipient_id,event_type,entity_type,entity_id) do nothing;
$function$;
revoke all on function public.emit_user_notification(uuid,text,text,text)
  from public,anon,authenticated,service_role;

create function public.notify_merchant_status_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare v_event text;
begin
  v_event := case
    when new.old_status = 'pending' and new.new_status = 'approved' then 'merchant_approved'
    when new.old_status = 'pending' and new.new_status = 'rejected' then 'merchant_rejected'
    when new.old_status = 'approved' and new.new_status = 'suspended' then 'merchant_suspended'
    when new.old_status = 'suspended' and new.new_status = 'approved' then 'merchant_reinstated'
    else null
  end;
  if v_event is null then return new; end if;

  perform public.emit_user_notification(
    new.merchant_id,v_event,'merchant_status_audit',new.id::text
  );
  perform public.emit_user_notification(
    a.id,v_event,'merchant_status_audit',new.id::text
  ) from public.profiles a where a.role = 'admin';
  return new;
end;
$function$;
revoke all on function public.notify_merchant_status_event()
  from public,anon,authenticated,service_role;
create trigger user_notifications_from_merchant_status_audit
  after insert on public.merchant_status_audit
  for each row execute function public.notify_merchant_status_event();

create function public.notify_reinstatement_request_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT' and new.request_status = 'open' then
    perform public.emit_user_notification(
      a.id,'reinstatement_requested','reinstatement_request',new.id::text
    ) from public.profiles a where a.role = 'admin';
  elsif tg_op = 'UPDATE'
        and old.request_status = 'open'
        and new.request_status = 'rejected' then
    perform public.emit_user_notification(
      new.merchant_id,'reinstatement_rejected','reinstatement_request',new.id::text
    );
  end if;
  return new;
end;
$function$;
revoke all on function public.notify_reinstatement_request_event()
  from public,anon,authenticated,service_role;
create trigger user_notifications_from_reinstatement_request
  after insert or update on public.merchant_reinstatement_requests
  for each row execute function public.notify_reinstatement_request_event();

create function public.notify_order_item_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare v_buyer_id uuid;
begin
  select o.user_id into v_buyer_id
  from public.orders o where o.id = new.order_id;
  if v_buyer_id is null then raise exception 'NOTIFICATION_ORDER_NOT_FOUND'; end if;

  perform public.emit_user_notification(
    v_buyer_id,'order_placed','order',new.order_id::text
  );
  perform public.emit_user_notification(
    new.merchant_id,'order_received','order',new.order_id::text
  );
  return new;
end;
$function$;
revoke all on function public.notify_order_item_event()
  from public,anon,authenticated,service_role;
create trigger user_notifications_from_order_items
  after insert on public.order_items
  for each row execute function public.notify_order_item_event();

create function public.notify_order_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.status is distinct from old.status then
    perform public.emit_user_notification(
      new.user_id,'order_status_changed','order',new.id::text || ':' || new.status
    );
    perform public.emit_user_notification(
      oi.merchant_id,'order_status_changed','order',new.id::text || ':' || new.status
    ) from public.order_items oi where oi.order_id = new.id;
  end if;

  return new;
end;
$function$;
revoke all on function public.notify_order_event()
  from public,anon,authenticated,service_role;
create trigger user_notifications_from_order_updates
  after update on public.orders
  for each row execute function public.notify_order_event();

-- Capture RPCs update the payment attempt first, then the order, in one
-- transaction. Observe the order transition so both rows contain capture
-- evidence when this trigger runs.
create function public.notify_verified_payment_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare v_attempt public.razorpay_payment_attempts%rowtype;
begin
  if new.status is distinct from 'paid'
     or new.payment_status is distinct from 'paid'
     or (old.status = 'paid' and old.payment_status = 'paid')
     or not public.has_verified_razorpay_capture(new.id) then
    return new;
  end if;

  select a.* into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = new.id for share;
  if not found or v_attempt.provider_payment_id is null then
    return new;
  end if;

  perform public.emit_user_notification(
    new.user_id,'payment_verified','payment',v_attempt.provider_payment_id
  );
  perform public.emit_user_notification(
    oi.merchant_id,'payment_verified','payment',v_attempt.provider_payment_id
  ) from public.order_items oi where oi.order_id = new.id;
  return new;
end;
$function$;
revoke all on function public.notify_verified_payment_event()
  from public,anon,authenticated,service_role;
create trigger user_notifications_from_verified_payment
  after update of status,payment_status on public.orders
  for each row execute function public.notify_verified_payment_event();

create function public.mark_my_user_notification_read(p_notification_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null or (select auth.role()) is distinct from 'authenticated' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  update public.user_notifications n
  set read_at = coalesce(n.read_at,now())
  where n.id = p_notification_id and n.recipient_id = v_user_id;
  if not found then raise exception 'NOTIFICATION_NOT_FOUND'; end if;
end;
$function$;
revoke all on function public.mark_my_user_notification_read(bigint)
  from public,anon,authenticated,service_role;
grant execute on function public.mark_my_user_notification_read(bigint)
  to authenticated;

commit;
