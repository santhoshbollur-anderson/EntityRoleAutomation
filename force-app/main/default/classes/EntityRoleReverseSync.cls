/**
 * @description       : Syncs Entity Role data back to Entity record fields based on Custom Metadata mappings.
 *                      When a new Entity Role becomes active, this class updates the corresponding
 *                      Entity fields (contact name, state, ownership percentage) based on the role mapping.
 * @author            : Santhosh Bollur (Anderson SSC)
 * @last modified on  : 05-29-2026
 **/
public with sharing class EntityRoleReverseSync {
    public class EntityRoleSyncException extends Exception {
    }

    // Cache for Custom Metadata to avoid repeated SOQL queries
    private static Map<String, Entity_Role_Mapping__mdt> cachedMappings;

    public class SyncRequest {
        @InvocableVariable(label='Entity Role Record Id' required=true description='The ID of the newly active Entity Role record')
        public String entityRoleId;
    }

    /**
     * @description Retrieves and caches Entity Role Mappings for reuse
     * @return Map<String, Entity_Role_Mapping__mdt> Map keyed by Role Name
     **/
    private static Map<String, Entity_Role_Mapping__mdt> getMappings() {
        if (cachedMappings == null) {
            cachedMappings = new Map<String, Entity_Role_Mapping__mdt>();
            for (Entity_Role_Mapping__mdt mapping : [
                SELECT 
                    Entity_Field_API__c, 
                    Role_Name__c, 
                    Ownership_Percentage_Field_API_Name__c, 
                    State_of_Residence_Field_API__c
                FROM Entity_Role_Mapping__mdt
                WHERE Entity_Field_API__c != null
            ]) {
                cachedMappings.put(mapping.Role_Name__c, mapping);
            }
        }
        return cachedMappings;
    }

    /**
     * @description Main invocable method to sync Entity Role data back to Entity record
     * @param requests List of SyncRequest containing Entity Role IDs
     **/
    @InvocableMethod(label='Sync Entity Role to Entity' category='Entity Role' description='Updates Entity record fields based on the active Entity Role and metadata mappings')
    public static void syncRoleToEntity(List<SyncRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        try {
            Set<Id> entityRoleIds = new Set<Id>();
            for (SyncRequest req : requests) {
                if (String.isNotBlank(req.entityRoleId)) {
                    entityRoleIds.add(req.entityRoleId);
                }
            }

            if (entityRoleIds.isEmpty()) {
                return;
            }

            // Query Entity Role records with related Contact information
            List<Entity_Role__c> entityRoles = [
                SELECT 
                    Id,
                    Entity__c,
                    Role__c,
                    Contact__c,
                    Contact__r.Name,
                    ShareHolder_Ownership__c,
                    State_of_Residence__c,
                    Entity_Role_Status__c
                FROM Entity_Role__c
                WHERE Id IN :entityRoleIds
                AND Entity_Role_Status__c = :AppConstants.STATUS_ACTIVE
                WITH SECURITY_ENFORCED
            ];

            if (entityRoles.isEmpty()) {
                return;
            }

            // Get metadata mappings
            Map<String, Entity_Role_Mapping__mdt> mappingsMap = getMappings();

            // Group Entity Role records by Entity Id for efficient processing
            Map<Id, List<Entity_Role__c>> rolesByEntity = new Map<Id, List<Entity_Role__c>>();
            for (Entity_Role__c role : entityRoles) {
                if (!rolesByEntity.containsKey(role.Entity__c)) {
                    rolesByEntity.put(role.Entity__c, new List<Entity_Role__c>());
                }
                rolesByEntity.get(role.Entity__c).add(role);
            }

            // Query Entity records
            Set<Id> entityIds = rolesByEntity.keySet();
            Map<Id, Entities__c> entitiesMap = new Map<Id, Entities__c>([
                SELECT Id
                FROM Entities__c
                WHERE Id IN :entityIds
                WITH SECURITY_ENFORCED
            ]);

            // Update Entity records based on mappings
            List<Entities__c> entitiesToUpdate = new List<Entities__c>();
            
            for (Id entityId : rolesByEntity.keySet()) {
                Entities__c entity = entitiesMap.get(entityId);
                if (entity == null) {
                    continue;
                }

                Boolean entityModified = false;

                for (Entity_Role__c role : rolesByEntity.get(entityId)) {
                    Entity_Role_Mapping__mdt mapping = mappingsMap.get(role.Role__c);
                    
                    if (mapping == null) {
                        continue;
                    }

                    // Update contact name field
                    if (String.isNotBlank(mapping.Entity_Field_API__c)) {
                        String contactName = role.Contact__r?.Name;
                        if (String.isNotBlank(contactName)) {
                            entity.put(mapping.Entity_Field_API__c, contactName);
                            entityModified = true;
                        }
                    }

                    // Update ownership percentage field
                    if (String.isNotBlank(mapping.Ownership_Percentage_Field_API_Name__c)) {
                        Decimal ownership = role.ShareHolder_Ownership__c;
                        entity.put(mapping.Ownership_Percentage_Field_API_Name__c, ownership);
                        entityModified = true;
                    }

                    // Update state of residence field
                    if (String.isNotBlank(mapping.State_of_Residence_Field_API__c)) {
                        String state = role.State_of_Residence__c;
                        entity.put(mapping.State_of_Residence_Field_API__c, state);
                        entityModified = true;
                    }
                }

                if (entityModified) {
                    entitiesToUpdate.add(entity);
                }
            }

            if (!entitiesToUpdate.isEmpty()) {
                update entitiesToUpdate;
            }

        } catch (Exception e) {
            throw new EntityRoleSyncException(
                'Error syncing Entity Role to Entity: ' + e.getMessage()
            );
        }
    }
}