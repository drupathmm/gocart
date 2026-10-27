begin;

-- Route authenticated checkout through a validating wrapper. The core
-- transaction remains place_order; callers cannot omit its idempotency key.
create or replace function public.checkout_place_order(
  p_offer_code text default null,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_key text := nullif(trim(coalesce(p_idempotency_key, '')), '');
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if v_key is null or length(v_key) < 8 or length(v_key) > 128 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  return public.place_order(p_offer_code, v_key);
end;
$function$;

revoke all on function public.checkout_place_order(text, text)
  from public, anon, authenticated;
grant execute on function public.checkout_place_order(text, text)
  to authenticated;

-- This lower-level function remains available only to trusted function
-- owners; authenticated clients must use checkout_place_order.
revoke all on function public.place_order(text, text)
  from public, anon, authenticated;

-- Disable the legacy no-key checkout entry point. No Flutter caller remains,
-- and it could otherwise create an order without an idempotency guarantee.
revoke all on function public.place_demo_order()
  from public, anon, authenticated;

commit;
