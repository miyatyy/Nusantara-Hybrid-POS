# Nusantara Hybrid POS

**AI-Powered, Offline-First F&B Point of Sale & Multi-Role Kitchen Ecosystem**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Firestore%20%7C%20AI%20%7C%20Hosting-FFCA28?logo=firebase&logoColor=black)](https://firebase.google.com)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Web-15803D)](#)

Nusantara Hybrid POS is a complete, production-ready restaurant & café operations platform built with Flutter and Firebase. It unifies **Cashier POS, Kitchen Display (KDS), Queue TV Display, Customer Order Tracker, and Hardware Hub** into a single resilient system engineered to keep running seamlessly both **online** and **offline**.

---

## Key Highlights

### 1. 5-Role Unified Ecosystem
- **POS Cashier (Master)**: Fast cart & checkout, Dine-In / Take-Away modes, split payment support (Cash, Midtrans QRIS & Card), shift handover Z-Reports, and local LAN master server.
- **Queue Display (TV)**: Real-time dual-column customer waiting board (*Preparing* & *Ready for Pickup*) with audible & visual callout announcements.
- **Kitchen Kanban (KDS)**: Real-time order pipeline (*Preparing → Cooking → Ready for Pickup → Completed*), auto-print kitchen tickets (KOT) once per order, and 1-tap customer pickup alerts.
- **Customer Portal & Live Order Tracker**: Token-secured real-time order progress tracker with countdown ETA, kitchen stage stepper, and automatic ready chimes.
- **Auto-Print & Hardware Hub**: Direct **Bluetooth ESC/POS thermal printing (58mm & 80mm)** for receipts & Z-Reports even while offline, plus **Wi-Fi LAN (Port 9100)** subnet auto-discovery for kitchen printers.

### 2. Hybrid AI Engine
- **Smart AI Natural Order Box**: Type or dictate natural-language orders (e.g., *"2 palm sugar latte less ice, 1 croissant, cash 100k"*) with automatic item matching, quantity extraction, modifiers, and cash parsing.
- **Real-Time AI Upsell & Business Insights**: Gemini-powered upsell recommendations, procurement advisor, and persuasive WhatsApp promo copywriting generator.
- **On-Device & Cloud Resilience**: Instant local parsing when offline, paired with cloud Gemini intelligence when connected.

### 3. Automated WhatsApp Notifications & Channel Pairing
- **Automated Kitchen Reminders**: Automatically dispatches WhatsApp messages via **Fonnte** or **Meta WABA** with the customer's exact **Queue Number** when their order is cooking or ready for pickup.
- **In-App Channel Pairing**: Built-in **Scan QR Code** and **8-Digit Pairing Code** setup directly inside **Settings** for quick Fonnte device linking, plus an offline message outbox that auto-sends upon reconnection.

### 4. Multi-Tenant Email OTP Security & Local-First Backup
- **Email OTP Authentication**: Secure 1-time Email + 6-digit OTP sign-in with automatic per-account local data isolation and tenant-scoped Firestore collections (`/tenants/{tenantId}/...`).
- **Local-First + Cloud Backup**: Menus, raw material BOM recipes, customer directory, and orders are stored safely on-device for zero-downtime operation and can be backed up or restored with Firebase Cloud anytime.
- **Web SaaS Admin Portal**: Dedicated web management portal (`?admin=true`) for Super Admins to monitor store accounts, license plans, and database summaries.

### 5. Inventory, BOM & Financial Analytics
- **Bill of Materials (BOM)**: Automatic raw material stock deduction per sold item, real-time *Ready / Sold Out* availability calculation, and low-stock threshold alerts.
- **Financial & Shift Reporting**: Gross sales, expenses, net profit & margin charts, Cash Drawer reconciliation, native thermal Z-Reports, and PDF export.

---

## Tech Stack

- **Frontend**: Flutter & Dart (Material 3, Royal Blue & Golden Amber theme)
- **Cloud & AI**: Firebase Core, Cloud Firestore, Firebase App Check, Firebase Hosting, Gemini AI
- **Hardware & Printing**: Custom Native ESC/POS SDK (Bluetooth Classic SPP & Wi-Fi Port 9100), PDF Generation (`pdf`, `printing`)
- **Messaging & Auth**: Fonnte WhatsApp API, Meta WABA Cloud API, Gmail SMTP OTP (`mailer`)
- **Payments**: Cash (Offline-ready) & Midtrans Sandbox (QRIS / Card)

---

## Getting Started

### Prerequisites
- Flutter SDK (`>=3.13.5`)
- Android SDK / connected Android device or Chrome for Web
- Firebase project configured in `lib/firebase_options.dart`

### Installation & Run
```bash
# 1. Install dependencies
flutter pub get

# 2. Run static analysis & unit tests
flutter analyze
flutter test

# 3. Run on Android or build APK
flutter run
# or
flutter build apk --release
```

---

## Project Structure

```text
lib/
├── main.dart                  # App entry point, role routing & Web Admin portal entry
├── models/                    # MenuItem, OrderItem, PosTransaction, RawMaterial, ZReportData
├── screens/                   # Cashier, Kitchen KDS, Queue TV, Customer Tracker, Menu, Inventory, Analytics, Settings, Web Admin
├── services/                  # AI, Email OTP, Firestore, Cloud Backup, WhatsApp Gateway, Local LAN Bridge, Shift & Settings
├── sdk/                       # Custom ESC/POS Bluetooth & Wi-Fi (Port 9100) Thermal Printer SDK
├── utils/                     # Z-Report PDF exporter
└── widgets/                   # Navigation Drawer, Thermal Receipt Dialog, Midtrans Dialog, AI Order Box, Charts
```

---

## License

Built for international innovation competition — **Nusantara Hybrid POS**.
