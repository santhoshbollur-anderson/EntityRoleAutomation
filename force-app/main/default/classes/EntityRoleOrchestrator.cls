/**
 * @description       : Orchestrates the creation, update, and deactivation of Entity Role records based on
 *                      Entity record changes. Handles contact lookup/creation, role mapping from custom metadata,
 *                      and maintains data integrity for ownership percentages and state of residence fields.
 *                      Invoked via Flow to automate Entity Role management.
 * @author            :  Santhosh Bollur (Anderson SSC)
 * @group             :
 * @last modified on  : 05-14-2026
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

    /**
     * @description Main invocable method that processes Entity requests to create, update, or deactivate Entity Roles.
     *              Compares current and prior Entity records to determine required changes, handles contact lookup/creation,
     *              and maintains role data integrity including ownership percentages and state of residence.
     * @author  Santhosh Bollur (Anderson SSC) | 05-14-2026
     * @param requests List of EntityRequest wrapper objects containing current and prior Entity records
     **/
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
        } catch (Exception e) {
            String errorMessage = e.getMessage();
            if (errorMessage.contains(EntityRoleConstants.DML_ERROR_INVALID_PICKLIST)) {
                errorMessage = EntityRoleConstants.ERROR_INVALID_PICKLIST;
            } else if (errorMessage.contains(EntityRoleConstants.DML_ERROR_REQUIRED_FIELD)) {
                errorMessage = EntityRoleConstants.ERROR_REQUIRED_FIELD;
            }

            // Throw the cleaned-up message
            throw new EntityRoleException(EntityRoleConstants.ERROR_ENTITY_ROLE_AUTOMATION + errorMessage);
        }
    }

    /**
     * @description Creates new Entity Role records selectively based on the roles that need to be replaced.
     *              Only processes mappings flagged for replacement and validates contact existence before insertion.
     *              Populates role fields including ownership percentage and state of residence from Entity record.
     * @author  Santhosh Bollur (Anderson SSC) | 05-14-2026
     * @param requests List of EntityRequest objects containing current Entity records
     * @param mappings List of all Entity Role Mapping custom metadata records
     * @param contactMap Map of contact names to Contact IDs for role assignment
     * @param rolesToReplaceByEntity Map of Entity IDs to sets of role names that need to be created/replaced
     **/
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

    /**
     * @description Deactivates specific Entity Role records by setting their status to 'Inactive'.
     *              Queries for active roles matching the Entity IDs and role names provided, then updates their status.
     *              Used when a role holder changes or a name field is cleared on the Entity record.
     * @author  Santhosh Bollur (Anderson SSC) | 05-14-2026
     * @param entityToRoles Map of Entity IDs to sets of role names that need to be deactivated
     **/
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

    /**
     * @description Synchronizes Entity Role data when the same person remains in a role but metadata changes.
     *              Updates ownership percentage and/or state of residence fields if values differ from current Entity record.
     *              Returns true if any changes were made, indicating the role needs to be updated.
     * @author  Santhosh Bollur (Anderson SSC) | 05-14-2026
     * @param er The existing Entity Role record to potentially update
     * @param entity The current Entity record with new field values
     * @param m The Entity Role Mapping metadata record defining which fields to sync
     * @return Boolean True if any field was updated, false if no changes were needed
     **/
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

    /**
     * @description Finds existing contacts or creates new ones for the provided names. First searches within specified accounts,
     *              then searches globally, and finally creates new Contact records for any remaining names not found.
     *              Ensures contacts are properly associated with accounts and have the Standard record type.
     * @author  Santhosh Bollur (Anderson SSC) | 05-14-2026
     * @param names Set of contact names to find or create
     * @param accountIds Set of Account IDs to search within for existing contacts
     * @param nameToAccountIdMap Map linking names to their associated Account IDs for new contact creation
     * @return Map<String, Id> Map of contact names to Contact record IDs
     **/
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

    /**
     * @description Parses a full name string into a Contact record with FirstName and LastName fields.
     *              Handles single-word names (LastName only) and multi-word names (first word as FirstName, remaining as LastName).
     *              Trims whitespace and splits on spaces to separate name components.
     * @author  Santhosh Bollur (Anderson SSC) | 05-14-2026
     * @param fullName The complete name string to parse (e.g., "John Smith" or "Smith")
     * @return Contact A new Contact record with FirstName and LastName populated (not inserted)
     **/
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
