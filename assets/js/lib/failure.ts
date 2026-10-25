// Exceptions from fetch, browser storage and signed API calls share one UI boundary.
export function failure(error: unknown) {
  const value =
    typeof error === "object" && error !== null
      ? (error as Record<string, unknown>)
      : {};
  const attempt = value.attempt;
  const attemptRecord =
    typeof attempt === "object" && attempt !== null
      ? (attempt as Record<string, unknown>)
      : {};
  return {
    message: error instanceof Error ? error.message : "Nieznany błąd operacji.",
    code: typeof value.code === "string" ? value.code : "",
    status: typeof value.status === "number" ? value.status : 0,
    attemptIdentity:
      typeof attemptRecord.identity === "string"
        ? attemptRecord.identity
        : null,
  };
}
