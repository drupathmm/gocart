import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { corsHeaders } from './cors.ts';

test('Edge Function preflight permits required request methods and headers', () => {
  assert.match(corsHeaders['Access-Control-Allow-Methods'], /POST/);
  assert.match(corsHeaders['Access-Control-Allow-Methods'], /OPTIONS/);
  assert.match(corsHeaders['Access-Control-Allow-Headers'], /authorization/i);
  assert.match(corsHeaders['Access-Control-Allow-Headers'], /apikey/i);
  assert.match(corsHeaders['Access-Control-Allow-Headers'], /content-type/i);
  assert.equal(corsHeaders['Access-Control-Allow-Credentials'], undefined);
});
