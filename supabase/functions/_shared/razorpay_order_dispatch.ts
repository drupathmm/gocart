export type DispatchMarkerResult = { error?: unknown };

export type ProviderDispatchResult<T> =
  | { state: 'not_marked' }
  | { state: 'dispatched'; response: T };

// The durable marker is the boundary between reclaimable work and an
// ambiguous provider outcome. Never call the provider unless it was saved.
export async function dispatchAfterClaim<T>(
  markDispatchStarted: () => Promise<DispatchMarkerResult>,
  dispatchProviderRequest: () => Promise<T>,
): Promise<ProviderDispatchResult<T>> {
  let marker: DispatchMarkerResult;
  try {
    marker = await markDispatchStarted();
  } catch {
    return { state: 'not_marked' };
  }
  if (marker.error) return { state: 'not_marked' };
  return { state: 'dispatched', response: await dispatchProviderRequest() };
}
