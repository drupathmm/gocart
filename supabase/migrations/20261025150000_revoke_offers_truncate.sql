begin;

-- The current migration chain creates public.offers, but some existing
-- databases may not have reached that schema yet. Harden it when present and
-- allow the migration to proceed safely when it is absent.
do $revoke_offers_truncate$
begin
  if to_regclass('public.offers') is null then
    raise notice 'Skipping offers TRUNCATE revocation: public.offers does not exist';
  else
    execute 'revoke truncate on table public.offers from public, anon, authenticated';

    -- Fail if either API role can still truncate the table.
    if has_table_privilege('anon', 'public.offers', 'TRUNCATE')
       or has_table_privilege('authenticated', 'public.offers', 'TRUNCATE') then
      raise exception 'CLIENT_OFFERS_TRUNCATE_PRIVILEGE_REMAINS';
    end if;
  end if;
end;
$revoke_offers_truncate$;

commit;
