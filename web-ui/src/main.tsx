import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import './styles/tokens.css';
import './styles/base.css';
import './styles/chat.css';
import './styles/markdown.css';

const container = document.getElementById('root');
if (container === null) {
  throw new Error('缺少 #root 容器');
}

createRoot(container).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
