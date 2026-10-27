import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'METHOD_NOT_ALLOWED' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceRoleKey) {
    console.error('checkout reservation reaper configuration is unavailable');
    return new Response(JSON.stringify({ error: 'REAPER_UNAVAILABLE' }), {
      status: 503,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // The gateway validates the JWT; this endpoint additionally permits only the
  // configured service credential. It must be called by a trusted scheduler.
  if (req.headers.get('Authorization') !== `Bearer ${serviceRoleKey}`) {
    return new Response(JSON.stringify({ error: 'NOT_AUTHORIZED' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const { data, error } = await admin.rpc('reap_expired_checkout_reservations', {
    p_batch_size: 100,
  });
  if (error || !Array.isArray(data) || data.length !== 1) {
    console.error('checkout reservation recovery failed', {
      code: error?.code ?? 'INVALID_RECOVERY_RESPONSE',
    });
    return new Response(JSON.stringify({ error: 'RESERVATION_RECOVERY_FAILED' }), {
      status: 503,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify(data[0]), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
