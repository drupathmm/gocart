import assert from 'node:assert/strict';
import test from 'node:test';
import {
  parseReport,
  reconciliationSql,
  summarizeReport,
} from './payment_reconciliation_report.mjs';

const emptyReport = {
  transaction_read_only: true,
  expired_processing_leases: [],
  retryable_events: [],
  quarantined_payment_events: [],
  captured_attempts_needing_review: [],
  payment_order_mismatches: [],
};

test('normal reconciliation report has no unresolved records', () => {
  assert.deepEqual(summarizeReport(emptyReport), {
    expired_processing_leases: 0,
    retryable_events: 0,
    quarantined_payment_events: 0,
    captured_attempts_needing_review: 0,
    payment_order_mismatches: 0,
  });
});

test('inconsistent records are represented in the expected review categories', () => {
  const report = {
    ...emptyReport,
    expired_processing_leases: [{ event_id: 'evt_expired', attempt_count: 3 }],
    retryable_events: [{ event_id: 'evt_retry', last_error_code: 'PROVIDER_TIMEOUT' }],
    quarantined_payment_events: [{
      event_id: 'evt_conflict',
      state: 'reconciliation_required',
      last_error_code: 'WEBHOOK_EVENT_ID_CONFLICT',
      provider_entity_reference: 'pay_…1234',
    }],
    captured_attempts_needing_review: [{
      attempt_id: 'attempt-1',
      reason: 'captured_after_cancellation_review',
    }],
    payment_order_mismatches: [{
      attempt_id: 'attempt-2',
      amount_mismatch: true,
      currency_mismatch: false,
      provider_order_id_mismatch: true,
    }],
  };
  assert.deepEqual(summarizeReport(report), {
    expired_processing_leases: 1,
    retryable_events: 1,
    quarantined_payment_events: 1,
    captured_attempts_needing_review: 1,
    payment_order_mismatches: 1,
  });
  assert.equal(report.payment_order_mismatches[0].amount_mismatch, true);
  assert.equal(report.quarantined_payment_events[0].provider_entity_reference, 'pay_…1234');
});

test('report refuses output unless PostgreSQL confirms a read-only transaction', () => {
  assert.equal(parseReport(JSON.stringify(emptyReport)).transaction_read_only, true);
  assert.throws(() => parseReport(JSON.stringify({
    ...emptyReport,
    transaction_read_only: false,
  })), /read-only transaction/);
  assert.match(reconciliationSql.trimStart(), /^begin read only;/i);
});
