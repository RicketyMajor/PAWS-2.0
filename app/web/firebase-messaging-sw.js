importScripts("https://www.gstatic.com/firebasejs/9.22.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.22.0/firebase-messaging-compat.js");

// Tus credenciales (Pegadas tal cual me las diste)
const firebaseConfig = {
  apiKey: "AIzaSyDx9gdPBOwqfg2BFxeg6shpR68w9jpergg",
  authDomain: "paws-app-3187d.firebaseapp.com",
  projectId: "paws-app-3187d",
  storageBucket: "paws-app-3187d.firebasestorage.app",
  messagingSenderId: "976358685710",
  appId: "1:976358685710:web:3d0880e1c4fca1bf2fd05f",
  measurementId: "G-3KYXY1HQ2Q"
};

firebase.initializeApp(firebaseConfig);

const messaging = firebase.messaging();

// Manejador opcional para background (puedes personalizarlo luego)
messaging.onBackgroundMessage(function(payload) {
  console.log('[firebase-messaging-sw.js] Notificación en 2do plano:', payload);
  // Aquí podrías personalizar la notificación visual del navegador si quisieras
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/icons/Icon-192.png' // Asegúrate de que este ícono exista
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});