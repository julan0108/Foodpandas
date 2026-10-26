const { initializeApp } = require('firebase-admin/app');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { timingSafeEqual, randomUUID } = require('node:crypto');

initializeApp();

const db = getFirestore();
const xenditSecretKey = defineSecret('XENDIT_SECRET_KEY');
const xenditCallbackToken = defineSecret('XENDIT_CALLBACK_TOKEN');
const demoMenu = {
  'demo-tita-luz': {
    name: 'Demo Tita Luz’s Kusina',
    deliveryFee: 49,
    items: {
      adobo: { name: 'Chicken Adobo', price: 165 },
      sinigang: { name: 'Sinigang na Baboy', price: 195 },
      sisig: { name: 'Sizzling Pork Sisig', price: 185 },
    },
  },
  'demo-mang-tonyo': {
    name: 'Demo Mang Tonyo’s Ihaw-Ihaw',
    deliveryFee: 49,
    items: {
      bbq: { name: 'Pork BBQ Meal', price: 145 },
      liempo: { name: 'Inihaw na Liempo', price: 210 },
      isaw: { name: 'Isaw & Betamax Combo', price: 99 },
    },
  },
  'demo-ate-mels': {
    name: 'Demo Ate Mel’s Meryenda',
    deliveryFee: 49,
    items: {
      'halo-halo': { name: 'Special Halo-Halo', price: 120 },
      turon: { name: 'Banana Turon (3 pcs)', price: 75 },
      pancit: { name: 'Pancit Palabok', price: 135 },
    },
  },
  'demo-lola-bebang': {
    name: 'Demo Lola Bebang’s Panaderya',
    deliveryFee: 49,
    items: {
      pandesal: { name: 'Pandesal (6 pcs)', price: 45 },
      ensaymada: { name: 'Classic Ensaymada', price: 65 },
      'ube-cheese': { name: 'Ube Cheese Pandesal (4 pcs)', price: 88 },
    },
  },
};

exports.createOrder = onCall(
  { secrets: [xenditSecretKey] },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to place an order.');
    if (request.auth.token.email_verified !== true) {
      throw new HttpsError('permission-denied', 'Verify your email before ordering.');
    }
    const {
      customerName, phone, deliveryAddress, items,
      paymentMethod = 'cash_on_delivery',
      demoOrder = false,
    } = request.data || {};
    if (typeof customerName !== 'string' || customerName.trim().length < 2 || customerName.length > 100 ||
        typeof phone !== 'string' || phone.trim().length < 7 || phone.length > 30 ||
        typeof deliveryAddress !== 'string' || !deliveryAddress.trim() || deliveryAddress.length > 500 ||
        !['cash_on_delivery', 'ewallet', 'card', 'xendit'].includes(paymentMethod) ||
        typeof demoOrder !== 'boolean' ||
        !Array.isArray(items) || items.length < 1 || items.length > 50) {
      throw new HttpsError('invalid-argument', 'Check the customer, address and cart details.');
    }
    if (demoOrder && paymentMethod !== 'ewallet') {
      throw new HttpsError('failed-precondition', 'Demo checkout supports Xendit e-wallet sandbox payments only.');
    }

    const grouped = new Map();
    for (const item of items) {
      if (!item || typeof item.restaurantId !== 'string' || !item.restaurantId.trim() ||
          typeof item.id !== 'string' || !item.id.trim() ||
          !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 99) {
        throw new HttpsError('invalid-argument', 'One or more cart items are invalid.');
      }
      const key = `${item.restaurantId}/${item.id}`;
      const row = grouped.get(key) || { restaurantId: item.restaurantId, id: item.id, quantity: 0 };
      row.quantity += item.quantity;
      if (row.quantity > 99) throw new HttpsError('invalid-argument', 'Item quantity is too high.');
      grouped.set(key, row);
    }

    const branchCache = new Map();
    const snapshots = [];
    let subtotal = 0;
    let deliveryFee = 0;
    const checkedRestaurants = new Set();
    for (const item of grouped.values()) {
      if (demoOrder) {
        const demoRestaurant = demoMenu[item.restaurantId];
        const entry = demoRestaurant?.items[item.id];
        if (!demoRestaurant || !entry) {
          throw new HttpsError('invalid-argument', 'A demo menu item is not available.');
        }
        subtotal += entry.price * item.quantity;
        if (!checkedRestaurants.has(item.restaurantId)) {
          deliveryFee += demoRestaurant.deliveryFee;
          checkedRestaurants.add(item.restaurantId);
        }
        snapshots.push({
          id: item.id,
          restaurantId: item.restaurantId,
          name: entry.name,
          restaurantName: demoRestaurant.name,
          branchName: 'Sandbox checkout',
          quantity: item.quantity,
          unitPrice: entry.price,
          imageUrl: '',
          category: 'Demo food',
        });
        continue;
      }
      let branch = branchCache.get(item.restaurantId);
      if (!branch) {
        const branchSnapshot = await db.collection('restaurants').doc(item.restaurantId).get();
        branch = branchSnapshot.exists ? branchSnapshot.data() : null;
        const branchFee = Number(branch?.deliveryFee ?? branch?.delivery_fee);
        if (!branch || branch.verified !== true || branch.active !== true ||
            !Number.isFinite(branchFee) || branchFee < 0) {
          throw new HttpsError('failed-precondition', 'This restaurant branch is unavailable.');
        }
        branchCache.set(item.restaurantId, branch);
        const areas = Array.isArray(branch.deliveryAreas)
          ? branch.deliveryAreas
          : Array.isArray(branch.delivery_areas) ? branch.delivery_areas : [];
        const address = deliveryAddress.toLocaleLowerCase();
        if (areas.length === 0 ||
            !areas.some((area) => typeof area === 'string' && area.trim() && address.includes(area.toLocaleLowerCase()))) {
          throw new HttpsError('failed-precondition', 'This branch does not serve the delivery address. Check the address or choose another restaurant.');
        }
      }
      const menu = Array.isArray(branch.menu) ? branch.menu : [];
      const entry = menu.find((row) => row && row.id === item.id);
      if (!entry || typeof entry.name !== 'string' ||
          !Number.isFinite(Number(entry.price)) || Number(entry.price) <= 0) {
        throw new HttpsError('failed-precondition', 'A menu item is no longer available.');
      }
      const price = Number(entry.price);
      subtotal += price * item.quantity;
      if (!checkedRestaurants.has(item.restaurantId)) {
        deliveryFee += Number(branch.deliveryFee ?? branch.delivery_fee);
        checkedRestaurants.add(item.restaurantId);
      }
      snapshots.push({
        id: item.id,
        restaurantId: item.restaurantId,
        name: entry.name,
        restaurantName: branch.name,
        branchName: branch.branchName || branch.branch_name || '',
        quantity: item.quantity,
        unitPrice: price,
        imageUrl: entry.imageUrl || '',
        category: entry.category || '',
      });
    }

    const orderId = randomUUID();
    const orderNumber = `${demoOrder ? 'DEMO' : 'FP'}-${orderId.substring(0, 8).toUpperCase()}`;
    const onlinePayment = paymentMethod !== 'cash_on_delivery';
    const xenditKey = onlinePayment ? configuredXenditSecretKey() : null;
    if (demoOrder && (!xenditKey || !xenditKey.startsWith('xnd_development-'))) {
      throw new HttpsError('failed-precondition', 'Demo payments require a Xendit development secret key.');
    }
    const externalId = onlinePayment ? `foodpandas_${orderId}` : null;
    const order = {
      orderNumber,
      userId: request.auth.uid,
      customerName: customerName.trim(),
      phone: phone.trim(),
      items: snapshots,
      subtotal,
      deliveryFee,
      total: subtotal + deliveryFee,
      deliveryAddress: deliveryAddress.trim(),
      status: onlinePayment ? 'pending_payment' : 'placed',
      paymentStatus: 'pending',
      paymentMethod,
      ...(demoOrder ? { demoOrder: true } : {}),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      ...(externalId ? { xenditExternalId: externalId } : {}),
    };
    await db.collection('orders').doc(orderId).create(order);

    if (!onlinePayment) return { orderId, orderNumber };

    let response;
    let result;
    try {
      const invoicePayload = {
        external_id: externalId,
        amount: order.total,
        currency: 'PHP',
        description: `Food Pandas order ${orderNumber}`,
        invoice_duration: 86400,
        ...(paymentMethod === 'ewallet' ? { payment_methods: ['GCASH', 'GRABPAY'] } : {}),
        customer: {
          given_names: customerName.trim(),
          mobile_number: phone.trim(),
        },
        items: [
          ...snapshots.map((item) => ({
            name: item.name,
            quantity: item.quantity,
            price: item.unitPrice,
            category: item.category || 'Food',
          })),
          ...(deliveryFee > 0
            ? [{ name: 'Delivery fee', quantity: 1, price: deliveryFee, category: 'Delivery' }]
            : []),
        ],
      };
      response = await fetch('https://api.xendit.co/v2/invoices', {
        method: 'POST',
        signal: AbortSignal.timeout(15000),
        headers: {
          Authorization: `Basic ${Buffer.from(`${xenditKey}:`).toString('base64')}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(invoicePayload),
      });
      result = await response.json().catch(() => null);
    } catch (error) {
      console.error('Xendit invoice request failed:', error.message);
      await markPaymentFailed(orderId);
      throw new HttpsError(
        'unavailable',
        'Could not start online payment. The failed order was saved in My orders.',
        { orderId, orderNumber },
      );
    }
    if (!response.ok || typeof result?.id !== 'string' ||
        typeof result?.invoice_url !== 'string') {
      console.error('Xendit rejected invoice creation:', response.status, result?.message);
      await markPaymentFailed(orderId);
      throw new HttpsError(
        'unavailable',
        'Xendit could not start this payment. The failed order was saved in My orders.',
        { orderId, orderNumber },
      );
    }
    try {
      await db.collection('orders').doc(orderId).update({
        xenditInvoiceId: result.id,
        invoiceUrl: result.invoice_url,
        updatedAt: FieldValue.serverTimestamp(),
      });
    } catch (error) {
      console.error('Could not save Xendit invoice to Firestore order:', error.message);
      await markPaymentFailed(orderId);
      throw new HttpsError(
        'unavailable',
        'The payment link could not be saved. The order was marked as failed; check My orders before retrying.',
        { orderId, orderNumber },
      );
    }
    return { orderId, orderNumber, invoiceUrl: result.invoice_url };
  },
);

async function markPaymentFailed(orderId) {
  const orderRef = db.collection('orders').doc(orderId);
  await db.runTransaction(async (transaction) => {
    const order = await transaction.get(orderRef);
    if (order.exists && order.get('paymentStatus') === 'pending') {
      transaction.update(orderRef, {
        paymentStatus: 'failed',
        status: 'cancelled',
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });
}

function configuredXenditSecretKey() {
  try {
    const secretKey = xenditSecretKey.value();
    if (secretKey && !secretKey.startsWith('xnd_public_')) return secretKey;
    if (secretKey) {
      throw new HttpsError(
        'failed-precondition',
        'XENDIT_SECRET_KEY must contain a server-side secret key, not a public key.',
      );
    }
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error('Xendit secret key is unavailable:', error.message);
  }
  throw new HttpsError(
    'failed-precondition',
    'Xendit payments are not configured. Set XENDIT_SECRET_KEY and deploy the Cloud Functions.',
  );
}

exports.xenditWebhook = onRequest(
  { secrets: [xenditCallbackToken] },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).send('Method not allowed');
      return;
    }
    if (!safeTokenEquals(
      request.get('x-callback-token') || '',
      xenditCallbackToken.value(),
    )) {
      response.status(401).send('Unauthorized');
      return;
    }
    const { external_id: externalId, id: invoiceId, status, amount, currency } =
      request.body || {};
    const match = typeof externalId === 'string'
      ? /^foodpandas_([0-9a-f-]{36})$/i.exec(externalId)
      : null;
    if (!match || typeof invoiceId !== 'string' ||
        !['PAID', 'SETTLED', 'EXPIRED', 'FAILED'].includes(status) ||
        typeof amount !== 'number' || currency !== 'PHP') {
      response.status(400).send('Invalid invoice callback');
      return;
    }

    const orderRef = db.collection('orders').doc(match[1]);
    const orderSnapshot = await orderRef.get();
    const order = orderSnapshot.data();
    if (!orderSnapshot.exists || !order) {
      response.status(404).send('Order not found');
      return;
    }
    if (order.xenditExternalId !== externalId ||
        order.xenditInvoiceId !== invoiceId ||
        !['ewallet', 'card', 'xendit'].includes(order.paymentMethod) ||
        Number(order.total) !== amount) {
      response.status(400).send('Invoice does not match order');
      return;
    }
    if (order.paymentStatus !== 'pending') {
      response.status(200).send('OK');
      return;
    }
    const paymentStatus = ['PAID', 'SETTLED'].includes(status) ? 'paid' : 'failed';
    await db.runTransaction(async (transaction) => {
      const current = await transaction.get(orderRef);
      if (current.exists && current.get('paymentStatus') === 'pending') {
        transaction.update(orderRef, {
          paymentStatus,
          status: paymentStatus === 'paid' ? 'placed' : 'cancelled',
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    });
    response.status(200).send('OK');
  },
);

exports.notifyOrderUpdate = onDocumentUpdated('orders/{orderId}', async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.status === after.status &&
      before.paymentStatus === after.paymentStatus) return;

  const paymentChanged = before.paymentStatus !== after.paymentStatus;
  const notification = {
    title: paymentChanged ? 'Payment update' : 'Order update',
    body: `Order ${after.orderNumber}: ${paymentChanged
      ? after.paymentStatus
      : after.status}.`,
    type: paymentChanged ? 'payment' : 'order',
    orderId: event.params.orderId,
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  };
  const userRef = db.collection('users').doc(after.userId);
  await userRef.collection('notifications').add(notification);
  const deviceSnapshot = await userRef.collection('devices').get();
  const tokens = deviceSnapshot.docs
    .map((device) => device.get('token'))
    .filter((token) => typeof token === 'string' && token.length > 0);
  for (let start = 0; start < tokens.length; start += 500) {
    await getMessaging().sendEachForMulticast({
      tokens: tokens.slice(start, start + 500),
      notification: { title: notification.title, body: notification.body },
      data: {
        type: notification.type,
        orderId: event.params.orderId,
      },
    });
  }
});

function safeTokenEquals(suppliedToken, expectedToken) {
  const supplied = Buffer.from(suppliedToken);
  const expected = Buffer.from(expectedToken);
  return expected.length > 0 &&
    supplied.length === expected.length &&
    timingSafeEqual(supplied, expected);
}
