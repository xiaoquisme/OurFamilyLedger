# OurFamilyLedger Test Setup

## Adding Test Targets to Xcode

To add the test targets to your Xcode project, follow these steps:

### Step 1: Add Unit Test Target

1. Open `OurFamilyLedger.xcodeproj` in Xcode
2. Go to **File > New > Target...**
3. Select **iOS > Unit Testing Bundle**
4. Configure:
   - **Product Name**: `OurFamilyLedgerTests`
   - **Bundle Identifier**: `com.xiaoquisme.ourfamilyledgers.tests`
   - **Target to Test**: `OurFamilyLedger`
5. Click **Finish**
6. Delete the auto-generated test file
7. Add existing files:
   - Right-click on the `OurFamilyLedgerTests` group
   - Select **Add Files to "OurFamilyLedger"...**
   - Navigate to `OurFamilyLedgerTests/` directory
   - Select all `.swift` files and the `Info.plist`
   - Check "Copy items if needed" is **unchecked**
   - Check "Add to targets" includes `OurFamilyLedgerTests`

### Step 2: Add UI Test Target

1. Go to **File > New > Target...**
2. Select **iOS > UI Testing Bundle**
3. Configure:
   - **Product Name**: `OurFamilyLedgerUITests`
   - **Bundle Identifier**: `com.xiaoquisme.ourfamilyledgers.uitests`
   - **Target to Test**: `OurFamilyLedger`
4. Click **Finish**
5. Delete the auto-generated test files
6. Add existing files:
   - Right-click on the `OurFamilyLedgerUITests` group
   - Select **Add Files to "OurFamilyLedger"...**
   - Navigate to `OurFamilyLedgerUITests/` directory
   - Select all `.swift` files and the `Info.plist`

### Step 3: Configure Test Targets

For both test targets, ensure these settings in **Build Settings**:

- **iOS Deployment Target**: 17.0
- **Swift Language Version**: Swift 5.9
- **Host Application**: OurFamilyLedger

## Running Tests

### Run All Tests
```bash
xcodebuild test \
  -scheme OurFamilyLedger \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -enableCodeCoverage YES
```

### Run Unit Tests Only
```bash
xcodebuild test \
  -scheme OurFamilyLedger \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:OurFamilyLedgerTests
```

### Run UI Tests Only
```bash
xcodebuild test \
  -scheme OurFamilyLedger \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:OurFamilyLedgerUITests
```

## Test Structure

```
OurFamilyLedgerTests/
├── Unit/
│   ├── ViewModels/
│   │   ├── ChatViewModelTests.swift
│   │   └── TransactionListViewModelTests.swift
│   ├── Services/
│   │   ├── CSVServiceTests.swift
│   │   └── ConflictResolverTests.swift
│   ├── Models/
│   │   └── TransactionDraftTests.swift
│   └── Utilities/
│       └── DateExtensionsTests.swift
├── Integration/
│   └── ChatViewModelIntegrationTests.swift
├── Mocks/
│   ├── MockAIService.swift
│   ├── MockOCRService.swift
│   ├── MockKeychainService.swift
│   ├── MockNotificationService.swift
│   ├── TestModelContainer.swift
│   └── TestFixtures.swift
└── Info.plist

OurFamilyLedgerUITests/
├── Flows/
│   ├── TransactionEntryUITests.swift
│   └── NavigationUITests.swift
└── Info.plist
```

## Mock Objects

The test suite includes several mock implementations for testing:

- **MockAIService**: Mock AI service for testing transaction parsing
- **MockOCRService**: Mock OCR service for testing image text recognition
- **MockKeychainService**: Mock keychain for testing credential storage
- **MockNotificationService**: Mock notification service for testing reminders
- **TestModelContainer**: In-memory SwiftData container for testing
- **TestFixtures**: Sample data for testing

## Code Coverage

To generate code coverage reports:

```bash
xcodebuild test \
  -scheme OurFamilyLedger \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -enableCodeCoverage YES \
  -resultBundlePath TestResults.xcresult

# View coverage
xcrun xccov view --report TestResults.xcresult
```
