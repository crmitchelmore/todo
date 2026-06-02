import { useEffect, useRef, useState } from 'react';
import { capture } from '../lib/tasks';

// The capture bar is the single most important surface: typing -> Enter must feel instant.
// We clear the input synchronously and fire capture() without blocking the keystroke.
export function CaptureBar() {
  const [value, setValue] = useState('');
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

  return (
    <div className="capture-bar">
      <input
        ref={inputRef}
        value={value}
        placeholder="Capture anything… (e.g. “email Kate the report tomorrow 2pm”)"
        onChange={(e) => setValue(e.target.value)}
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
        Capture
      </button>
    </div>
  );
}
