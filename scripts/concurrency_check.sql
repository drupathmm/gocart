-- Acceptance checks (run against a staging project, not production data).
--
-- 1) Concurrency: stock = 1, two authenticated sessions call place_order
--    at the same time. Exactly one commit succeeds; the other raises OUT_OF_STOCK.
--    Example (two psql sessions after setting request.jwt.claim.sub):
--      select public.place_order(null, gen_random_uuid()::text);
--
-- 2) Security: a user JWT against PostgREST must not insert orders.
--      POST /rest/v1/orders  -> 403 (RLS / GRANTs deny INSERT).
--
-- 3) Price integrity: changing a product price only in the Flutter client
--    cannot change total_amount. place_order snapshots products.offer_price
--    (aliased as price) inside PostgreSQL.

select 'See comments in this file for manual verification steps.' as note;
