# Rayzon Solar - Employee Travel & Kilometer Log

A modern, ultra-polished Flutter mobile application for Rayzon Solar employees to log travel journeys and meter readings. Built with offline-first architecture, automatic sync, and role-based access control.

## 🌟 Features

### 🔐 Authentication & Roles
- **Secure Login**: Email/password authentication with Firebase Auth
- **Forgot Password**: Password reset functionality
- **Role-Based Access**: Admin and Normal User roles with different permissions
- **User Management**: Admins can create and manage user accounts

### 📱 User Experience
- **Modern UI**: Custom white-themed, ultra-premium design with brand color #095763
- **Smooth Animations**: Micro-interactions and transitions throughout the app
- **Offline-First**: Works seamlessly without internet connection
- **Auto-Sync**: Automatic background synchronization when connectivity is restored

### 🚗 Travel Request Management
- **Live GPS tracking**: Continuous background sampling during travel legs; route points sync to Firestore under `travel_requests/{id}/route_points/{pointId}`. Ensure your Firestore rules allow authenticated users to create/read those subcollection documents.
- **Create Requests**: Users can create travel requests with location details
- **Camera Integration**: GPS-stamped meter image capture with overlay
- **Status Tracking**: Start Missing → End Missing → Completed workflow
- **Request History**: View all past requests with filtering options

### 👨‍💼 Admin Dashboard
- **Statistics**: Today/Week/Month travel request counts
- **User Management**: Create, view, and manage user accounts
- **Request Overview**: View all employee travel requests
- **Data Export**: CSV export functionality for reporting

### 📸 Advanced Camera Features
- **GPS Overlay**: Automatically adds location, timestamp, and address to images
- **Dual Capture**: Separate start and end meter readings
- **Image Processing**: Custom overlay with Rayzon branding
- **Metadata Storage**: Complete EXIF and location data preservation

### 🔄 Offline & Sync
- **Local Storage**: Isar database for offline data persistence
- **Queue Management**: Automatic retry mechanism for failed syncs
- **Background Sync**: Periodic synchronization using WorkManager
- **Conflict Resolution**: Last-write-wins with user notifications

## 🏗️ Architecture

### MVVM Pattern
- **View**: Flutter widgets (UI layer)
- **ViewModel**: GetX controllers (business logic)
- **Model**: Data entities and repositories

### Clean Architecture
- **Presentation Layer**: UI components and controllers
- **Domain Layer**: Business logic and entities
- **Data Layer**: Repositories and data sources

### Modular Structure
```
lib/
├── core/                    # Core functionality
│   ├── constants/          # App constants
│   ├── theme/             # Custom theming system
│   ├── widgets/           # Reusable UI components
│   ├── services/          # Core services
│   ├── database/          # Local storage (Isar)
│   └── routes/            # Navigation configuration
├── modules/               # Feature modules
│   ├── auth/             # Authentication
│   ├── admin/            # Admin functionality
│   ├── user/             # User functionality
│   └── offline_sync/     # Sync management
```

## 🛠️ Technology Stack

### Core Framework
- **Flutter**: 3.5.3+ (Latest stable)
- **Dart**: 3.5.3+

### State Management
- **GetX**: Reactive state management, routing, and dependency injection

### Backend Services
- **Firebase Auth**: User authentication
- **Cloud Firestore**: NoSQL database
- **Firebase Storage**: Image storage
- **Firebase Messaging**: Push notifications

### Local Storage
- **Isar**: High-performance local database
- **Path Provider**: File system access

### Camera & Location
- **Camera**: Device camera integration
- **Image**: Image processing and overlay
- **Geolocator**: GPS location services
- **Geocoding**: Address resolution

### UI & Animations
- **Custom Theme**: Brand-specific design system
- **Lottie**: Advanced animations
- **Shimmer**: Loading animations

### Offline & Sync
- **Connectivity Plus**: Network monitoring
- **WorkManager**: Background tasks
- **UUID**: Unique identifiers

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.5.3 or higher
- Dart SDK 3.5.3 or higher
- Android Studio / VS Code
- Firebase project setup

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd trip_track
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Generate code**
   ```bash
   flutter packages pub run build_runner build
   ```

4. **Firebase Setup**
   - Create a new Firebase project
   - Enable Authentication, Firestore, and Storage
   - Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
   - Place files in appropriate directories

5. **Run the app**
   ```bash
   flutter run
   ```

### Firebase Configuration

#### Authentication Setup
1. Enable Email/Password authentication in Firebase Console
2. Configure authorized domains
3. Set up password reset email templates

#### Firestore Database
1. Create Firestore database in production mode
2. Set up security rules (see Security Rules section)
3. Configure indexes for optimal query performance

#### Storage Setup
1. Enable Firebase Storage
2. Configure storage rules for image uploads
3. Set up bucket permissions

#### Security Rules

**Firestore Rules:**
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can read/write their own data
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Travel requests - users can manage their own, admins can manage all
    match /travel_requests/{requestId} {
      allow read, write: if request.auth != null && 
        (resource.data.createdBy == request.auth.uid || 
         get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin');
      allow create: if request.auth != null && 
        request.resource.data.createdBy == request.auth.uid;
    }
    
    // Audit logs - admin only
    match /audit_logs/{logId} {
      allow read, write: if request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
  }
}
```

**Storage Rules:**
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /images/{allPaths=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

## 📱 App Structure

### Authentication Flow
1. **Splash Screen**: App initialization and branding
2. **Login Screen**: Email/password authentication
3. **Role-Based Navigation**: Admin Dashboard or User Home

### Admin Features
- **Dashboard**: Statistics and quick actions
- **User Management**: Create and manage users
- **Request Overview**: View all travel requests
- **Settings**: App configuration

### User Features
- **Home**: Quick request creation and recent requests
- **Create Request**: Form for new travel requests
- **Request List**: Personal request history
- **Camera Capture**: GPS-stamped meter readings

## 🔧 Development

### Code Generation
```bash
# Generate Isar database code
flutter packages pub run build_runner build

# Watch for changes during development
flutter packages pub run build_runner watch
```

### Testing
```bash
# Run unit tests
flutter test

# Run integration tests
flutter drive --target=test_driver/app.dart
```

### Building
```bash
# Android APK
flutter build apk --release

# iOS (requires macOS)
flutter build ios --release
```

## 📊 Database Schema

### Users Collection
```json
{
  "uid": "string",
  "email": "string",
  "name": "string", 
  "employeeCode": "string",
  "role": "admin|user",
  "createdAt": "timestamp",
  "updatedAt": "timestamp"
}
```

### Travel Requests Collection
```json
{
  "id": "string",
  "userId": "string",
  "name": "string",
  "city": "string",
  "fromLocation": "string",
  "toLocation": "string",
  "vehicleType": "Car|Bike",
  "status": "Start Missing|End Missing|Completed",
  "requestDate": "timestamp",
  "startImageUrl": "string",
  "endImageUrl": "string",
  "startImageMetadata": "object",
  "endImageMetadata": "object",
  "createdAt": "timestamp",
  "updatedAt": "timestamp"
}
```

## 🎨 Design System

### Brand Colors
- **Primary**: #095763 (0xFF095763)
- **Accent**: #00BCD4
- **Success**: #4CAF50
- **Warning**: #FF9800
- **Error**: #F44336

### Typography
- **Display**: 32px, Bold
- **Headline**: 20-22px, SemiBold
- **Title**: 14-16px, SemiBold
- **Body**: 14-16px, Regular
- **Caption**: 10-12px, Regular

### Spacing
- **Small**: 8px
- **Default**: 16px
- **Large**: 24px

### Components
- **Cards**: 12px radius, subtle shadows
- **Buttons**: 8px radius, gradient backgrounds
- **Inputs**: Floating labels, animated validation

## 🔒 Security Features

- **Firebase Security Rules**: Server-side data validation
- **Role-Based Access**: Granular permission system
- **Image Metadata**: GPS and timestamp verification
- **Audit Logging**: Complete action tracking
- **Offline Encryption**: Local data protection

## 🚀 Performance Optimizations

- **Offline-First**: Instant app responsiveness
- **Image Compression**: Optimized storage usage
- **Lazy Loading**: Efficient data fetching
- **Background Sync**: Non-blocking synchronization
- **Caching**: Smart data persistence

## 📈 Analytics & Monitoring

- **Firebase Analytics**: User behavior tracking
- **Crashlytics**: Error monitoring
- **Performance Monitoring**: App performance metrics
- **Custom Events**: Business-specific analytics

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

### Code Standards
- Follow Flutter/Dart style guidelines
- Use meaningful variable names
- Add comprehensive comments
- Write unit tests for business logic
- Ensure proper error handling

## 📄 License

This project is proprietary software owned by Rayzon Solar. All rights reserved.

## 📞 Support

For technical support or questions:
- Email: support@rayzonsolar.com
- Documentation: [Internal Wiki]
- Issue Tracker: [GitHub Issues]

---

**Built with ❤️ for Rayzon Solar**# Trip-Track-Fronted
