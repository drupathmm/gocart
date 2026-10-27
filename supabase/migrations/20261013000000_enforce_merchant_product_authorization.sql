begin;

-- Keep merchant authorization in PostgreSQL so direct REST calls cannot
-- bypass the checks currently performed by the Flutter service.
drop policy if exists "Merchants insert own products" on public.products;
create policy "Approved merchants insert own products"
  on public.products for insert to authenticated
  with check (
    merchant_id = (select auth.uid())
    and exists (
      select 1
      from public.profiles p
      where p.id = (select auth.uid())
        and p.role = 'merchant'
        and p.merchant_status = 'approved'
    )
  );

drop policy if exists "Merchants update own product fields" on public.products;
create policy "Approved merchants update own product fields"
  on public.products for update to authenticated
  using (
    merchant_id = (select auth.uid())
    and exists (
      select 1
      from public.profiles p
      where p.id = (select auth.uid())
        and p.role = 'merchant'
        and p.merchant_status = 'approved'
    )
  )
  with check (
    merchant_id = (select auth.uid())
    and exists (
      select 1
      from public.profiles p
      where p.id = (select auth.uid())
        and p.role = 'merchant'
        and p.merchant_status = 'approved'
    )
  );

-- Preserve the existing RPC contract. A SECURITY DEFINER function must do
-- its own authorization because table grants and RLS do not constrain it.
create or replace function public.merchant_set_product_stock(
  p_product_id bigint,
  p_stock integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_merchant_status text;
begin
  if v_user is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select p.role, p.merchant_status
    into v_role, v_merchant_status
  from public.profiles p
  where p.id = v_user;

  if v_role is distinct from 'merchant' then
    raise exception 'NOT_MERCHANT';
  end if;
  if v_merchant_status = 'suspended' then
    raise exception 'MERCHANT_SUSPENDED';
  end if;
  if v_merchant_status is distinct from 'approved' then
    raise exception 'MERCHANT_NOT_APPROVED';
  end if;
  if p_stock is null or p_stock < 0 then
    raise exception 'INVALID_STOCK';
  end if;

  update public.products
  set stock = p_stock,
      updated_at = now()
  where id = p_product_id
    and merchant_id = v_user;

  if not found then
    raise exception 'PRODUCT_NOT_FOUND';
  end if;
end;
$function$;

revoke all on function public.merchant_set_product_stock(bigint, integer)
  from public, anon, authenticated;
grant execute on function public.merchant_set_product_stock(bigint, integer)
  to authenticated;

commit;
