# Intune Configuration settings

## Administrative Templates
### MS Security Guide
- Block Flash activation in Office documents: **Enabled**
  - Block Flash player in Office (Device): **Block all activation**
- Restrict legacy JScript execution for Office: **Enabled**
  - Access: (Device): **69632**
  - Excel: (Device): **69632**
  - OneNote: (Device): **69632**
  - Outlook: (Device): **69632**
  - PowerPoint: (Device): **69632**
  - Project: (Device): **69632**
  - Publisher: (Device): **69632**
  - Visio: (Device): **69632**
  - Word: (Device): **69632**

---

## Windows Components > BitLocker Drive Encryption > Fixed Data Drives
- Select the encryption type: (Device): **Used Space Only encryption**
- Enforce drive encryption type on fixed data drives: **Enabled**
- Choose drive encryption method and cipher strength (Windows 10 [Version 1511] and later): **Enabled**
  - Select the encryption method for fixed data drives: **XTS-AES 256-bit**
  - Select the encryption method for operating system drives: **XTS-AES 256-bit**
  - Select the encryption method for removable data drives: **XTS-AES 256-bit**

---

## Windows Components > AutoPlay Policies
- Turn off Autoplay on: (User): **CD-ROM and removable media drives**
- Disallow Autoplay for non-volume devices (User): **Enabled**
- Set the default behavior for AutoRun (User): **Enabled**
  - Default AutoRun Behavior (User): **Do not execute any autorun commands**
- Turn off Autoplay (User): **Enabled**

---

## Windows Components > App runtime
- Allow Microsoft accounts to be optional: **Enabled**

---

## Windows Components > App Package Deployment
- Feedback Hub (Device): **True**
- Microsoft 365 Copilot (Device): **False**
- Microsoft Clipchamp (Device): **True**
- Microsoft Copilot (Device): **True**
- Microsoft News (Device): **True**
- Microsoft Photos (Device): **False**
- Microsoft Solitaire Collection (Device): **True**
- Microsoft Sticky Notes (Device): **True**
- Microsoft Teams (Device): **False**
- Microsoft To Do (Device): **True**
- MSN Weather (Device): **True**
- Outlook for Windows (Device): **False**
- Paint (Device): **False**
- Quick Assist (Device): **False**
- Snipping Tool (Device): **False**
- Windows Calculator (Device): **False**
- Windows Camera (Device): **False**
- Windows Media Player (Device): **True**
- Windows Notepad (Device): **False**
- Windows Sound Recorder (Device): **True**
- Windows Terminal (Device): **False**
- Xbox Gaming App (Device): **True**
- Xbox Identity Provider (Device): **True**
- Xbox Speech To Text Overlay (Device): **True**
- Xbox TCUI (Device): **True**
- Remove Default Microsoft Store packages from the system: **Enabled**

---

## System > Power Management > Sleep Settings
- Require a password when a computer wakes (on battery): **Enabled**
- Require a password when a computer wakes (plugged in): **Enabled**

---

## System > Power Management > Notification Settings
- Low Battery Notification Level (Device): **35**
- Critical battery notification action: **Enabled**
  - Critical Battery Notification Action (Device): **Hibernate**
- Critical battery notification level: **Enabled**
  - Critical Battery Notification Level (Device): **10**
- Low battery notification action: **Enabled**
  - Low Battery Notification Action (Device): **Take no action**
- Low battery notification level: **Enabled**

---

## System > Device Health Attestation Service
- Enable Device Health Attestation Monitoring and Reporting: **Enabled**

---

## Desktop > Desktop
- Enter URL(s) of desktop item(s) to Add (space separated): (User): **shell:MyComputerFolder**
- Enter URL(s) of desktop item(s) to Delete (space separated): (User): *(optioneel)*
- Add/Delete items (User): **Enabled**

---

## Control Panel > Personalization
- Path to theme file: (User): **C:\Windows\Resources\Themes\dark.theme**
- Load a specific theme (User): **Enabled**

---

## Browser
- Configure Open Microsoft Edge With (User): **Load the previous pages**

---

## Experience
- Allow Sync My Settings: **Allow**
- Allow Windows Spotlight (User): **Allow**
- Allow Tailored Experiences With Diagnostic Data (User): **Block**
- Allow Third Party Suggestions In Windows Spotlight (User): **Block**
- Allow Windows Consumer Features: **Allow**
- Allow Windows Spotlight On Action Center (User): **Allow**
- Allow Windows Spotlight Windows Welcome Experience (User): **Allow**
- Allow Windows Tips: **Allow**
- Configure Windows Spotlight On Lock Screen (User): **Windows spotlight enabled.**
- Allow Windows Spotlight On Settings (User): **Block**
- Configure Chat Icon: **Hide**
- Do Not Show Feedback Notifications: **Feedback notifications are disabled.**
- Prevent Users From Turning On Browser Syncing: **Disabled**
- Show Lock On User Tile: **Enabled**

---

## Google Chrome
- List of types that should be excluded from synchronization (User): **passwords, autofill, payments**
- Disable synchronization of data with Google (User): **Enabled**
- List of types that should be excluded from synchronization (User): **Enabled**

---

## Microsoft Edge
- Ads setting for sites with intrusive ads (User): **Enabled**
- Ads setting for sites with intrusive ads (User): **Block ads on sites with intrusive ads. (Default value)**
- Allow importing of autofill form data (User): **Disabled**
- Allow importing of payment info (User): **Disabled**
- Allow importing of saved passwords (User): **Disabled**
- Configure the list of types that are excluded from synchronization (User): **Enabled, passwords, addressesAndMore, edgeWallet**
- Configure the list of types that are included for synchronization (User): **Enabled, favorites, settings, extensions, history, openTabs, collections, apps, edgeFeatureUsage**
- Force synchronization of browser data and do not show the sync consent prompt (User): **Enabled**
- Hide the First-run experience and splash screen (User): **Enabled**
- Microsoft Edge - Default Settings (users can override): **Enable favorites bar (User): Enabled**
- Get user confirmation before closing a browser window with multiple tabs (User): **Disabled**
- Manage Search Engines (User): **Enabled**
- Manage Search Engines (User):  
  `{"name": "Google", "keyword": "google.com", "search_url": "https://www.google.com/search?q={searchTerms}", "is_default": true}`
- Action to take on Microsoft Edge startup (User): **Enabled**
- Action to take on Microsoft Edge startup (User): **Restore the last session**
- Enable preload of the new tab page for faster rendering (User): **Enabled**

---

## OneDrive
- Block file downloads when users are low on disk space: **Enabled**
  - Minimum available disk space: (Device): **5000**
- Configure team site libraries to sync automatically (User): **Enabled**
  - *libraryId needs to be filled in here*
- Convert synced team site files to online-only files: **Enabled**
- Disable a toast and activity center message to encourage a user to sign in OneDrive using an existing credential that is made available to Microsoft applications: **Enabled**
- Disable animation that appears during OneDrive Setup (User): **Enabled**
- Disable the tutorial that appears at the end of OneDrive Setup (User): **Enabled**
- Enable sync health reporting for OneDrive: **Enabled**
- Hide the "Deleted files are removed everywhere" reminder: **Enabled**
- Prevent users from changing the location of their OneDrive folder (User): **Enabled**
- Prevent users from moving their Windows known folders to OneDrive: **Disabled**
- Prevent users from redirecting their Windows known folders to their PC: **Disabled**
- Prevent users from syncing personal OneDrive accounts (User): **Disabled**
- Prompt user to confirm when they delete shared content: **Enabled**
- Prompt users to move Windows known folders to OneDrive: **Disabled**
- Prompt users when they delete multiple OneDrive files on their local computer: **Disabled**
- Require users to confirm large delete operations: **Disabled**
- Set the default location for the OneDrive folder (User): **Disabled**
- Set the maximum size of a user's OneDrive that can download automatically: **Disabled**
- Silently move Windows known folders to OneDrive: **Enabled**
  - Desktop (Device): **True**
  - Documents (Device): **True**
  - Pictures (Device): **True**
  - Show notification to users after folders have been redirected (Device): **No**
  - Tenant ID: (Device): 
    - *libraryId needs to be filled in here*
- Silently sign in users to the OneDrive sync app with their Windows credentials: **Enabled**
- Specify SharePoint Server URL and organization name: **Disabled**
- Specify the OneDrive location in a hybrid environment: **Disabled**
- Start OneDrive automatically when signing in to Windows (User): **Disabled**
- Sync Admin Reports: **Disabled**
- Use OneDrive Files On-Demand: **Disabled**
- Warn users who are low on disk space: **Enabled**
  - Minimum available disk space: (Device): **5000**
