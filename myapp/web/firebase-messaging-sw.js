/* Firebase web push requires HTTPS and a Web Push certificate (VAPID key). */
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDoWmnYep0063Dy9bB1GSFDxhc3-SDbfY4',
  authDomain: 'foodpandas-f2e83.firebaseapp.com',
  projectId: 'foodpandas-f2e83',
  storageBucket: 'foodpandas-f2e83.firebasestorage.app',
  messagingSenderId: '1083814338526',
  appId: '1:1083814338526:web:bbcaefad7d64417fe9474f',
  measurementId: 'G-KHRF3GVCMY',
});

const messaging = firebase.messaging();
