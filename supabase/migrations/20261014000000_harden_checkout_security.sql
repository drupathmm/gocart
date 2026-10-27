begin;

-- All application relations in these functions are schema-qualified. An empty
-- path prevents caller-controlled name resolution in SECURITY DEFINER code.
alter function public.place_order(text, text) set search_path = '';
alter function public.place_demo_order() set search_path = '';

-- Preserve the legacy merchant access contract, but expose only item rows for
-- products belonging to the current merchant. Buyers retain their own rows.
drop policy if exists "Users can view own order items" on public.order_items;
create policy "Buyers and merchants can view authorized order items"
  on public.order_items for select to authenticated
  using (
    merchant_id = (select auth.uid())
    or exists (
      select 1
      from public.orders o
      where o.id = order_id
        and o.user_id = (select auth.uid())
    )
  );

commit;
