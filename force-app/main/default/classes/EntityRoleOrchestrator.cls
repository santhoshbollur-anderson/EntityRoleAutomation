/**
 * @description       : Orchestrates the creation, update, and deactivation of Entity Role records based on
 * Entity record changes. Supports "Back-and-Forth" logic to prevent duplicate records
 * by reactivating historical records instead of inserting new ones.
 * @author            : Santhosh Bollur (Anderson SSC)
 * @last modified on  : 05-27-2026
 **/
public with sharing class EntityRoleOrchestrator {
    public class EntityRoleException extends Exception {
    }

    public static final Id CONTACT_STANDARD_RT_ID = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get(AppConstants.RT_CONTACT_STANDARD)?.getRecordTypeId();

    // PERFORMANCE OPTIMIZATION: Static cache for Custom Metadata to avoid repeated SOQL queries
    private static Map<String, Entity_Role_Mapping__mdt> cachedMappings;

    public class EntityRequest {
        @InvocableVariable(label='Current Entity' required=true)
        public Entities__c currentRecord;
        @InvocableVariable(label='Prior Entity')
        public Entities__c priorRecord;
    }

    /**
     * @description Retrieves and caches Entity Role Mappings for reuse across transactions
     * @return Map of Role Name to Entity_Role_Mapping__mdt
     **/
    private static Map<String, Entity_Role_Mapping__mdt> getMappings() {
        if (cachedMappings == null) {
            cachedMappings = new Map<String, Entity_Role_Mapping__mdt>();
            for (Entity_Role_Mapping__mdt mapping : [
                SELECT Entity_Field_API__c, Role_Name__c, Ownership_Percentage_Field_API_Name__c, State_of_Residence_Field_API__c
                FROM Entity_Role_Mapping__mdt
            ]) {
                cachedMappings.put(mapping.Role_Name__c, mapping);
            }
        }
        return cachedMappings;
    }

    /**
     * @description Main invocable method that processes Entity requests to create, update, or deactivate Entity Roles.
     **/
    @InvocableMethod(label='Execute Entity Role Logic' category='Entities')
    public static void processRoles(List<EntityRequest> requests) {
        // PERFORMANCE OPTIMIZATION: Early exit before any processing
        if (requests == null || requests.isEmpty())
            return;

        try {
            Map<String, Entity_Role_Mapping__mdt> mappingsMap = getMappings();
            List<Entity_Role_Mapping__mdt> allMappings = mappingsMap.values();

            Set<Id> accountIds = new Set<Id>();
            Set<Id> entityIds = new Set<Id>();
            Map<String, Id> nameToAccountIdMap = new Map<String, Id>();

            for (EntityRequest req : requests) {
                Id entityId = req.currentRecord.Id;
                entityIds.add(entityId);

                Id primaryClientId = req.currentRecord.Primary_Client__c;
                if (primaryClientId != null) {
                    accountIds.add(primaryClientId);
                    for (Entity_Role_Mapping__mdt m : allMappings) {
                        String nameVal = (String) safeGet(req.currentRecord, m.Entity_Field_API__c, m.Role_Name__c);
                        if (String.isNotBlank(nameVal)) {
                            nameToAccountIdMap.put(nameVal, primaryClientId);
                        }
                    }
                }
            }

            // Initialize maps for efficient lookups
            Map<String, Entity_Role__c> activeRolesMap = new Map<String, Entity_Role__c>();
            Map<String, Entity_Role__c> historicalRolesMap = new Map<String, Entity_Role__c>();

            // Query both Active and Inactive roles to support back-and-forth reactivation
            for (Entity_Role__c er : getEntityRolesInternal(entityIds)) {
                Id erEntityId = er.Entity__c;
                String erRole = er.Role__c;
                String erStatus = er.Entity_Role_Status__c;
                String erContactName = er.Contact__r.Name;

                if (erStatus == AppConstants.STATUS_ACTIVE) {
                    String activeKey = String.valueOf(erEntityId) + erRole;
                    activeRolesMap.put(activeKey, er);
                }

                // Composite Key: Entity + Role + Contact Name to find previous occupancy
                String historicalKey = String.valueOf(erEntityId) + erRole + erContactName;
                historicalRolesMap.put(historicalKey, er);
            }

            Set<String> namesToProcess = new Set<String>();
            List<Entity_Role__c> rolesToUpdate = new List<Entity_Role__c>();
            Map<Id, Set<String>> rolesToReplaceByEntity = new Map<Id, Set<String>>();
            Map<Id, EntityRequest> requestsByEntityId = new Map<Id, EntityRequest>();
            Set<Id> reactivatedRecordIds = new Set<Id>();

            for (EntityRequest req : requests) {
                Id entityId = req.currentRecord.Id;
                Entities__c currentRecord = req.currentRecord;
                Entities__c priorRecord = req.priorRecord;

                for (Entity_Role_Mapping__mdt m : allMappings) {
                    String entityFieldAPI = m.Entity_Field_API__c;
                    String roleName = m.Role_Name__c;
                    String ownershipFieldAPI = m.Ownership_Percentage_Field_API_Name__c;
                    String stateFieldAPI = m.State_of_Residence_Field_API__c;

                    String currentNameVal = (String) safeGet(currentRecord, entityFieldAPI, roleName);
                    Decimal currentPct = (Decimal) safeGet(currentRecord, ownershipFieldAPI, roleName);
                    String currentState = (String) safeGet(currentRecord, stateFieldAPI, roleName);

                    // MOVE THIS UP: Get the existing role before the optimization check
                    String activeRoleKey = String.valueOf(entityId) + roleName;
                    Entity_Role__c existingRole = activeRolesMap.get(activeRoleKey);

                    // PERFORMANCE OPTIMIZATION: Check prior record to see if fields actually changed
                    if (priorRecord != null) {
                        String priorNameVal = (String) safeGet(priorRecord, entityFieldAPI, roleName);
                        Decimal priorPct = (Decimal) safeGet(priorRecord, ownershipFieldAPI, roleName);
                        String priorState = (String) safeGet(priorRecord, stateFieldAPI, roleName);

                        if (currentNameVal == priorNameVal && currentPct == priorPct && currentState == priorState) {
                            // CRITICAL FIX: Only skip if nothing changed AND (the role actually exists OR the name is blank)
                            if (existingRole != null || String.isBlank(currentNameVal)) {
                                continue; 
                            }
                        }
                    }

                    // HANDLE BLANK FIELDS: If name is cleared, deactivate the existing role
                    if (String.isBlank(currentNameVal)) {
                        if (existingRole != null) {
                            markRoleForReplacement(rolesToReplaceByEntity, entityId, roleName);
                        }
                        continue;
                    }

                    // Check for historical record for reactivation (Back-and-forth scenario)
                    String historicalKey = String.valueOf(entityId) + roleName + currentNameVal;
                    Entity_Role__c historicalRole = historicalRolesMap.get(historicalKey);

                    // CASE 1: Occupant Changed or New Role
                    if (existingRole == null || existingRole.Contact__r.Name != currentNameVal) {
                        if (historicalRole != null) {
                            // REACTIVATE: Historical person returning to the same role
                            historicalRole.Entity_Role_Status__c = AppConstants.STATUS_ACTIVE;
                            syncRoleData(historicalRole, currentNameVal, currentPct, currentState);
                            rolesToUpdate.add(historicalRole);
                            reactivatedRecordIds.add(historicalRole.Id);

                            if (existingRole != null) {
                                markRoleForReplacement(rolesToReplaceByEntity, entityId, roleName);
                            }
                        } else {
                            // Truly new person: Flag for lookup and insert
                            namesToProcess.add(currentNameVal);
                            requestsByEntityId.put(entityId, req);
                            markRoleForReplacement(rolesToReplaceByEntity, entityId, roleName);
                        }
                    }
                    // CASE 2: Same Person, Sync Data
                    else if (existingRole.ShareHolder_Ownership__c != currentPct || existingRole.State_of_Residence__c != currentState) {
                        if (syncRoleData(existingRole, currentNameVal, currentPct, currentState)) {
                            rolesToUpdate.add(existingRole);
                        }
                    }
                }
            }

            if (!rolesToUpdate.isEmpty()) {
                update rolesToUpdate;
            }

            if (!rolesToReplaceByEntity.isEmpty()) {
                Map<String, Id> contactMap = findOrCreateContactsScoped(namesToProcess, accountIds, nameToAccountIdMap);

                // Pass the reactivated IDs to ensure they are NOT flipped back to Inactive
                deactivateSpecificRoles(rolesToReplaceByEntity, reactivatedRecordIds);

                createNewRolesSelective(requestsByEntityId.values(), allMappings, contactMap, rolesToReplaceByEntity);
            }
        } catch (Exception e) {
            String errorMessage = e.getMessage();
            if (errorMessage.contains(AppConstants.DML_ERROR_INVALID_PICKLIST)) {
                errorMessage = AppConstants.ERROR_INVALID_PICKLIST;
            } else if (errorMessage.contains(AppConstants.DML_ERROR_REQUIRED_FIELD)) {
                errorMessage = AppConstants.ERROR_REQUIRED_FIELD;
            }
            throw new EntityRoleException(AppConstants.ERROR_ENTITY_ROLE_AUTOMATION + ' ' + errorMessage);
        }
    }

    private static void markRoleForReplacement(Map<Id, Set<String>> replaceMap, Id entityId, String roleName) {
        if (!replaceMap.containsKey(entityId)) {
            replaceMap.put(entityId, new Set<String>());
        }
        replaceMap.get(entityId).add(roleName);
    }

    private static void createNewRolesSelective(List<EntityRequest> requests, List<Entity_Role_Mapping__mdt> mappings, Map<String, Id> contactMap, Map<Id, Set<String>> rolesToReplaceByEntity) {
        List<Entity_Role__c> rolesToInsert = new List<Entity_Role__c>();

        for (EntityRequest req : requests) {
            Id entityId = req.currentRecord.Id;
            Entities__c currentRecord = req.currentRecord;
            Set<String> rolesNeeded = rolesToReplaceByEntity.get(entityId);

            if (rolesNeeded == null)
                continue;

            for (Entity_Role_Mapping__mdt m : mappings) {
                String roleName = m.Role_Name__c;
                if (!rolesNeeded.contains(roleName))
                    continue;

                String newVal = (String) safeGet(currentRecord, m.Entity_Field_API__c, roleName);
                if (String.isNotBlank(newVal) && contactMap.containsKey(newVal)) {
                    Decimal newPct = (Decimal) safeGet(currentRecord, m.Ownership_Percentage_Field_API_Name__c, roleName);
                    String newState = (String) safeGet(currentRecord, m.State_of_Residence_Field_API__c, roleName);

                    Entity_Role__c newRole = new Entity_Role__c(Entity__c = entityId, Contact__c = contactMap.get(newVal), Role__c = roleName, Entity_Role_Status__c = AppConstants.STATUS_ACTIVE);

                    syncRoleData(newRole, newVal, newPct, newState);
                    rolesToInsert.add(newRole);
                }
            }
        }
        if (!rolesToInsert.isEmpty()) {
            insert rolesToInsert;
        }
    }

    private static void deactivateSpecificRoles(Map<Id, Set<String>> entityToRoles, Set<Id> skipIds) {
        List<Entity_Role__c> toDeactivate = new List<Entity_Role__c>();
        Set<Id> entityIds = entityToRoles.keySet();

        if (entityIds.isEmpty())
            return;

        // CRITICAL FIX: Pulled SOQL outside of the loop
        for (Entity_Role__c er : [
            SELECT Id, Entity__c, Role__c
            FROM Entity_Role__c
            WHERE Entity__c IN :entityIds AND Entity_Role_Status__c = :AppConstants.STATUS_ACTIVE
        ]) {
            if (entityToRoles.get(er.Entity__c).contains(er.Role__c) && !skipIds.contains(er.Id)) {
                er.Entity_Role_Status__c = AppConstants.STATUS_INACTIVE;
                toDeactivate.add(er);
            }
        }

        if (!toDeactivate.isEmpty()) {
            update toDeactivate;
        }
    }

    private static Boolean syncRoleData(Entity_Role__c er, String currentName, Decimal newPct, String newState) {
        Boolean changed = false;

        if (er.ShareHolder_Ownership__c != newPct) {
            er.ShareHolder_Ownership__c = newPct;
            changed = true;
        }
        if (er.State_of_Residence__c != newState) {
            er.State_of_Residence__c = newState;
            changed = true;
        }
        return changed;
    }

    private static Map<String, Id> findOrCreateContactsScoped(Set<String> names, Set<Id> accountIds, Map<String, Id> nameToAccountIdMap) {
        Map<String, Id> contactMap = new Map<String, Id>();

        for (Contact con : [SELECT Id, Name FROM Contact WHERE Name IN :names AND AccountId IN :accountIds WITH SECURITY_ENFORCED]) {
            contactMap.put(con.Name, con.Id);
        }

        Set<String> remainingNames = new Set<String>(names);
        remainingNames.removeAll(contactMap.keySet());

        if (remainingNames.isEmpty()) {
            return contactMap;
        }

        // NOTE: Removed org-wide fallback search. Only account-scoped lookups are allowed.
        // The following org-wide contact search was intentionally commented out to ensure
        // contacts are only matched/created scoped to the provided Account(s).
        /*
        for (Contact con : [SELECT Id, Name FROM Contact WHERE Name IN :remainingNames WITH SECURITY_ENFORCED]) {
            contactMap.put(con.Name, con.Id);
        }

        remainingNames.removeAll(contactMap.keySet());

        if (remainingNames.isEmpty()) {
            return contactMap;
        }
        */

        List<Contact> newContacts = new List<Contact>();

        for (String fullName : remainingNames) {
            if (String.isBlank(fullName))
                continue;
            Contact c = parseName(fullName);
            c.AccountId = nameToAccountIdMap.get(fullName);
            c.RecordTypeId = CONTACT_STANDARD_RT_ID;
            c.Inactive_Client__c = false;
            newContacts.add(c);
        }

        if (!newContacts.isEmpty()) {
            insert newContacts;
            for (Contact con : [SELECT Id, Name FROM Contact WHERE Id IN :newContacts]) {
                contactMap.put(con.Name, con.Id);
            }
        }

        return contactMap;
    }

    private static List<Entity_Role__c> getEntityRolesInternal(Set<Id> entityIds) {
        Set<String> fieldsToQuery = new Set<String>{ 'Entity__c', 'Role__c', 'Contact__r.Name', 'Entity_Role_Status__c' };
        for (Schema.FieldSetMember field : SObjectType.Entity_Role__c.FieldSets.Entity_Role_Details.getFields()) {
            fieldsToQuery.add(field.getFieldPath());
        }
        String query = 'SELECT ' + String.join(new List<String>(fieldsToQuery), ', ') + ' FROM Entity_Role__c WHERE Entity__c IN :entityIds';
        return Database.query(query);
    }

    private static Contact parseName(String fullName) {
        fullName = fullName.trim();
        List<String> parts = fullName.split(' ');
        if (parts.size() == 1)
            return new Contact(LastName = parts[0]);
        String firstName = parts[0];
        parts.remove(0);
        return new Contact(FirstName = firstName, LastName = String.join(parts, ' '));
    }

    /**
     * @description Safely retrieves field values from an SObject. Prevents generic SObjectExceptions
     * from failing the transaction silently if a Custom Metadata API Name is incorrect.
     */
    private static Object safeGet(SObject record, String fieldApiName, String roleName) {
        if (record == null || String.isBlank(fieldApiName))
            return null;
        try {
            return record.get(fieldApiName);
        } catch (Exception e) {
            throw new EntityRoleException('Invalid Field API Name [' + fieldApiName + '] in Custom Metadata for Role [' + roleName + ']. Ensure the field exists on the Object.');
        }
    }
}