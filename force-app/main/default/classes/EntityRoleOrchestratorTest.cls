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
        Id llcRtId = Schema.SObjectType.Entities__c.getRecordTypeInfosByDeveloperName().get('Limited_Liability_Company_LLC')?.getRecordTypeId();
        Id testAccountId = createTestAccount();
        
        // Update the existing contact to belong to the same account
        Contact existingContact = [SELECT Id FROM Contact WHERE FirstName = 'Existing' AND LastName = 'Manager' LIMIT 1];
        existingContact.AccountId = testAccountId;
        update existingContact;
        
        Entities__c testEntity = new Entities__c(
            Name = 'Test LLC', 
            RecordTypeId = llcRtId, 
            Manager_1__c = 'Initial Manager',
            Primary_Client__c = testAccountId
        );
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
        Id corpRtId = Schema.SObjectType.Entities__c.getRecordTypeInfosByDeveloperName().get('Corporation')?.getRecordTypeId();

        Entities__c testEntity = new Entities__c(
            Name = 'Test Corp', 
            RecordTypeId = corpRtId, 
            President__c = 'Brand New Person',
            Primary_Client__c = createTestAccount()
        );
        insert testEntity;

        EntityRoleOrchestrator.EntityRequest req = new EntityRoleOrchestrator.EntityRequest();
        req.currentRecord = testEntity;
        req.priorRecord = null;

        Test.startTest();
        EntityRoleOrchestrator.processRoles(new List<EntityRoleOrchestrator.EntityRequest>{ req });
        Test.stopTest();

        List<Contact> newCons = [
            SELECT Id
            FROM Contact
            WHERE Name LIKE '%Brand New Person%'
        ];
        System.assertEquals(1, newCons.size(), 'A new contact should have been created');
    }

    @IsTest
    static void testLPPartnerChange() {
        Id lpRtId = Schema.SObjectType.Entities__c.getRecordTypeInfosByDeveloperName().get('Limited_Partnership_LP')?.getRecordTypeId();
        Id testAccountId = createTestAccount();

        Entities__c testEntity = new Entities__c(
            Name = 'Test LP', 
            RecordTypeId = lpRtId, 
            Limited_Partner_1__c = 'Partner A',
            Primary_Client__c = testAccountId
        );
        insert testEntity;

        // Manually create an active role to test deactivation logic
        Contact conA = new Contact(LastName = 'Partner A', AccountId = testAccountId);
        insert conA;
        insert new Entity_Role__c(
            Entity__c = testEntity.Id, 
            Contact__c = conA.Id, 
            Role__c = 'Manager 1',
            Entity_Role_Status__c = 'Active'
        );

        Entities__c updatedEntity = testEntity.clone(true, true, true, true);
        updatedEntity.Limited_Partner_1__c = 'Partner B';

        EntityRoleOrchestrator.EntityRequest req = new EntityRoleOrchestrator.EntityRequest();
        req.currentRecord = updatedEntity;
        req.priorRecord = testEntity;

        Test.startTest();
        EntityRoleOrchestrator.processRoles(new List<EntityRoleOrchestrator.EntityRequest>{ req });
        Test.stopTest();

        List<Entity_Role__c> oldRoles = [
            SELECT Entity_Role_Status__c
            FROM Entity_Role__c
            WHERE Contact__c = :conA.Id
        ];
        System.assertEquals(1, oldRoles.size(), 'The old role record should exist');
        System.assertEquals('Inactive', oldRoles[0].Entity_Role_Status__c, 'Old role should be deactivated');
    }
    
    // Helper method to create test account
    private static Id createTestAccount() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        return testAccount.Id;
    }
}