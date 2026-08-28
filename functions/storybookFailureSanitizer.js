const SAFE_STAGES = new Set([
  "validate", "init", "scene", "title", "narrator", "promptAssembly", "image", "upload", "persist"
]);

function boundedToken(raw) {
  const value = String(raw || "").trim();
  return /^[A-Za-z0-9_.:-]{1,80}$/.test(value) ? value : null;
}

function publicMessageForStage(stage) {
  switch (stage) {
    case "validate":
      return "This memory does not have usable text yet.";
    case "scene":
    case "title":
    case "narrator":
    case "promptAssembly":
      return "We couldn't prepare this memory for illustration.";
    case "image":
      return "The illustration service could not generate this image.";
    case "upload":
    case "persist":
      return "We couldn't save the generated illustration.";
    default:
      return "We couldn't generate this memory's illustration.";
  }
}

function sanitizeStorybookFailure(error, rawStage, timestamp) {
  const stage = SAFE_STAGES.has(rawStage) ? rawStage : "unknown";
  const rawStatus = Number(error?.status || error?.statusCode || error?.response?.status || 0);
  const failure = {
    stage,
    message: publicMessageForStage(stage),
    at: timestamp
  };
  if (Number.isInteger(rawStatus) && rawStatus >= 400 && rawStatus <= 599) {
    failure.httpStatus = rawStatus;
  }
  const errorName = boundedToken(error?.name);
  const finishReason = boundedToken(error?.geminiFinishReason);
  const blockReason = boundedToken(error?.geminiBlockReason);
  if (errorName) failure.errorName = errorName;
  if (finishReason) failure.geminiFinishReason = finishReason;
  if (blockReason) failure.geminiBlockReason = blockReason;
  if (error?.noImageBytes === true) failure.noImageBytes = true;
  return failure;
}

module.exports = { publicMessageForStage, sanitizeStorybookFailure };
