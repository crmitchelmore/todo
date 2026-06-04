import { useEffect, useRef, useState } from 'react';
import { capture, captureBatch } from '../lib/tasks';
import { parseMarkdownList } from '../lib/markdownList';
import { fileToAttachmentDraft, imageFilesFromTransfer, type AttachmentDraft } from '../lib/attachments';

// The capture bar is the single most important surface: typing -> Enter must feel instant.
// We clear the input synchronously and fire capture() without blocking the keystroke.
// Pasting a markdown / checkbox list ingests each line as its own item (nesting -> tags).
export function CaptureBar() {
  const [value, setValue] = useState('');
  const [flash, setFlash] = useState<string | null>(null);
  const [attachments, setAttachments] = useState<AttachmentDraft[]>([]);
  const [dragging, setDragging] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  function submit() {
    const v = value;
    if (!v.trim() && attachments.length === 0) return;
    setValue(''); // instant clear = perceived speed
    const outgoing = attachments;
    setAttachments([]);
    void capture(v, outgoing); // background; not awaited
  }

  async function addImageFiles(files: File[]) {
    const drafts = (await Promise.all(files.slice(0, 4).map(fileToAttachmentDraft)))
      .filter((draft): draft is AttachmentDraft => Boolean(draft));
    if (drafts.length === 0) {
      setFlash('Image was too large or unsupported');
    } else {
      setAttachments((current) => [...current, ...drafts].slice(0, 4));
      setFlash(`Attached ${drafts.length} image${drafts.length === 1 ? '' : 's'}`);
    }
    window.setTimeout(() => setFlash(null), 2500);
  }

  function onPaste(e: React.ClipboardEvent<HTMLInputElement>) {
    const imageFiles = imageFilesFromTransfer(e.clipboardData);
    if (imageFiles.length > 0) {
      e.preventDefault();
      void addImageFiles(imageFiles);
      return;
    }
    const text = e.clipboardData.getData('text');
    const items = parseMarkdownList(text);
    if (!items || items.length === 0) return; // let the browser paste normally
    e.preventDefault();
    void captureBatch(items);
    setValue('');
    setFlash(`Added ${items.length} item${items.length === 1 ? '' : 's'} from list`);
    window.setTimeout(() => setFlash(null), 2500);
  }

  return (
    <div
      className={`capture-bar${dragging ? ' dragging' : ''}`}
      onDragOver={(e) => {
        if (imageFilesFromTransfer(e.dataTransfer).length === 0) return;
        e.preventDefault();
        setDragging(true);
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={(e) => {
        const files = imageFilesFromTransfer(e.dataTransfer);
        if (files.length === 0) return;
        e.preventDefault();
        setDragging(false);
        void addImageFiles(files);
      }}
    >
      <input
        ref={inputRef}
        value={value}
        placeholder="Capture anything… (paste/drop images or markdown lists)"
        onChange={(e) => setValue(e.target.value)}
        onPaste={onPaste}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault();
            submit();
          }
        }}
        autoComplete="off"
        spellCheck={false}
      />
      <button onClick={submit} disabled={!value.trim() && attachments.length === 0}>
        Capture <span className="kbd">⏎</span>
      </button>
      {attachments.length > 0 && (
        <div className="capture-attachments" aria-label="Pending image attachments">
          {attachments.map((attachment, index) => (
            <button
              key={`${attachment.preview_data_url.slice(0, 48)}-${index}`}
              type="button"
              className="capture-attachment"
              onClick={() => setAttachments((current) => current.filter((_, i) => i !== index))}
              title="Remove image"
            >
              <img src={attachment.preview_data_url} alt={attachment.filename ?? 'Image attachment'} />
            </button>
          ))}
        </div>
      )}
      {flash && <span className="capture-flash">{flash}</span>}
    </div>
  );
}
