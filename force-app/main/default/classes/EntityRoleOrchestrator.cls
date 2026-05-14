/**
 * @description       : 
 * @author            :  Santhosh Bollur (Anderson SSC)
 * @group             : 
 * @last modified on  : 05-12-2026
 * @last modified by  :  Santhosh Bollur (Anderson SSC)
**/

public with sharing class EntityRoleOrchestrator {
    public class EntityRoleException extends Exception {
    }
    
    public static final Id CONTACT_STANDARD_RT_ID = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('Standard')?.getRecordTypeId();

    public class EntityRequest {
        @InvocableVariable(label='Current Entity' required=true)
        public Entities__c currentRecord;
        @InvocableVariable(label='Prior Entity')
        public Entities__c priorRecord;
    }

    @InvocableMethod(label='Execute Entity Role Logic' category='Entities')
    public static void processRoles(List<EntityRequest> requests) {
        if (requests == null || requests.isEmpty())
            return;

        try {
            List<Entity_Role_Mapping__mdt> allMappings = [
                SELECT Entity_Field_API__c, Role_Name__c, Ownership_Percentage_Field_API_Name__c, State_of_Residence_Field_API__c
                FROM Entity_Role_Mapping__mdt
            ];

            Set<Id> accountIds = new Set<Id>();
            Set<Id> entityIds = new Set<Id>();
            Map<String, Id> nameToAccountIdMap = new Map<String, Id>();

            for (EntityRequest req : requests) {
                entityIds.add(req.currentRecord.Id);
                if (req.currentRecord.Primary_Client__c != null) {
                    accountIds.add(req.currentRecord.Primary_Client__c);
                    for (Entity_Role_Mapping__mdt m : allMappings) {
                        String nameVal = (String) req.currentRecord.get(m.Entity_Field_API__c);
                        if (String.isNotBlank(nameVal))
                            nameToAccountIdMap.put(nameVal, req.currentRecord.Primary_Client__c);
                    }
                }
            }

            Map<String, Entity_Role__c> existingRolesMap = new Map<String, Entity_Role__c>();
            for (Entity_Role__c er : [
                SELECT Id, Entity__c, Role__c, Contact__r.Name, ShareHolder_Ownership__c, State_of_Residence__c
                FROM Entity_Role__c
                WHERE Entity__c IN :entityIds AND Entity_Role_Status__c = 'Active'
            ]) {
                existingRolesMap.put(er.Entity__c + er.Role__c, er);
            }

            Set<String> namesToProcess = new Set<String>();
            List<Entity_Role__c> rolesToUpdate = new List<Entity_Role__c>();

            // TRACKING: Which specific mappings per Entity ID need to be created/replaced/deactivated
            Map<Id, Set<String>> rolesToReplaceByEntity = new Map<Id, Set<String>>();
            // TRACKING: Unique list of requests that have at least one replacement
            Map<Id, EntityRequest> requestsByEntityId = new Map<Id, EntityRequest>();

            for (EntityRequest req : requests) {
                for (Entity_Role_Mapping__mdt m : allMappings) {
                    String currentNameVal = (String) req.currentRecord.get(m.Entity_Field_API__c);
                    Entity_Role__c existingRole = existingRolesMap.get(req.currentRecord.Id + m.Role_Name__c);

                    // HANDLE BLANK FIELDS: If name is cleared, deactivate the existing role
                    if (String.isBlank(currentNameVal)) {
                        if (existingRole != null) {
                            if (!rolesToReplaceByEntity.containsKey(req.currentRecord.Id)) {
                                rolesToReplaceByEntity.put(req.currentRecord.Id, new Set<String>());
                            }
                            rolesToReplaceByEntity.get(req.currentRecord.Id).add(m.Role_Name__c);
                        }
                        continue;
                    }

                    Decimal currentPct = (m.Ownership_Percentage_Field_API_Name__c != null) ? (Decimal) req.currentRecord.get(m.Ownership_Percentage_Field_API_Name__c) : null;
                    String currentState = (m.State_of_Residence_Field_API__c != null) ? (String) req.currentRecord.get(m.State_of_Residence_Field_API__c) : null;

                    // CASE 1: New Role or Name Change
                    if (existingRole == null || existingRole.Contact__r.Name != currentNameVal) {
                        namesToProcess.add(currentNameVal);
                        requestsByEntityId.put(req.currentRecord.Id, req);

                        if (!rolesToReplaceByEntity.containsKey(req.currentRecord.Id)) {
                            rolesToReplaceByEntity.put(req.currentRecord.Id, new Set<String>());
                        }
                        rolesToReplaceByEntity.get(req.currentRecord.Id).add(m.Role_Name__c);
                    }
                    // CASE 2: Same Person, Metadata Change
                    else if (existingRole.ShareHolder_Ownership__c != currentPct || existingRole.State_of_Residence__c != currentState) {
                        if (syncRoleData(existingRole, req.currentRecord, m)) {
                            rolesToUpdate.add(existingRole);
                        }
                    }
                }
            }

            if (!rolesToUpdate.isEmpty())
                update rolesToUpdate;

            if (!rolesToReplaceByEntity.isEmpty()) {
                Map<String, Id> contactMap = findOrCreateContactsScoped(namesToProcess, accountIds, nameToAccountIdMap);

                deactivateSpecificRoles(rolesToReplaceByEntity);

                // Creates roles ONLY for the flagged mappings where a name exists
                createNewRolesSelective(requestsByEntityId.values(), allMappings, contactMap, rolesToReplaceByEntity);
            }
        }  catch (Exception e) {
    String errorMessage = e.getMessage();
    
    // Check for Picklist Validation errors
    if (errorMessage.contains('INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST')) {
        // Extract the value and field name for a friendlier message
        errorMessage = 'One of the State values entered is not valid for the "State of Residence" picklist. Please ensure you are using standard State abbreviations or names defined in Salesforce.';
    } 
    // Check for Required Field errors
    else if (errorMessage.contains('REQUIRED_FIELD_MISSING')) {
        errorMessage = 'A required field is missing. Please check that all Name and Role fields are populated.';
    }
    
    // Throw the cleaned-up message
    throw new EntityRoleException('Entity Role Automation Failed: ' + errorMessage);
}
    }

    private static void createNewRolesSelective(List<EntityRequest> requests, List<Entity_Role_Mapping__mdt> mappings, Map<String, Id> contactMap, Map<Id, Set<String>> rolesToReplaceByEntity) {
        List<Entity_Role__c> rolesToInsert = new List<Entity_Role__c>();
        for (EntityRequest req : requests) {
            Set<String> rolesNeeded = rolesToReplaceByEntity.get(req.currentRecord.Id);
            if (rolesNeeded == null)
                continue;

            for (Entity_Role_Mapping__mdt m : mappings) {
                if (!rolesNeeded.contains(m.Role_Name__c))
                    continue;

                String newVal = (String) req.currentRecord.get(m.Entity_Field_API__c);
                if (String.isNotBlank(newVal) && contactMap.containsKey(newVal)) {
                    Entity_Role__c newRole = new Entity_Role__c(Entity__c = req.currentRecord.Id, Contact__c = contactMap.get(newVal), Role__c = m.Role_Name__c, Entity_Role_Status__c = 'Active');
                    if (String.isNotBlank(m.Ownership_Percentage_Field_API_Name__c)) {
                        newRole.ShareHolder_Ownership__c = (Decimal) req.currentRecord.get(m.Ownership_Percentage_Field_API_Name__c);
                    }
                    if (String.isNotBlank(m.State_of_Residence_Field_API__c)) {
                        newRole.State_of_Residence__c = (String) req.currentRecord.get(m.State_of_Residence_Field_API__c);
                    }
                    rolesToInsert.add(newRole);
                }
            }
        }
        if (!rolesToInsert.isEmpty())
            insert rolesToInsert;
    }

    private static void deactivateSpecificRoles(Map<Id, Set<String>> entityToRoles) {
        List<Entity_Role__c> toDeactivate = new List<Entity_Role__c>();
        for (Id entityId : entityToRoles.keySet()) {
            Set<String> roles = entityToRoles.get(entityId);
            for (Entity_Role__c er : [
                SELECT Id
                FROM Entity_Role__c
                WHERE Entity__c = :entityId AND Role__c IN :roles AND Entity_Role_Status__c = 'Active'
            ]) {
                er.Entity_Role_Status__c = 'Inactive';
                toDeactivate.add(er);
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
        Map<String, Id> contactMap = new Map<String, Id>();
        for (Contact con : [
            SELECT Id, Name
            FROM Contact
            WHERE Name IN :names AND AccountId IN :accountIds
            WITH SECURITY_ENFORCED
        ]) {
            contactMap.put(con.Name, con.Id);
        }
        Set<String> remainingNames = new Set<String>(names);
        remainingNames.removeAll(contactMap.keySet());
        if (!remainingNames.isEmpty()) {
            for (Contact con : [
                SELECT Id, Name
                FROM Contact
                WHERE Name IN :remainingNames
                WITH SECURITY_ENFORCED
            ]) {
                contactMap.put(con.Name, con.Id);
            }
        }
        remainingNames.removeAll(contactMap.keySet());
        if (!remainingNames.isEmpty()) {
            List<Contact> newContacts = new List<Contact>();
            for (String fullName : remainingNames) {
                if (String.isBlank(fullName))
                    continue;
                Contact c = parseName(fullName);
                c.AccountId = nameToAccountIdMap.get(fullName);
                c.RecordTypeId = CONTACT_STANDARD_RT_ID;
                newContacts.add(c);
            }
            if (!newContacts.isEmpty()) {
                insert newContacts;
                for (Contact con : [
                    SELECT Id, Name
                    FROM Contact
                    WHERE Id IN :newContacts
                ]) {
                    contactMap.put(con.Name, con.Id);
                }
            }
        }
        return contactMap;
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