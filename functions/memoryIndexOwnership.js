function memoryIndexOwner(snapshot) {
  if (!snapshot?.exists) return null;
  const ownerId = String(snapshot.data()?.ownerId || "").trim();
  return ownerId || null;
}

function memoryIndexClaimDecision(snapshot, userId) {
  const ownerId = memoryIndexOwner(snapshot);
  if (!ownerId) return "claim";
  return ownerId === userId ? "owned" : "collision";
}

function memoryIndexBelongsToUser(snapshot, userId) {
  return memoryIndexOwner(snapshot) === userId;
}

module.exports = {
  memoryIndexBelongsToUser,
  memoryIndexClaimDecision,
  memoryIndexOwner
};
