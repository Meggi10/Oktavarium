function failure(error) {
  const value = typeof error === "object" && error !== null ? error : {};
  const attempt = value.attempt;
  const attemptRecord =
    typeof attempt === "object" && attempt !== null ? attempt : {};
  return {
    message:
      error instanceof Error
        ? error.message
        : "Nieznany b\u0142\u0105d operacji.",
    code: typeof value.code === "string" ? value.code : "",
    status: typeof value.status === "number" ? value.status : 0,
    attemptIdentity:
      typeof attemptRecord.identity === "string"
        ? attemptRecord.identity
        : null,
  };
}
export { failure };
