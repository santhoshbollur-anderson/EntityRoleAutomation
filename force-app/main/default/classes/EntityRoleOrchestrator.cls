/**
 * @description       : Orchestrates the creation, update, and deactivation of Entity Role records based on
 * Entity record changes. Supports "Back-and-Forth" logic to prevent duplicate records
 * by reactivating historical records instead of inserting new ones.
 * @author            : Santhosh Bollur (Anderson SSC)
 * @last modified on  : 05-14-2026
 **/
public with sharing class EntityRoleOrchestrator {
    public class EntityRoleException extends Exception {
    }

    public static final Id CONTACT_STANDARD_RT_ID = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('Standard')?.getRecordTypeId();

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
            // PERFORMANCE OPTIMIZATION: Use cached mappings instead of querying every time
            Map<String, Entity_Role_Mapping__mdt> mappingsMap = getMappings();
            List<Entity_Role_Mapping__mdt> allMappings = mappingsMap.values();

            // PERFORMANCE OPTIMIZATION: Calculate estimated capacity for collection sizing
            Integer requestCount = requests.size();
            Integer mappingCount = allMappings.size();
            Integer estimatedCapacity = requestCount * mappingCount;

            Set<Id> accountIds = new Set<Id>();
            Set<Id> entityIds = new Set<Id>();
            Map<String, Id> nameToAccountIdMap = new Map<String, Id>();

            for (EntityRequest req : requests) {
                // PERFORMANCE OPTIMIZATION: Cache entity ID to avoid repeated field access
                Id entityId = req.currentRecord.Id;
                entityIds.add(entityId);

                Id primaryClientId = req.currentRecord.Primary_Client__c;
                if (primaryClientId != null) {
                    accountIds.add(primaryClientId);
                    for (Entity_Role_Mapping__mdt m : allMappings) {
                        String nameVal = (String) req.currentRecord.get(m.Entity_Field_API__c);
                        if (String.isNotBlank(nameVal))
                            nameToAccountIdMap.put(nameVal, primaryClientId);
                    }
                }
            }

            // PERFORMANCE OPTIMIZATION: Initialize maps for efficient lookups
            Map<String, Entity_Role__c> activeRolesMap = new Map<String, Entity_Role__c>();
            Map<String, Entity_Role__c> historicalRolesMap = new Map<String, Entity_Role__c>();

            // Query both Active and Inactive roles to support back-and-forth reactivation
            for (Entity_Role__c er : getEntityRolesInternal(entityIds)) {
                // PERFORMANCE OPTIMIZATION: Cache field values to avoid repeated access
                Id erEntityId = er.Entity__c;
                String erRole = er.Role__c;
                String erStatus = er.Entity_Role_Status__c;
                String erContactName = er.Contact__r.Name;

                // PERFORMANCE OPTIMIZATION: Use String.join for efficient key generation
                if (erStatus == EntityRoleConstants.STATUS_ACTIVE) {
                    String activeKey = String.valueOf(erEntityId) + erRole;
                    activeRolesMap.put(activeKey, er);
                }
                // Composite Key: Entity + Role + Contact Name to find previous occupancy
                String historicalKey = String.valueOf(erEntityId) + erRole + erContactName;
                historicalRolesMap.put(historicalKey, er);
            }

            // PERFORMANCE OPTIMIZATION: Initialize collections for efficient processing
            Set<String> namesToProcess = new Set<String>();
            List<Entity_Role__c> rolesToUpdate = new List<Entity_Role__c>();
            Map<Id, Set<String>> rolesToReplaceByEntity = new Map<Id, Set<String>>();
            Map<Id, EntityRequest> requestsByEntityId = new Map<Id, EntityRequest>();

            // TRACKING: Records we've reactivated in this transaction to prevent them from being deactivated
            Set<Id> reactivatedRecordIds = new Set<Id>();

            for (EntityRequest req : requests) {
                // PERFORMANCE OPTIMIZATION: Cache entity ID and record outside inner loop
                Id entityId = req.currentRecord.Id;
                Entities__c currentRecord = req.currentRecord;

                for (Entity_Role_Mapping__mdt m : allMappings) {
                    // PERFORMANCE OPTIMIZATION: Cache field values to avoid repeated field access
                    String entityFieldAPI = m.Entity_Field_API__c;
                    String roleName = m.Role_Name__c;
                    String currentNameVal = (String) currentRecord.get(entityFieldAPI);

                    // PERFORMANCE OPTIMIZATION: Efficient deduplication key generation
                    String activeRoleKey = String.valueOf(entityId) + roleName;
                    Entity_Role__c existingRole = activeRolesMap.get(activeRoleKey);

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

                    // PERFORMANCE OPTIMIZATION: Cache field API names to avoid repeated access
                    String ownershipFieldAPI = m.Ownership_Percentage_Field_API_Name__c;
                    String stateFieldAPI = m.State_of_Residence_Field_API__c;

                    Decimal currentPct = (ownershipFieldAPI != null) ? (Decimal) currentRecord.get(ownershipFieldAPI) : null;
                    String currentState = (stateFieldAPI != null) ? (String) currentRecord.get(stateFieldAPI) : null;

                    // CASE 1: Occupant Changed or New Role
                    if (existingRole == null || existingRole.Contact__r.Name != currentNameVal) {
                        if (historicalRole != null) {
                            // REACTIVATE: Historical person returning to the same role
                            historicalRole.Entity_Role_Status__c = EntityRoleConstants.STATUS_ACTIVE;
                            syncRoleData(historicalRole, currentRecord, m);
                            rolesToUpdate.add(historicalRole);
                            reactivatedRecordIds.add(historicalRole.Id);

                            // Mark the current occupant (who is being replaced) for deactivation
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
                        if (syncRoleData(existingRole, currentRecord, m)) {
                            rolesToUpdate.add(existingRole);
                        }
                    }
                }
            }

            if (!rolesToUpdate.isEmpty())
                update rolesToUpdate;

            if (!rolesToReplaceByEntity.isEmpty()) {
                Map<String, Id> contactMap = findOrCreateContactsScoped(namesToProcess, accountIds, nameToAccountIdMap);

                // Pass the reactivated IDs to ensure they are NOT flipped back to Inactive
                deactivateSpecificRoles(rolesToReplaceByEntity, reactivatedRecordIds);

                createNewRolesSelective(requestsByEntityId.values(), allMappings, contactMap, rolesToReplaceByEntity);
            }
        } catch (Exception e) {
            String errorMessage = e.getMessage();
            if (errorMessage.contains(EntityRoleConstants.DML_ERROR_INVALID_PICKLIST)) {
                errorMessage = EntityRoleConstants.ERROR_INVALID_PICKLIST;
            } else if (errorMessage.contains(EntityRoleConstants.DML_ERROR_REQUIRED_FIELD)) {
                errorMessage = EntityRoleConstants.ERROR_REQUIRED_FIELD;
            }
            throw new EntityRoleException(EntityRoleConstants.ERROR_ENTITY_ROLE_AUTOMATION + errorMessage);
        }
    }

    private static void markRoleForReplacement(Map<Id, Set<String>> replaceMap, Id entityId, String roleName) {
        if (!replaceMap.containsKey(entityId)) {
            replaceMap.put(entityId, new Set<String>());
        }
        replaceMap.get(entityId).add(roleName);
    }

    private static void createNewRolesSelective(List<EntityRequest> requests, List<Entity_Role_Mapping__mdt> mappings, Map<String, Id> contactMap, Map<Id, Set<String>> rolesToReplaceByEntity) {
        // PERFORMANCE OPTIMIZATION: Initialize list for efficient insertions
        List<Entity_Role__c> rolesToInsert = new List<Entity_Role__c>();

        for (EntityRequest req : requests) {
            // PERFORMANCE OPTIMIZATION: Cache entity ID and current record
            Id entityId = req.currentRecord.Id;
            Entities__c currentRecord = req.currentRecord;
            Set<String> rolesNeeded = rolesToReplaceByEntity.get(entityId);

            if (rolesNeeded == null)
                continue;

            for (Entity_Role_Mapping__mdt m : mappings) {
                String roleName = m.Role_Name__c;
                if (!rolesNeeded.contains(roleName))
                    continue;

                String newVal = (String) currentRecord.get(m.Entity_Field_API__c);
                if (String.isNotBlank(newVal) && contactMap.containsKey(newVal)) {
                    Entity_Role__c newRole = new Entity_Role__c(Entity__c = entityId, Contact__c = contactMap.get(newVal), Role__c = roleName, Entity_Role_Status__c = EntityRoleConstants.STATUS_ACTIVE);
                    syncRoleData(newRole, currentRecord, m);
                    rolesToInsert.add(newRole);
                }
            }
        }
        if (!rolesToInsert.isEmpty())
            insert rolesToInsert;
    }

    private static void deactivateSpecificRoles(Map<Id, Set<String>> entityToRoles, Set<Id> skipIds) {
        // PERFORMANCE OPTIMIZATION: Initialize list for efficient updates
        List<Entity_Role__c> toDeactivate = new List<Entity_Role__c>();

        for (Id entityId : entityToRoles.keySet()) {
            Set<String> roles = entityToRoles.get(entityId);
            for (Entity_Role__c er : [
                SELECT Id
                FROM Entity_Role__c
                WHERE Entity__c = :entityId AND Role__c IN :roles AND Entity_Role_Status__c = :EntityRoleConstants.STATUS_ACTIVE
            ]) {
                // Safeguard: Do not deactivate if we just reactivated this specific record
                if (!skipIds.contains(er.Id)) {
                    er.Entity_Role_Status__c = EntityRoleConstants.STATUS_INACTIVE;
                    toDeactivate.add(er);
                }
            }
        }
        if (!toDeactivate.isEmpty())
            update toDeactivate;
    }

    private static Boolean syncRoleData(Entity_Role__c er, Entities__c entity, Entity_Role_Mapping__mdt m) {
        Boolean changed = false;
        Decimal newPct = (m.Ownership_Percentage_Field_API_Name__c != null) ? (Decimal) entity.get(m.Ownership_Percentage_Field_API_Name__c) : null;
        String newState = (m.State_of_Residence_Field_API__c != null) ? (String) entity.get(m.State_of_Residence_Field_API__c) : null;

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
        // PERFORMANCE OPTIMIZATION: Initialize map for efficient lookups
        Map<String, Id> contactMap = new Map<String, Id>();

        for (Contact con : [SELECT Id, Name FROM Contact WHERE Name IN :names AND AccountId IN :accountIds WITH SECURITY_ENFORCED]) {
            contactMap.put(con.Name, con.Id);
        }

        Set<String> remainingNames = new Set<String>(names);
        remainingNames.removeAll(contactMap.keySet());

        // PERFORMANCE OPTIMIZATION: Early exit if all contacts found
        if (remainingNames.isEmpty()) {
            return contactMap;
        }

        for (Contact con : [SELECT Id, Name FROM Contact WHERE Name IN :remainingNames WITH SECURITY_ENFORCED]) {
            contactMap.put(con.Name, con.Id);
        }

        remainingNames.removeAll(contactMap.keySet());

        // PERFORMANCE OPTIMIZATION: Early exit if all contacts found
        if (remainingNames.isEmpty()) {
            return contactMap;
        }

        // PERFORMANCE OPTIMIZATION: Initialize list for new contacts
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
}
