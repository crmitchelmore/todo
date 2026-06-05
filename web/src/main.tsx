import React, { useEffect, useState } from 'react';
import ReactDOM from 'react-dom/client';
import { PowerSyncContext } from '@powersync/react';
import { db, prepareForActiveUser } from './powersync/db';
import { consumeOAuthSessionFromUrl, isAuthenticated, onAuthChange } from './lib/auth';
import { applyAppearance, getAppearance } from './lib/preferences';
import { SignIn } from './components/SignIn';
import App from './App';
import './styles.css';

applyAppearance(getAppearance());

function Root() {
  const [oauthResult] = useState(() => consumeOAuthSessionFromUrl());
  const [authed, setAuthed] = useState(isAuthenticated());

  useEffect(() => onAuthChange(() => setAuthed(isAuthenticated())), []);

  useEffect(() => {
    if (authed) {
      // Resets only when the account actually changed, otherwise keeps pending offline writes.
      void prepareForActiveUser();
    }
  }, [authed]);

  if (!authed) {
    return <SignIn initialError={oauthResult.error} onSignedIn={() => setAuthed(true)} />;
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
