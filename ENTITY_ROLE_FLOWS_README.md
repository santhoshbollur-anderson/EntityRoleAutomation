# Entity Role Automation Flows

## Overview
This document describes the master flow and subflow created to automate Entity Role status management. When a new Entity Role record is created with Active status, the automation ensures only one active role of the same type exists per entity.

## Flows Created

### 1. Entity Role Master Flow (`Entity_Role_Master_Flow.flow-meta.xml`)

**Type:** Record-Triggered Flow  
**Trigger:** After Insert on `Entity_Role__c`  
**Status:** Active

**Purpose:**  
This master flow triggers when a new Entity Role record is created. It checks if the new record has an Active status and, if so, calls the subflow to deactivate any other active roles with the same role name for the same entity.

**Flow Logic:**
1. **Trigger:** Fires after a new Entity_Role__c record is inserted
2. **Decision:** Checks if `Entity_Role_Status__c` = 'Active'
3. **Action:** If Active, calls the subflow `Deactivate_Other_Entity_Roles` with parameters:
   - `varCurrentRecordId` - ID of the newly created record
   - `varEntityId` - The Entity (Entity__c) lookup value
   - `varRoleName` - The Role__c field value

**Key Elements:**
- Decision Element: `Check_Status_Is_Active`
- Subflow Call: `Call_Deactivate_Subflow`

---

### 2. Deactivate Other Entity Roles (`Deactivate_Other_Entity_Roles.flow-meta.xml`)

**Type:** Autolaunched Flow (Subflow)  
**Status:** Active

**Purpose:**  
This subflow searches for other Entity Role records with the same role and entity that are currently Active (excluding the current record) and sets their status to Inactive.

**Input Variables:**
- `varCurrentRecordId` (String) - ID of the current/new record to exclude from search
- `varEntityId` (String) - The Entity lookup ID to match
- `varRoleName` (String) - The role name to match

**Flow Logic:**
1. **Get Records:** Query Entity_Role__c where:
   - `Entity__c` = varEntityId (same entity)
   - `Role__c` = varRoleName (same role)
   - `Entity_Role_Status__c` = 'Active' (currently active)
   - `Id` ≠ varCurrentRecordId (exclude the new record)
   - Get all matching records (collection)
2. **Decision:** Check if any records were found
3. **Loop:** Iterate through each found record
4. **Assignment:** For each record, set `Entity_Role_Status__c` = 'Inactive'
5. **Update:** Save all updated records in bulk

**Key Elements:**
- Record Lookup: `Get_Other_Active_Roles` (returns collection)
- Decision: `Check_If_Other_Roles_Found`
- Loop: `Loop_Through_Active_Roles`
- Assignment: `Set_Status_To_Inactive` (inside loop)
- Record Update: `Update_All_Roles` (bulk update)

---

## Business Scenario

**Requirement:**  
When someone manually creates an Entity Role record with:
- A specific role (e.g., "Director", "Manager", etc.)
- Status = Active

**Automation:**  
The system should automatically search for other Entity Role records for the same entity with:
- The same role name
- Status = Active

If any are found, they should be updated to Status = Inactive, ensuring only one active role of each type exists per entity.

---

## Example Scenario

**Before:**
- Entity: ABC Company
  - Entity Role 1: Role = "Director", Status = Active
  
**User Action:**
- User creates Entity Role 2: Entity = ABC Company, Role = "Director", Status = Active

**After Automation:**
- Entity: ABC Company
  - Entity Role 1: Role = "Director", Status = **Inactive** ← Updated by flow
  - Entity Role 2: Role = "Director", Status = Active ← New record remains active

---

## Technical Notes

### Field API Names Used:
- **Entity_Role__c** - Custom object for entity roles
- **Entity_Role_Status__c** - Picklist field (Active, Inactive)
- **Entity__c** - Lookup field to the Entity
- **Role__c** - Text field containing the role name

### Flow Configuration:
- **API Version:** 61.0
- **Canvas Mode:** AUTO_LAYOUT_CANVAS
- **Builder Type:** LightningFlowBuilder

### Important Considerations:

1. **Bulk Processing:** The subflow uses `getFirstRecordOnly=false` and processes ALL active roles with the same Entity and Role combination. It uses a loop to iterate through each record and performs a bulk update at the end, ensuring efficient processing of multiple records.

2. **Manual Creation:** The flow triggers on INSERT only, so it's designed for manual record creation scenarios as described in the requirements.

3. **Update Trigger:** If you need to handle updates as well (e.g., when changing a role from Inactive to Active), you would need to modify the trigger type to include "Update" operations.

4. **Governor Limits:** The bulk processing approach respects Salesforce governor limits by using a single DML operation to update all records at once, rather than updating them individually within the loop.

---

## Deployment

Both flows are marked as **Active** and ready for deployment. Ensure that:

1. The `Entity_Role__c` custom object exists with required fields
2. The field API names match your org's configuration
3. Test in a sandbox environment before deploying to production

---

## Testing

**Test Scenario 1: New Active Role (Single Existing)**
1. Create Entity Role A: Entity = Test Entity, Role = "Manager", Status = Active
2. Create Entity Role B: Entity = Test Entity, Role = "Manager", Status = Active
3. **Expected:** Entity Role A should automatically change to Inactive

**Test Scenario 1b: New Active Role (Multiple Existing)**
1. Create Entity Role A: Entity = Test Entity, Role = "Manager", Status = Active
2. Create Entity Role B: Entity = Test Entity, Role = "Manager", Status = Active (manually set to Active)
3. Create Entity Role C: Entity = Test Entity, Role = "Manager", Status = Active
4. **Expected:** Both Entity Role A and B should automatically change to Inactive

**Test Scenario 2: New Inactive Role**
1. Create Entity Role C: Entity = Test Entity, Role = "Manager", Status = Inactive
2. **Expected:** No automation should run (Decision element filters out inactive records)

**Test Scenario 3: Different Roles**
1. Create Entity Role D: Entity = Test Entity, Role = "Director", Status = Active
2. Create Entity Role E: Entity = Test Entity, Role = "Manager", Status = Active
3. **Expected:** Both remain Active (different roles)

**Test Scenario 4: Different Entities**
1. Create Entity Role F: Entity = Test Entity 1, Role = "Manager", Status = Active
2. Create Entity Role G: Entity = Test Entity 2, Role = "Manager", Status = Active
3. **Expected:** Both remain Active (different entities)

---

## Future Enhancements

Consider these potential improvements:

1. **Update Trigger:** Add support for role status changes (Inactive → Active)
2. **Role Change Detection:** Handle when the Role__c field value changes on an existing record
3. **Audit Trail:** Add logging or notifications when roles are automatically deactivated
4. **Error Handling:** Add fault paths to handle scenarios where updates fail
5. **Notification:** Send email or platform event notifications when roles are automatically deactivated
