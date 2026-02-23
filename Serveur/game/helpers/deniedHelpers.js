function userDenied(code, params = null) {
  const denied = { valid: false, kind: "user", code };
  if (params && typeof params === "object" && !Array.isArray(params) && Object.keys(params).length > 0) {
    denied.params = params;
  }
  return denied;
}

function technicalDenied(debugReason) {
  return { valid: false, kind: "technical", debug_reason: debugReason };
}

function deniedTracePayload(result) {
  if (String(result?.kind) === "user") {
    return {
      kind: "user",
      reason_code: String(result?.code ?? ""),
    };
  }
  return {
    kind: "technical",
    reason_debug: String(result?.debug_reason ?? ""),
  };
}

export {
  deniedTracePayload,
  technicalDenied,
  userDenied,
};
