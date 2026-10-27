begin;

select plan(21);

select ok(to_regclass('public.admin_merchant_notifications') is not null,
  'merchant registration notifications are persisted');
select ok(to_regclass('public.admin_merchant_notification_reads') is not null,
  'notification read state is stored per administrator');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.admin_merchant_notifications'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.admin_merchant_notification_reads'::regclass),
  'both notification tables have RLS enabled');
select ok(
  not has_table_privilege('authenticated', 'public.admin_merchant_notifications', 'SELECT')
  and not has_table_privilege('anon', 'public.admin_merchant_notifications', 'SELECT')
  and not has_table_privilege('authenticated', 'public.admin_merchant_notification_reads', 'SELECT'),
  'clients cannot read notification storage tables directly');
select ok(
  not has_function_privilege('anon', 'public.admin_list_merchant_notifications()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.admin_list_merchant_notifications()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.admin_unread_merchant_notification_count()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.admin_mark_merchant_notification_read(bigint)', 'EXECUTE'),
  'notification RPCs are authenticated-only');
select ok(
  has_function_privilege('authenticated', 'public.merchant_sales_analytics()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.merchant_sales_analytics()', 'EXECUTE'),
  'merchant analytics RPC is authenticated-only');

select set_config('request.jwt.claim.sub', '', true);
insert into auth.users (id, email) values
  ('30000000-0000-0000-0000-000000000001', 'notice-admin@example.invalid'),
  ('30000000-0000-0000-0000-000000000002', 'notice-merchant@example.invalid'),
  ('30000000-0000-0000-0000-000000000003', 'notice-buyer@example.invalid');
insert into public.profiles (id, name, email, role, merchant_status) values
  ('30000000-0000-0000-0000-000000000001', 'Notice Admin', 'ignored@example.invalid', 'admin', 'approved'),
  ('30000000-0000-0000-0000-000000000002', 'Notice Merchant', 'ignored@example.invalid', 'merchant', 'pending'),
  ('30000000-0000-0000-0000-000000000003', 'Notice Buyer', 'ignored@example.invalid', 'user', 'approved');

select ok((select count(*) = 1 from public.admin_merchant_notifications
  where merchant_id = '30000000-0000-0000-0000-000000000002'),
  'a pending merchant registration creates one notification');
update public.profiles set merchant_status = 'pending'
where id = '30000000-0000-0000-0000-000000000002';
select ok((select count(*) = 1 from public.admin_merchant_notifications
  where merchant_id = '30000000-0000-0000-0000-000000000002'),
  'repeated pending profile updates do not duplicate the registration notification');

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select ok((select count(*) = 1 from public.admin_list_merchant_notifications()),
  'an authenticated admin can read the pending registration');
select is(public.admin_unread_merchant_notification_count(), 1,
  'unread count is scoped to the authenticated admin');
select lives_ok(
  $$select public.admin_mark_merchant_notification_read(
      (select notification_id from public.admin_list_merchant_notifications() limit 1))$$,
  'an authenticated admin can mark a registration notification read');
select is(public.admin_unread_merchant_notification_count(), 0,
  'marking a notification read updates that admin unread count');
reset role;

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select throws_ok(
  $$select * from public.admin_list_merchant_notifications()$$,
  'P0001', 'NOT_AUTHORIZED',
  'ordinary buyers cannot read admin merchant notifications');
select throws_ok(
  $$select public.merchant_sales_analytics()$$,
  'P0001', 'NOT_AUTHORIZED',
  'ordinary buyers cannot read merchant analytics');
reset role;

select set_config('request.jwt.claim.sub', '', true);
insert into auth.users (id, email) values
  ('30000000-0000-0000-0000-000000000004', 'analytics-merchant-b@example.invalid');
insert into public.profiles (id, name, email, role) values
  ('30000000-0000-0000-0000-000000000004', 'Analytics Merchant B', 'ignored@example.invalid', 'merchant');
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.admin_set_merchant_status(
  '30000000-0000-0000-0000-000000000002', 'approved', null
);
select public.admin_set_merchant_status(
  '30000000-0000-0000-0000-000000000004', 'approved', null
);
reset role;
select ok((select resolved_at is not null and resolved_status = 'approved'
  from public.admin_merchant_notifications
  where merchant_id = '30000000-0000-0000-0000-000000000002'),
  'merchant approval resolves its registration notification');
select is((select count(*) from public.admin_merchant_notifications n
  where n.merchant_id = '30000000-0000-0000-0000-000000000002'
    and n.resolved_at is null), 0::bigint,
  'resolved registration notifications are removed from the pending inbox');

insert into public.products (
  merchant_id, name, original_price, offer_price, price, stock, category
) values
  ('30000000-0000-0000-0000-000000000002', 'Analytics A Product', 50, 45, 45, 10, 'Electronics'),
  ('30000000-0000-0000-0000-000000000004', 'Analytics B Product', 900, 900, 900, 10, 'Electronics');
insert into public.orders (user_id, total_amount, status, payment_status)
values
  ('30000000-0000-0000-0000-000000000003', 45, 'pending', 'unpaid'),
  ('30000000-0000-0000-0000-000000000003', 30, 'pending', 'unpaid'),
  ('30000000-0000-0000-0000-000000000003', 450, 'pending', 'unpaid'),
  ('30000000-0000-0000-0000-000000000003', 100, 'cancelled', 'unpaid'),
  ('30000000-0000-0000-0000-000000000003', 900, 'pending', 'unpaid');

-- Construct legitimate local payment attempts and settle through the same
-- verified-capture RPC used by the server; never fabricate a paid order row.
update public.orders o set razorpay_order_id = 'order_analytics_' || o.total_amount::text
where o.user_id = '30000000-0000-0000-0000-000000000003';
insert into public.razorpay_payment_attempts (
  order_id, buyer_id, expected_amount_paise, currency, state, provider_order_id
)
select o.id, o.user_id, (o.total_amount * 100)::bigint, 'INR', 'created', o.razorpay_order_id
from public.orders o
where o.user_id = '30000000-0000-0000-0000-000000000003'
  and o.total_amount in (45, 30, 450, 900);
select set_config('request.jwt.claim.role', 'service_role', true);
do $verified_analytics_fixtures$
declare v_order record;
begin
  for v_order in
    select id, user_id, razorpay_order_id, (total_amount * 100)::bigint amount_paise
    from public.orders
    where user_id = '30000000-0000-0000-0000-000000000003'
      and total_amount in (45, 30, 900)
  loop
    perform public.record_verified_razorpay_payment(
      v_order.id, v_order.user_id, v_order.razorpay_order_id,
      'pay_analytics_' || v_order.amount_paise::text,
      v_order.amount_paise, 'INR'
    );
  end loop;
end;
$verified_analytics_fixtures$;
update public.orders set status = 'delivered'
where user_id = '30000000-0000-0000-0000-000000000003' and total_amount = 30;
select set_config('request.jwt.claim.role', 'authenticated', true);
insert into public.order_items (
  order_id, product_id, merchant_id, product_name, unit_price, quantity, line_total
)
select o.id, p.id, p.merchant_id, p.name, p.offer_price, 1, p.offer_price
from public.orders o
join public.products p on p.name = 'Analytics A Product'
where o.total_amount in (45, 30, 450, 100);
insert into public.order_items (
  order_id, product_id, merchant_id, product_name, unit_price, quantity, line_total
)
select o.id, p.id, p.merchant_id, p.name, p.offer_price, 1, p.offer_price
from public.orders o
join public.products p on p.name = 'Analytics B Product'
where o.total_amount = 900;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select is((public.merchant_sales_analytics()->>'paid_item_sales')::numeric, 75::numeric,
  'merchant analytics sum only this merchant eligible paid item lines');
select is((public.merchant_sales_analytics()->>'total_orders')::integer, 2,
  'merchant analytics counts each eligible order once');
select is((public.merchant_sales_analytics()->>'pending_orders')::integer, 1,
  'paid orders awaiting fulfillment are reported as pending');
select is((public.merchant_sales_analytics()->>'completed_orders')::integer, 1,
  'delivered paid orders are reported as completed');
select ok(
  not ((public.merchant_sales_analytics()->'top_products')::text like '%Analytics B Product%')
  and not (public.merchant_sales_analytics()::text like '%notice-buyer%'),
  'analytics does not expose another merchant product or buyer identity');
reset role;

select * from finish();
rollback;
