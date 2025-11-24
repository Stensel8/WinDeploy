# Setting Up Intune with Autopilot Device Preparation

## Overview
This guide provides step-by-step instructions for configuring Microsoft Intune with Autopilot Device Preparation (formerly Autopilot v2), streamlining Mobile Device Management (MDM) for IT professionals.

To establish a baseline setup, create three security groups in Microsoft Entra ID (formerly Azure AD). These groups enable targeted policies and configurations:

- **Standard Users Group**: For regular users on Autopilot-prepared devices.
- **Local Admins Group**: For users requiring local administrator privileges.
- **Devices Group**: For the devices themselves, to support device-based policies.

These groups form the foundation. You can add more groups later for finer control over users or applications.

## Prerequisites
- Access to the Microsoft Entra admin center with appropriate permissions (e.g., Global Administrator or User Administrator).
- Microsoft Intune enabled in your Microsoft Entra ID tenant (via Microsoft 365 Business Premium or equivalent licenses).
- The "Intune Provisioning Client" service principal (required for the Devices group).

## Steps

### 1. Navigate to Microsoft Entra Admin Center
1. Open your web browser and go to [https://entra.microsoft.com/](https://entra.microsoft.com/).
2. Sign in with an account that has the necessary permissions.

### 2. Access Groups
1. In the left-hand menu, select **Groups**.
2. Click on **All groups**.

Example image: ![Entra ID Groups](./Intune%20configuration/Entra-Groups.png)

### 3. Create the Devices Group
1. Click **+ New group**.  
2. Select **Security** as the group type.  
3. Enter the group name: `Autopilot Device Preparation - Devices`.  
4. Optionally add a description, e.g., "Group for Autopilot Device Preparation devices".  
5. Set **Entra roles can be assigned to this group**: **No**.  
6. Set **Membership type**: **Assigned**.  
    - Source: **Cloud**  
    - Type: **Security**  
7. Under **Owners**, click **Add owners** and search for `Intune Provisioning Client` (service principal). Select it and click **Select**.  
8. Leave **Members** empty — the group will be populated automatically with Autopilot Device Preparation devices later.  
9. Click **Create** and verify the group in the **Groups** list (confirm owners and settings).

Example image: ![Autopilot Device Group](./Intune%20configuration/Autopilot-device-group.png)


### 4. Create the Standard Users Group
1. Click **+ New group**.  
2. Select **Security** as the group type.  
3. Enter the group name: `Autopilot Device Preparation - Users`.  
4. Optionally add a description: "Security group for Autopilot Device Preparation policies targeting standard users."  
5. Set **Entra roles can be assigned to this group**: **No**.  
6. Set **Membership type**: **Assigned**.  
    - Source: **Cloud**  
    - Type: **Security**  
7. Leave **Owners** unassigned.  
8. Under **Members**, add the user accounts that should be standard users (this group is populated manually).  
9. Click **Create**.  
10. Verify the group in the **Groups** list (confirm members and settings).

Example image: ![Autopilot standard user Group](./Intune%20configuration/Autopilot-standard_user-group.png)


### 5. Create the Local Admins Group
1. Click **+ New group**.  
2. Select **Security** as the group type.  
3. Enter the group name: `Autopilot Device Preparation - Local Admins`.  
4. Optionally add a description: "Security group for Autopilot Device Preparation policies targeting users with local admin privileges."  
5. Set **Entra roles can be assigned to this group**: **No**.  
6. Set **Membership type**: **Assigned**.  
    - Source: **Cloud**  
    - Type: **Security**  
7. Leave **Owners** unassigned.  
8. Under **Members**, add the user accounts that should have local administrator privileges (populate manually).  
9. Click **Create**.  
10. Verify the group in the **Groups** list (confirm members and settings).

Example image: ![Autopilot local admin Group](./Intune%20configuration/Autopilot-local_admin-group.png)

### 6. Prepare Apps and Scripts
Before creating Device Preparation Policies, ensure you have set up any required apps and scripts in Intune.

1. To create Apps, navigate to **Home > Apps** in the Intune admin center.

   Example image: ![Intune apps](./Intune%20configuration/Intune-apps.png)

2. To create Scripts, navigate to **Home > Devices > Scripts and Remediations** in the Intune admin center.

   Example image: ![Intune scripts](./Intune%20configuration/Intune-scripts.png)

**Note on OOBE Script**: For customizing the Out-of-Box Experience (OOBE), refer to the [Skip-OOBEPrivacy-Intune.ps1](../Scripts/Intune/Platform%20scripts/Skip-OOBEPrivacy-Intune.ps1) script. This can be added to Device Preparation Policies to skip privacy questions and accelerate provisioning.

### 7. Configure MDM Enrollment for User Groups
1. Go to the Microsoft Intune admin center at [https://intune.microsoft.com](https://intune.microsoft.com).
2. Navigate to **Devices > Enrollment restrictions**.
3. Under **Mobility (MDM and WIP)**, remove any other MDM providers except Microsoft Intune.
4. Select **Microsoft Intune**.
5. Configure the following settings (using Microsoft defaults where applicable):

   - **MDM user scope**: Select **Some** and choose both `Autopilot Device Preparation - Users` and `Autopilot Device Preparation - Local Admins`.  
   - **MDM terms of use URL**: Keep default — https://portal.manage.microsoft.com/TermsofUse.aspx  
   - **MDM discovery URL**: Keep default — https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc  
   - **MDM compliance URL**: Keep default — https://portal.manage.microsoft.com/?portalAction=Compliance  
   - **Windows Information Protection (WIP) user scope**: Select **Some** and choose both `Autopilot Device Preparation - Users` and `Autopilot Device Preparation - Local Admins`.  
   - **WIP terms of use URL**: Leave empty unless you have a custom URL.  
   - **WIP discovery URL**: Keep default — https://wip.mam.manage.microsoft.com/Enroll  
   - **WIP compliance URL**: Leave empty unless you have a custom URL.

   Example image: ![MDM and WIP settings](./Intune%20configuration/MDM_and_WIP-settings.png)


### 8. Create Device Preparation Policies

#### Navigate to Device Preparation Policies
1. In the Intune admin center, go to **Devices > Windows > Windows enrollment > Device preparation policies**.
2. Click **Create policy** and select **User-driven** mode (Automatic mode is in beta and not recommended due to potential issues).

   ![Device Preparation](./Intune%20configuration/Device-Preparation-new_policy.png)

#### Create Policies for Each User Group
Create two separate policies:

- One for standard users targeting the `Autopilot Device Preparation - Users` group.

  ![Device Preparation standard user policy](./Intune%20configuration/Device-Preparation-new_policy-standarduser_1.png)
- One for local admins targeting the `Autopilot Device Preparation - Local Admins` group.

  ![Device Preparation local admin policy](./Intune%20configuration/Device-Preparation-new_policy-localadmin_1.png)

#### Assign Devices to the Devices Group
4. Assign the device to the `Autopilot Device Preparation - Devices` group created earlier.

   ![Device Preparation device group assignment](./Intune%20configuration/Device-Preparation-new_policy-standarduser_2.png)

#### Configure Deployment and OOBE Settings
5. Configure **Deployment settings** and **Out-of-box experience (OOBE)** based on your needs. Recommended settings:

   - **Deployment mode**: User-driven
   - **Deployment type**: Single user
   - **Join type**: Microsoft Entra joined
   - **User account type**: Standard user (for users policy) or Administrator (for local admins policy)
   - Additional options: Skip privacy settings, Skip OneDrive setup, etc.

     ![Device Preparation](./Intune%20configuration/Device-Preparation-new_policy-standarduser_3.png)

#### Configure Apps and Scripts
6. Add **Apps and Scripts** for deployment.  
   **Note:** These install during Autopilot provisioning (OOBE or ESPv2). Assign apps via **Home > Apps** in Intune or directly here. Non-assigned apps install after full enrollment.

   ![Device Preparation apps and scripts](./Intune%20configuration/Device-Preparation-new_policy-standarduser_4.png)

#### Assign the Policy
7. Assign the policy to the appropriate user group (`Autopilot Device Preparation - Users` or `Autopilot Device Preparation - Local Admins`).  
   Scope tags can be added if needed, but are not covered in this guide.

   ![Device Preparation assignment](./Intune%20configuration/Device-Preparation-new_policy-standarduser_5.png)

### 9. Assigning Licenses to Groups
To simplify license management, assign Intune licenses to the user groups created earlier. This eliminates the need to assign licenses individually to each user. By adding a user to one of these groups, they will automatically receive the required license and gain access to Intune and Autopilot functionality.
1. Head to the Microsoft 365 admin center: [https://admin.microsoft.com](https://admin.microsoft.com).
2. Go to License - Subscriptions > Microsoft 365 Business Premium (or the license you use that includes Intune).
3. Click on **Groups** tab.
4. Click on **Assign licenses** and assign the `Autopilot Device Preparation - Users` and `Autopilot Device Preparation - Local Admins` groups to the license.

   ![Licenses and groups in Microsoft 365 Admin Center](./Intune%20configuration/M365-Admin_center-licenses-groups.png)

### 10. Assigning Groups to Users
Finally, ensure users are added to the appropriate groups created earlier. This will ensure they receive the correct policies and permissions when using Autopilot Device Preparation.
1. In the Microsoft 365 admin center or the Microsoft Entra admin center, navigate to **Users**.
2. Select the user you want to add to a group.
3. Go to the **Groups** tab and click on **+ Add memberships**.
4. Search for and select either `Autopilot Device Preparation - Users` or `Autopilot Device Preparation - Local Admins` based on the user's role.
5. Click **Save** to confirm the changes.

   ![Licenses and groups assigned to user in Microsoft 365 Admin Center](./Intune%20configuration/M365-Admin_center-licenses-groups-users.png)


## Troubleshooting
- If the "Intune Provisioning Client" is not found, ensure Intune is properly set up in your tenant and that you have the necessary licenses.
- Verify group configurations in the Microsoft Entra portal.
- For permission issues, contact your Microsoft Entra administrator.

