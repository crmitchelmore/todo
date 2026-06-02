import React from 'react';
import ReactDOM from 'react-dom/client';
import { PowerSyncContext } from '@powersync/react';
import { db, initPowerSync } from './powersync/db';
import App from './App';
import './styles.css';

void initPowerSync();

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <PowerSyncContext.Provider value={db}>
      <App />
    </PowerSyncContext.Provider>
  </React.StrictMode>
);
