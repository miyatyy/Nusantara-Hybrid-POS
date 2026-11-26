# Nusantara Hybrid POS

**AI-Powered, Blackout-Resilient 5-Role Point of Sale & Kitchen Ecosystem for F&B SMEs**  
*Built for the **#BuildHybridAI 2026** Hackathon*

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase AI Logic](https://img.shields.io/badge/Firebase_AI_Logic-Gemini_Nano_%2B_Cloud-FFCA28?logo=firebase&logoColor=black)](https://firebase.google.com/docs/ai-logic)
[![Platform](https://img.shields.io/badge/Platform-Android_%7C_Web-15803D)](#)

---

## 1. Overview & Value Proposition

Food & Beverage (F&B) SMEs often suffer from unstable internet, missed kitchen tickets, and manual customer queue callouts. **Nusantara Hybrid POS** solves this by uniting **5 operational roles** inside a single Flutter & Firebase application that operates seamlessly **online, on local Wi-Fi during internet blackouts, and completely offline**:

1. **Cashier (POS Master)** — AI natural-language/voice ordering, real-time BOM stock checks, Cash & Midtrans QRIS/Card checkout, Z-Report shift handover, and embedded Local LAN Master Server.
2. **Kitchen Kanban (KDS)** — Real-time order pipeline (*Preparing → Cooking → Ready for Pickup → Completed*), single-print Kitchen Order Ticket (KOT) deduplication, and automated customer pickup alerts.
3. **Queue Display (TV)** — Dual-column customer waiting board (*Preparing* & *Ready for Pickup*) with **2x English Text-to-Speech (TTS)** voice announcements and responsive phone/tablet layouts.
4. **Customer Portal & Live Order Tracker** — Token-isolated real-time order progress tracker with live countdown ETA, kitchen stage stepper, and audible pickup chimes.
5. **Auto-Print & Hardware Hub** — Direct **Bluetooth Classic SPP ESC/POS thermal printing (58mm & 80mm)** for receipts & Z-Reports even while offline, plus **Wi-Fi LAN (Port 9100)** subnet auto-discovery for kitchen printers.

---

## 2. How Firebase AI Logic & Hybrid AI Are Used

Nusantara Hybrid POS uses **`package:firebase_ai/firebase_ai.dart`** and **`package:firebase_app_check/firebase_app_check.dart`** at runtime to power hybrid on-device + cloud intelligence:

- **App Check Activation (`lib/main.dart`)**:
  Immediately after `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`, `FirebaseAppCheck.instance.activate(...)` is invoked with `AndroidDebugProvider()` for Android and `ReCaptchaV3Provider` for Web so Firebase AI Logic requests authenticate cleanly during evaluation.
- **Runtime Hybrid AI Inference (`lib/services/ai_service.dart`)**:
  - **AI Smart Natural Order Box**: `AiService.parseNaturalOrder(...)` invokes `FirebaseAI.googleAI()` (with on-device Gemini Nano preference / hybrid fallback to Gemini Flash) to parse natural-language or voice-dictated orders (e.g., *"2 palm sugar latte less ice, 1 croissant, cash 100k"*) into structured menu items, quantities, modifiers, and cash tendered.
  - **AI Business Insights, Procurement & WhatsApp Promo Copywriting**: `AiService.generateBusinessInsight(...)`, `AiService.generateProcurementAdvice(...)`, and `AiService.generateSmartPromo(...)` call `FirebaseAI.googleAI()` to analyze recent sales & margins, suggest high-margin combo bundles, recommend raw-material restocks, and draft persuasive promotional messages.
  - **Graceful Offline Fallback**: When running offline or on devices without Gemini Nano runtime support, `AiService` falls back seamlessly to its deterministic local parser and analytics engine so checkout never blocks.

---

## 3. Architecture & Key Features

| Layer | Implementation | Key Files |
| :--- | :--- | :--- |
| **App Entry & App Check** | `Firebase.initializeApp`, `FirebaseAppCheck.instance.activate`, Firestore offline persistence, 5-role routing | `lib/main.dart` |
| **Hybrid AI Engine** | `FirebaseAI.googleAI()` runtime inference + on-device/offline fallback | `lib/services/ai_service.dart` |
| **Local LAN Failover** | Master HTTP server on **Port 8765** + UDP auto-discovery beacon on **Port 8766** for offline Cashier ↔ Kitchen ↔ Queue sync | `lib/services/local_kitchen_bridge.dart` |
| **Thermal Printing SDK** | Direct Bluetooth Classic SPP ESC/POS (58mm/80mm) & Wi-Fi Port 9100 KOT printing with single-print deduplication | `lib/sdk/nusantara_printer_sdk.dart` |
| **WhatsApp Automation** | Automated Fonnte / Meta WABA pickup alerts per queue number + in-app **Fonnte QR & 8-Digit Pairing Code** setup | `lib/services/whatsapp_gateway_service.dart`, `lib/screens/settings_screen.dart` |
| **Multi-Tenant Auth & Backup** | Email OTP login (`mailer`), per-tenant local & Firestore isolation (`/tenants/{tenantId}/...`), Cloud Backup/Restore, Web SaaS Admin (`?admin=true`) | `lib/services/email_auth_service.dart`, `lib/services/cloud_backup_service.dart`, `lib/screens/web_admin_portal_screen.dart` |
| **English Queue Voice (TTS)** | Native Android `TextToSpeech` (`Locale.US`) calling each ready queue number twice with clear digit spacing | `android/app/src/main/kotlin/com/miya/nusantara_hybrid_pos/MainActivity.kt`, `lib/screens/queue_display_screen.dart` |

---

## 4. Setup, Build & Judging Test Instructions

### Prerequisites
- Flutter SDK (`>=3.13.5`)
- Android device (USB debugging enabled) or Android Emulator / Chrome
- Optional runtime keys (see `.env.example`): `MIDTRANS_SERVER_KEY`, `FONNTE_TOKEN`, `RECAPTCHA_V3_SITE_KEY`

### Build & Run
```bash
# 1. Install dependencies
flutter pub get

# 2. Verify static analysis & unit tests
flutter analyze
flutter test

# 3. Run on connected Android device (or build APK)
flutter run
# Optional compile-time keys:
# flutter run --dart-define=MIDTRANS_SERVER_KEY=your_sandbox_key --dart-define=FONNTE_TOKEN=your_fonnte_token
```

### Judging Test Guide
1. **Sign In or Open Queue Display**:
   - Sign in via **Email OTP** (preview OTP code is displayed if Gmail App Password is not configured), or tap **Open Queue Display (No Login Required)** to jump straight to the customer waiting board.
2. **Switch Between All 5 Roles via the Sidebar**:
   - Open the top-left **Navigation Drawer (☰)** to switch seamlessly between:
     1. **Cashier (POS Master)**
     2. **Queue Display (TV)**
     3. **Kitchen Kanban (Auto-Print)**
     4. **Customer (Order Tracker)**
     5. **Auto-Print & Hardware Hub**
   - Plus **Menu & Bundles**, **Procurement**, **Analytics & AI**, and **Store & POS Settings**.
3. **Test Hybrid AI Ordering**:
   - On the **Cashier** screen, tap a quick sample prompt or type/speak an order in the **Smart AI Natural Order Box** and tap **Process AI Order** to watch items and cash tendered populate automatically.
4. **Test Airplane Mode Blackout Sync & Offline Printing**:
   - Enable **Airplane Mode** on the device, place an order in **Cashier**, and complete **Cash** checkout.
   - The transaction records locally with BOM stock deduction, generates a **Bluetooth ESC/POS thermal receipt**, updates **Kitchen Kanban** and **Queue Display** immediately, and auto-syncs to Cloud Firestore once connectivity returns.
