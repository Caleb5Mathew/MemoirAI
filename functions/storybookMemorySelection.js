function chapterMemories(memories, pinnedMemoryIds = []) {
  if (!Array.isArray(memories)) return [];
  const pinned = new Set(
    Array.isArray(pinnedMemoryIds)
      ? pinnedMemoryIds.map((id) => String(id || "").trim()).filter(Boolean)
      : []
  );
  return memories.filter((memory) => {
    const hasChapter = typeof memory?.chapter === "string" && memory.chapter.trim().length > 0;
    const isPinned = pinned.size === 0 || pinned.has(String(memory?.id || ""));
    return hasChapter && isPinned;
  });
}

function preferredMemoryTranscript(memory) {
  const edited = memory?.transcriptionEdited;
  if (edited === "") return "";
  if (typeof edited === "string" && edited.trim()) return edited.trim();
  for (const value of [memory?.transcription, memory?.transcriptionRaw]) {
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return "";
}

module.exports = { chapterMemories, preferredMemoryTranscript };
