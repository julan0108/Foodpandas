# Food-Pandas

A responsive Flutter ordering experience for neighborhood Filipino food stalls.
Built-in vendor/menu content is sample data; real orders and customer data for
verified Firebase restaurants are managed through trusted Firebase Cloud Functions.

## Project structure

```text
myapp/
├── lib/
│   ├── main.dart             # App shell, ordering UI and verified-checkout gate
│   ├── firebase_options.dart # FlutterFire platform configuration
│   ├── screens/
│   │   └── auth/
│   │       └── auth_pages.dart
│   └── services/
│       └── auth_service.dart
├── firestore.rules           # Firebase customer and restaurant access rules
├── test/
│   └── widget_test.dart      # Ordering and verified-checkout tests
├── web/
│   ├── index.html            # Browser title and app metadata
│   └── manifest.json
├── pubspec.yaml
└── README.md
```

## Run in a browser

Install the [Flutter SDK](https://docs.flutter.dev/get-started/install) with web
support and a current Chrome or Edge browser. From this project folder:

```bash
flutter pub get
flutter run -d chrome
```

To create a static web release:

```bash
flutter build web --release
```

The generated site is in `build/web/`. Deploy that folder to a static host. For
hosting under a subpath, pass the matching `--base-href` to `flutter build web`.

## Included screens and flow

- Home landing page with local-stall highlights
- Vendor directory with search and food-category filters
- Vendor menu with add-to-cart actions
- Cart with editable item quantities and delivery estimate
- Validated checkout with a manually entered delivery address, cash on delivery,
  and Xendit GCash/GrabPay/card payments
- Order confirmation and live progress timeline for verified restaurant orders

The cart and sample-preview orders exist only in app memory and reset on
refresh. Food photos load from Unsplash; colored food-themed placeholders
appear if a photo is unavailable.

## Firebase setup (Phase 2)

Phase 2 adds Firebase email/password authentication and Firebase
Authentication's built-in email verification link. Users can browse without
signing in; the app routes the checkout UI only for authenticated,
email-verified accounts. Verification emails are sent directly by Firebase
Authentication, so this flow does not require Cloud Functions, Gmail SMTP
credentials, or the pay-as-you-go Firebase plan. This is not a server-side
order authorization by itself; the `createOrder` Cloud Function also checks
authentication and email verification before saving a real order.

### Configure Phase 2

1. In Firebase Console, enable **Authentication → Email/Password**. Firebase
   sends the built-in verification link to the address used to register. Check
   Firebase Authentication's email templates to customize the message.
2. Configure the missing iOS app options and refresh generated FlutterFire
   configuration (Android and Web are already present):

   ```bash
   flutterfire configure --project=foodpandas-f2e83 --platforms=android,ios,web
   ```

   Keep the generated `GoogleService-Info.plist` in the iOS Runner configuration
   as instructed by FlutterFire. Do not manually fabricate platform options.
3. Build and run from the project root:

   ```bash
   flutter pub get
   flutter run -d chrome
   ```

   To run the Flutter web release build, use `flutter build web --release`.
4. For iOS, finish the generated Firebase setup before running on an iOS device.
   The generated options currently do not include iOS, so `main()` will clearly
   fail initialization there until FlutterFire is configured.

The verification screen sends a link when first opened (and supports resending)
and lets the user refresh their Firebase Authentication status after opening
the link. No numeric code is used.

## Firebase database, restaurant coverage, and notifications

Firebase Authentication provides user identity and Cloud Firestore stores
customer profiles, verified restaurant/menu catalog, orders, notifications,
and device tokens. The `firestore.rules` file restricts customers to their own
profiles, orders, notifications, and device tokens. Orders are created and
priced by the trusted Firebase Cloud Function; the client cannot create or
change order records. Customer GPS coordinates are not requested or saved;
delivery addresses are entered manually.

The in-app Notifications page and **My orders** use Firestore live snapshots.
The `notifyOrderUpdate` Cloud Function creates an in-app notification and sends
push notifications when an order's payment or delivery status changes.

The original built-in stalls and menus are preview content. Their checkout
flow remains available to demonstrate the UI, but it is explicitly labeled
and never creates a Firebase order or notifies a restaurant. Only a branch
loaded from the verified Firebase restaurant catalog is saved as a real order.
Checkout opens an order-details dialog; for saved orders it shows the Firestore
order and live payment/status details. **My orders** lists those saved orders.
If it is empty, sample preview checkouts are not included.

The Restaurants page reads verified, active `restaurants` documents without
requesting the customer's GPS location. Customers enter a delivery address at
checkout. Each branch must include its official address, coordinates, menu and
current prices, verification source, delivery radius, and verified
`deliveryAreas`. Do not mark a branch verified until those details have been
checked with the restaurant or its official ordering channel. Add actual
Jollibee, McDonald's, and local branch/menu records for the target city; this
repository does not invent branch availability or menu prices. No restaurant
will appear until verified documents have been added.

Orders are submitted through the `createOrder` callable Cloud Function. It
checks the authenticated, email-verified user, reloads each active verified
branch and menu item, validates the manually entered delivery address against
the branch's configured `deliveryAreas`, and computes prices and fees from
Firestore. Client writes to `orders` are denied by Firestore rules. Configure
verified neighborhood or service-area names in `deliveryAreas`; orders cannot
be placed for branches without configured service areas.

Restaurant document shape (create documents in the Firestore `restaurants`
collection using the Firebase Console or a trusted administrative script):

```json
{
  "name": "Jollibee",
  "branchName": "<verified branch name>",
  "address": "<verified delivery address>",
  "category": "Fast food",
  "imageUrl": "<approved image URL>",
  "latitude": 0,
  "longitude": 0,
  "deliveryRadiusKm": 0,
  "deliveryAreas": ["<verified service area>"],
  "deliveryFee": 0,
  "verified": false,
  "active": false,
  "verificationSource": "<official source and date>",
  "menu": [
    {
      "id": "<stable-item-id>",
      "name": "<official item name>",
      "description": "<menu description>",
      "category": "<food category>",
      "price": 0,
      "imageUrl": "<approved image URL>"
    }
  ]
}
```

Client writes to `restaurants` are denied by Firestore rules. The `verified`
and `active` fields must remain false until the branch and its service area
are confirmed. The address field remains editable at checkout if the customer
needs to change it. Branch coordinates remain part of the trusted catalog.

Create the Cloud Firestore database in the Firebase Console if it does not
already exist, then deploy the included access rules and indexes from the
project root:

```powershell
firebase deploy --only firestore:rules,firestore:indexes --project foodpandas-f2e83
```

### Configure Firebase and Maps

1. Install the required Flutter packages and configure the missing iOS Firebase
   app using the project owner account:

   ```powershell
   flutter pub get
   flutterfire configure --project=foodpandas-f2e83 --platforms=android,ios,web
   ```

   `lib/firebase_options.dart` currently has Android and Web entries only.
   The command must register the real iOS bundle ID and generate its options;
   do not fabricate an iOS app ID or `GoogleService-Info.plist`.

2. Create a Google Maps Platform API key, enable Maps SDK for Android, Maps
   SDK for iOS, and Maps JavaScript API, and apply platform restrictions. The
   Maps Flutter package requires a Google Cloud billing account and an API key.
   Add the key to `android/local.properties`:

   ```properties
   MAPS_API_KEY=YOUR_RESTRICTED_ANDROID_KEY
   ```

   Copy `ios/Flutter/Maps.xcconfig.example` to the ignored
   `ios/Flutter/Maps.xcconfig` file and set its `MAPS_API_KEY`. In `web/index.html`,
   replace `YOUR_GOOGLE_MAPS_API_KEY` with a key restricted to the deployed web
   origin. Use separate keys for Android, iOS and Web.

3. In Xcode, enable the Runner target's **Push Notifications** capability and
   **Background Modes → Remote notifications**. In Firebase Console, enable
   Cloud Messaging and upload an APNs authentication key for iOS. For web push,
   create a Web Push certificate and provide its
   public VAPID key when building/running the web app:

   ```powershell
   flutter run -d chrome --dart-define=FCM_VAPID_KEY=YOUR_PUBLIC_VAPID_KEY
   flutter build web --release --dart-define=FCM_VAPID_KEY=YOUR_PUBLIC_VAPID_KEY
   ```

   Web push requires an HTTPS origin and the included
   `web/firebase-messaging-sw.js` service worker. Without push permission or
   platform credentials, in-app Firebase notifications remain available.

4. Install Firebase CLI, sign in, and deploy the Cloud Functions:

   Before deploying Functions, configure the Firebase and Xendit settings in
   the sections below. Use a project-specific ignored `.env.foodpandas-f2e83`
   file or the Firebase CLI prompt for any configured Firebase function values.

   ```powershell
   firebase login
   cd functions
   npm install
   cd ..
   firebase deploy --only functions --project foodpandas-f2e83
   ```

   Cloud Functions deployment requires the Firebase project to use the Blaze
   plan. Order-status updates are made by a trusted restaurant/admin backend
   using `placed`, `preparing`, `ready_for_pickup`, `out_for_delivery`,
   `delivered`, or `cancelled`; e-wallet orders also use `pending_payment`
   until payment completes. Payment statuses are `pending`, `paid`, `failed`,
   or `refunded`; e-wallet status is updated by the verified Xendit webhook.

### Xendit online checkout

Verified restaurant checkout supports cash on delivery, Xendit e-wallets,
credit/debit cards, and an **All available online methods** option. E-wallet
checkout restricts Xendit's hosted invoice to GCash and GrabPay.
Credit/debit card and **All available online methods** checkout leave Xendit's
`payment_methods` filter unset so the hosted invoice offers the corresponding
channels enabled for the merchant account.
Sample/demo orders remain non-fulfillable. E-wallet is available for sample
checkout only with a Xendit development secret key; the server prices those
items from its own fixed demo catalog, saves a `DEMO-` order for webhook status,
and opens Xendit's sandbox checkout. The server rejects demo payments if a
production key is configured. Card and all-method checkout remain disabled for
sample items. The Xendit secret key is used only by the `createOrder` Cloud
Function; never put it in Flutter code, app build arguments, or source control.

For E-wallet checkout, select **E-wallet** and tap **Place my order**. The
server creates an invoice for that order and the app opens its hosted Xendit
checkout page (in the current browser tab on web to avoid popup blocking).
The `xnd_public_...` key is a client-side publishable key and cannot authorize
server-side invoice creation; configure the Xendit secret key using the
Firebase Functions secret command below instead.

1. Enable the payment channels you want in the Xendit dashboard and use a test
   key while validating in the Xendit test environment. Enable GCash and/or
   GrabPay for the e-wallet checkout option. Xendit presents the enabled wallet
   choices on the hosted invoice after the customer places an e-wallet order.
2. Set both Firebase function secrets from the project root. Firebase CLI will
   prompt for each value; use the callback verification token from the Xendit
   dashboard:

   ```powershell
   firebase functions:secrets:set XENDIT_SECRET_KEY --project foodpandas-f2e83
   firebase functions:secrets:set XENDIT_CALLBACK_TOKEN --project foodpandas-f2e83
   firebase deploy --only functions --project foodpandas-f2e83
   ```

3. Copy the deployed `xenditWebhook` HTTPS URL from the Firebase CLI output into
   Xendit's invoice callback/webhook configuration. Configure the callback
   verification token there to match `XENDIT_CALLBACK_TOKEN`.
4. At verified-restaurant checkout, choose **E-wallet**, **Credit or debit
   card**, or **All available online methods**. The server computes the total
   from the verified restaurant catalog and saves the full order to Firestore
   before requesting the invoice. At sample checkout, choose **E-wallet** to
   open a sandbox invoice priced from the server-side demo catalog; it is not a
   real order and no restaurant will fulfill it. The server rejects sample
   payments unless `XENDIT_SECRET_KEY` is a development key. On successful
   invoice creation, the Xendit invoice ID and payment link are saved onto the
   order. **Continue to payment** opens hosted checkout from order details or
   order history. The order remains pending until the webhook's token, invoice
   ID, order ID, currency, and amount are verified. If invoice creation fails,
   the saved order is marked failed/cancelled and the callable returns its
   order number so it remains visible in **My orders**. Xendit `FAILED` or
   `EXPIRED` callbacks also mark payment failed and cancel the unpaid order.
   The customer receives a notification when payment or delivery status
   changes. Do not manually set an online order to paid.

Use separate test and live credentials, and do not enable live payments until
the merchant account and callback configuration have been verified.

5. Run the widget tests and build the supported targets after configuring the
   SDKs and keys:

   ```powershell
   flutter test
   flutter build apk --release
   flutter build web --release --dart-define=FCM_VAPID_KEY=YOUR_PUBLIC_VAPID_KEY
   ```

   Build iOS on macOS after running `flutterfire configure` and installing the
   Apple signing/APNs setup.

Customer profile details are stored in each customer's Firestore
`users/{userId}` document. The profile screen loads and saves email, display
name, mobile number, delivery address, and the last update timestamp. Firestore
rules limit customers to their own profile. Real orders and online payments
require verified Firebase restaurant records and deployed, configured Firebase
Functions. Maps, rider tracking, and App Check still require production setup;
do not enable live payments until the merchant and all backend configuration
have been verified.
