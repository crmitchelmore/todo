import { useEffect, useRef, useState } from 'react';
import { capture, captureBatch } from '../lib/tasks';
import { parseMarkdownList } from '../lib/markdownList';

// The capture bar is the single most important surface: typing -> Enter must feel instant.
// We clear the input synchronously and fire capture() without blocking the keystroke.
// Pasting a markdown / checkbox list ingests each line as its own item (nesting -> tags).
export function CaptureBar() {
  const [value, setValue] = useState('');
  const [flash, setFlash] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  function submit() {
    const v = value;
    if (!v.trim()) return;
    setValue(''); // instant clear = perceived speed
    void capture(v); // background; not awaited
  }

  function onPaste(e: React.ClipboardEvent<HTMLInputElement>) {
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
    <div className="capture-bar">
      <input
        ref={inputRef}
        value={value}
        placeholder="Capture anything… (or paste a markdown / checkbox list)"
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
      <button onClick={submit} disabled={!value.trim()}>
        Capture <span className="kbd">⏎</span>
      </button>
      {flash && <span className="capture-flash">{flash}</span>}
    </div>
  );
}
