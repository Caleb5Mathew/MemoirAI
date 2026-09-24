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

module.exports = { chapterMemories };
