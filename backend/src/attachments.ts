export const ATTACHMENT_MAX_BYTES = 512 * 1024;
export const ATTACHMENT_MAX_DATA_URL_BYTES = 800 * 1024;

const IMAGE_MIME_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);

export interface ValidAttachmentData {
  readonly task_id: string;
  readonly filename?: string | null;
  readonly mime_type: string;
  readonly byte_size: number;
  readonly preview_data_url: string;
  readonly created_at?: string | null;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function validateAttachmentData(data: Record<string, unknown>): ValidAttachmentData | null {
  const taskId = typeof data.task_id === "string" && UUID_RE.test(data.task_id) ? data.task_id : null;
  const mimeType = typeof data.mime_type === "string" ? data.mime_type.trim().toLowerCase() : "";
  const byteSize = typeof data.byte_size === "number" && Number.isInteger(data.byte_size) ? data.byte_size : null;
  const previewDataUrl = typeof data.preview_data_url === "string" ? data.preview_data_url : "";
  const filename = typeof data.filename === "string" && data.filename.trim()
    ? data.filename.trim().slice(0, 160)
    : null;
  const createdAt = typeof data.created_at === "string" && !Number.isNaN(new Date(data.created_at).getTime())
    ? data.created_at
    : null;

  if (!taskId) return null;
  if (!IMAGE_MIME_TYPES.has(mimeType)) return null;
  if (byteSize === null || byteSize < 1 || byteSize > ATTACHMENT_MAX_BYTES) return null;
  if (!previewDataUrl.startsWith(`data:${mimeType};base64,`)) return null;
  if (Buffer.byteLength(previewDataUrl, "utf8") > ATTACHMENT_MAX_DATA_URL_BYTES) return null;

  return {
    task_id: taskId,
    filename,
    mime_type: mimeType,
    byte_size: byteSize,
    preview_data_url: previewDataUrl,
    created_at: createdAt,
  };
}
