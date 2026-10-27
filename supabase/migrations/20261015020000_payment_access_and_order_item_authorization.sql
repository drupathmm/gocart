begin;

-- The verification Edge Function reads this ledger with its service-role
-- client. Keep ordinary API roles denied while granting only that read.
grant select on table public.razorpay_payment_attempts to service_role;

-- Historical order items remain visible to buyers. Merchant access follows
-- the same current approval rule used to manage products and stock.
drop policy if exists "Buyers and merchants can view authorized order items"
  on public.order_items;
create policy "Buyers and approved merchants can view authorized order items"
  on public.order_items for select to authenticated
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = (select auth.uid())
        and p.id = merchant_id
        and p.role = 'merchant'
        and p.merchant_status = 'approved'
    )
    or exists (
      select 1
      from public.orders o
      where o.id = order_id
        and o.user_id = (select auth.uid())
    )
  );

commit;
