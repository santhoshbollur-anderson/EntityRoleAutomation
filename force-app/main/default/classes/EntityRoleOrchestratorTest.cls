/**
 * @description       : 
 * @author            :  Santhosh Bollur (Anderson SSC)
 * @group             : 
 * @last modified on  : 05-12-2026
 * @last modified by  :  Santhosh Bollur (Anderson SSC)
**/
@IsTest
private class EntityRoleOrchestratorTest {
    @TestSetup
    static void setupData() {
        // Create a test contact to test "Existing Contact" matching logic
        Contact existingCon = new Contact(FirstName = 'Existing', LastName = 'Manager');
        insert existingCon;
    }

    @IsTest
    static void testLLCManagerChange() {
        Id llcRtId = Schema.SObjectType.Entities__c.getRecordTypeInfosByDeveloperName().get('Limited_Liability_Company_LLC').getRecordTypeId();

        Entities__c testEntity = new Entities__c(Name = 'Test LLC', RecordTypeId = llcRtId, Manager_1__c = 'Initial Manager');
        insert testEntity;

        Entities__c updatedEntity = testEntity.clone(true, true, true, true);
        updatedEntity.Manager_1__c = 'Existing Manager';

        // Use the explicit inner class reference
        EntityRoleOrchestrator.EntityRequest req = new EntityRoleOrchestrator.EntityRequest();
        req.currentRecord = updatedEntity;
        req.priorRecord = testEntity;

        Test.startTest();
        EntityRoleOrchestrator.processRoles(new List<EntityRoleOrchestrator.EntityRequest>{ req });
        Test.stopTest();

        List<Entity_Role__c> roles = [
            SELECT Id
            FROM Entity_Role__c
            WHERE Entity__c = :testEntity.Id AND Entity_Role_Status__c = 'Active'
        ];
        System.assert(roles.size() > 0, 'An active Entity Role should have been created');
    }

    @IsTest
    static void testNewContactCreation() {
        Id corpRtId = Schema.SObjectType.Entities__c.getRecordTypeInfosByDeveloperName().get('Corporation').getRecordTypeId();

        Entities__c testEntity = new Entities__c(Name = 'Test Corp', RecordTypeId = corpRtId, President__c = 'Brand New Person');
        insert testEntity;

        EntityRoleOrchestrator.EntityRequest req = new EntityRoleOrchestrator.EntityRequest();
        req.currentRecord = testEntity;
        req.priorRecord = null;

        Test.startTest();
        EntityRoleOrchestrator.processRoles(new List<EntityRoleOrchestrator.EntityRequest>{ req });
        Test.stopTest();

        Contact newCon = [
            SELECT Id
            FROM Contact
            WHERE LastName = 'Brand New Person'
            LIMIT 1
        ];
        System.assertNotEquals(null, newCon, 'A new contact should have been created');
    }

    @IsTest
    static void testLPPartnerChange() {
        Id lpRtId = Schema.SObjectType.Entities__c.getRecordTypeInfosByDeveloperName().get('Limited_Partnership_LP').getRecordTypeId();

        Entities__c testEntity = new Entities__c(Name = 'Test LP', RecordTypeId = lpRtId, Limited_Partner_1__c = 'Partner A');
        insert testEntity;

        // Manually create an active role to test deactivation logic
        Contact conA = new Contact(LastName = 'Partner A');
        insert conA;
        insert new Entity_Role__c(Entity__c = testEntity.Id, Contact__c = conA.Id, Role__c = 'LP Partner', Entity_Role_Status__c = 'Active');

        Entities__c updatedEntity = testEntity.clone(true, true, true, true);
        updatedEntity.Limited_Partner_1__c = 'Partner B';

        EntityRoleOrchestrator.EntityRequest req = new EntityRoleOrchestrator.EntityRequest();
        req.currentRecord = updatedEntity;
        req.priorRecord = testEntity;

        Test.startTest();
        EntityRoleOrchestrator.processRoles(new List<EntityRoleOrchestrator.EntityRequest>{ req });
        Test.stopTest();

        Entity_Role__c oldRole = [
            SELECT Entity_Role_Status__c
            FROM Entity_Role__c
            WHERE Contact__c = :conA.Id
            LIMIT 1
        ];
        System.assertEquals('Inactive', oldRole.Entity_Role_Status__c, 'Old role should be deactivated');
    }
}