begin;

-- Profiles are readable by authenticated users through the existing RLS
-- policy. Signup may insert only identity fields and the two public roles;
-- merchant_status is assigned by set_initial_profile_status(). Normal
-- profile editing may change only the display name.
revoke all privileges on table public.profiles from anon, authenticated;
revoke insert (id, name, email, role, created_at, merchant_status)
  on table public.profiles from authenticated;
revoke update (id, name, email, role, created_at, merchant_status)
  on table public.profiles from authenticated;
revoke references (id, name, email, role, created_at, merchant_status)
  on table public.profiles from anon, authenticated;

grant select on table public.profiles to authenticated;
grant insert (id, name, email, role) on table public.profiles to authenticated;
grant update (name) on table public.profiles to authenticated;

-- The INSERT policy already limits a new profile to its own auth.uid() and
-- role IN ('user', 'merchant'). The BEFORE INSERT trigger assigns status.

-- Cart mutations must use the SECURITY DEFINER RPCs, which lock the product
-- row and enforce stock. Direct INSERT/UPDATE would bypass those checks.
drop policy if exists "Users can add to own cart" on public.cart_items;
drop policy if exists "Users can update own cart" on public.cart_items;

revoke all privileges on table public.cart_items from anon, authenticated;
revoke insert (id, user_id, product_id, quantity, created_at)
  on table public.cart_items from authenticated;
revoke update (id, user_id, product_id, quantity, created_at)
  on table public.cart_items from authenticated;
revoke references (id, user_id, product_id, quantity, created_at)
  on table public.cart_items from anon, authenticated;

grant select, delete on table public.cart_items to authenticated;

-- A fixed search_path prevents object shadowing inside SECURITY DEFINER code.
alter function public.add_to_cart(bigint, integer) set search_path = '';
alter function public.update_cart_quantity(bigint, integer) set search_path = '';
alter function public.approve_my_merchant_account() set search_path = '';

-- Only authenticated app users need these RPCs. The functions independently
-- validate auth.uid(), ownership, stock, and approval state.
revoke all on function public.add_to_cart(bigint, integer)
  from public, anon, authenticated;
revoke all on function public.update_cart_quantity(bigint, integer)
  from public, anon, authenticated;
revoke all on function public.approve_my_merchant_account()
  from public, anon, authenticated;
grant execute on function public.add_to_cart(bigint, integer) to authenticated;
grant execute on function public.update_cart_quantity(bigint, integer)
  to authenticated;
grant execute on function public.approve_my_merchant_account()
  to authenticated;

-- Admins previously changed merchant_status through direct table UPDATE.
-- Keep that action behind a server-side role check now that authenticated
-- clients no longer have UPDATE permission on profiles.merchant_status.
create or replace function public.admin_set_merchant_status(
  p_merchant_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  ) then
    raise exception 'Only admins can change merchant status.';
  end if;

  if p_status is null or p_status not in ('approved', 'suspended') then
    raise exception 'Invalid merchant status.';
  end if;

  update public.profiles
  set merchant_status = p_status
  where id = p_merchant_id
    and role = 'merchant';

  if not found then
    raise exception 'Merchant profile not found.';
  end if;
end;
$function$;

revoke all on function public.admin_set_merchant_status(uuid, text)
  from public, anon, authenticated;
grant execute on function public.admin_set_merchant_status(uuid, text)
  to authenticated;

commit;
