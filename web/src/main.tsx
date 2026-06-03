import React, { useEffect, useState } from 'react';
import ReactDOM from 'react-dom/client';
import { PowerSyncContext } from '@powersync/react';
import { db, initPowerSync, resetLocalData } from './powersync/db';
import { isAuthenticated, onAuthChange } from './lib/auth';
import { SignIn } from './components/SignIn';
import App from './App';
import './styles.css';

function Root() {
  const [authed, setAuthed] = useState(isAuthenticated());

  useEffect(() => onAuthChange(() => setAuthed(isAuthenticated())), []);

  useEffect(() => {
    if (authed) {
      // Fresh sign-in: wipe any prior local data so accounts can't cross-contaminate, then sync.
      void resetLocalData().then(() => initPowerSync());
    }
  }, [authed]);

  if (!authed) {
    return <SignIn onSignedIn={() => setAuthed(true)} />;
  }

  return (
    <PowerSyncContext.Provider value={db}>
      <App />
    </PowerSyncContext.Provider>
  );
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Root />
  </React.StrictMode>
);
