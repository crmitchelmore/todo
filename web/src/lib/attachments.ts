export const MAX_ATTACHMENT_BYTES = 512 * 1024;
export const MAX_ATTACHMENT_DATA_URL_BYTES = 800 * 1024;
const MAX_DIMENSION = 1600;

export interface AttachmentDraft {
  filename: string | null;
  mime_type: 'image/jpeg' | 'image/png' | 'image/webp' | 'image/gif';
  byte_size: number;
  preview_data_url: string;
}

export function imageFilesFromTransfer(data: DataTransfer): File[] {
  const files = [...data.files].filter((file) => file.type.startsWith('image/'));
  if (files.length > 0) return files;
  return [...data.items]
    .filter((item) => item.kind === 'file')
    .map((item) => item.getAsFile())
    .filter((file): file is File => file !== null && file.type.startsWith('image/'));
}

export function dataUrlByteLength(dataUrl: string): number {
  const marker = ';base64,';
  const index = dataUrl.indexOf(marker);
  if (index < 0) return 0;
  const base64 = dataUrl.slice(index + marker.length);
  const padding = base64.endsWith('==') ? 2 : base64.endsWith('=') ? 1 : 0;
  return Math.max(0, Math.floor((base64.length * 3) / 4) - padding);
}

export async function fileToAttachmentDraft(file: File): Promise<AttachmentDraft | null> {
  if (!file.type.startsWith('image/')) return null;
  const filename = file.name || 'image attachment';
  const bitmap = await createBitmap(file).catch(() => null);
  if (bitmap) {
    const canvas = document.createElement('canvas');
    const scale = Math.min(1, MAX_DIMENSION / Math.max(bitmap.width, bitmap.height));
    canvas.width = Math.max(1, Math.round(bitmap.width * scale));
    canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    const context = canvas.getContext('2d');
    if (context) {
      context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
      const preview = encodeCanvas(canvas);
      closeBitmap(bitmap);
      if (preview) return { filename, ...preview };
    }
    closeBitmap(bitmap);
  }

  if (file.size > MAX_ATTACHMENT_BYTES) return null;
  const dataUrl = await readAsDataUrl(file);
  if (!isSupportedImageDataUrl(dataUrl)) return null;
  if (dataUrl.length > MAX_ATTACHMENT_DATA_URL_BYTES) return null;
  return {
    filename,
    mime_type: mimeTypeFromDataUrl(dataUrl),
    byte_size: dataUrlByteLength(dataUrl),
    preview_data_url: dataUrl,
  };
}

function encodeCanvas(canvas: HTMLCanvasElement): Omit<AttachmentDraft, 'filename'> | null {
  const attempts: ReadonlyArray<{ type: AttachmentDraft['mime_type']; quality?: number }> = [
    { type: 'image/jpeg', quality: 0.82 },
    { type: 'image/jpeg', quality: 0.68 },
    { type: 'image/webp', quality: 0.78 },
  ];
  for (const attempt of attempts) {
    const dataUrl = canvas.toDataURL(attempt.type, attempt.quality);
    const byteSize = dataUrlByteLength(dataUrl);
    if (byteSize > 0 && byteSize <= MAX_ATTACHMENT_BYTES && dataUrl.length <= MAX_ATTACHMENT_DATA_URL_BYTES) {
      return { mime_type: attempt.type, byte_size: byteSize, preview_data_url: dataUrl };
    }
  }
  return null;
}

function createBitmap(file: File): Promise<ImageBitmap> {
  if (!('createImageBitmap' in window)) return Promise.reject(new Error('createImageBitmap unavailable'));
  return createImageBitmap(file);
}

function closeBitmap(bitmap: ImageBitmap) {
  if ('close' in bitmap) bitmap.close();
}

function readAsDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result ?? ''));
    reader.onerror = () => reject(reader.error ?? new Error('failed to read image'));
    reader.readAsDataURL(file);
  });
}

function isSupportedImageDataUrl(dataUrl: string): boolean {
  return /^data:image\/(jpeg|png|webp|gif);base64,/i.test(dataUrl);
}

function mimeTypeFromDataUrl(dataUrl: string): AttachmentDraft['mime_type'] {
  const match = /^data:(image\/(?:jpeg|png|webp|gif));base64,/i.exec(dataUrl);
  return (match?.[1].toLowerCase() as AttachmentDraft['mime_type']) ?? 'image/jpeg';
}
