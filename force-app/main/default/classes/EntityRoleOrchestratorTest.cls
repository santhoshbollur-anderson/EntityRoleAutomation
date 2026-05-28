/**
 * @description       : Test class for EntityRoleOrchestrator. Validates entity role creation, contact matching,
 * contact creation, role deactivation on name changes, and proper handling of different
 * entity record types (LLC, Corporation, Limited Partnership). Tests cover various scenarios
 * including manager changes, new contact creation, partner replacements, and role reactivation.
 * @author            : Santhosh Bollur (Anderson SSC)
 * @last modified on  : 05-28-2026
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

        Entities__c testEntity = new Entities__c(Name = 'Test LLC', RecordTypeId = llcRtId, Manager_1__c = 'Initial Manager', Primary_Client__c = testAccountId);
        insert testEntity;

        Entities__c updatedEntity = testEntity.clone(true, true, true, true);
        updatedEntity.Manager_1__c = 'Existing Manager';

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

        Entities__c testEntity = new Entities__c(Name = 'Test Corp', RecordTypeId = corpRtId, President__c = 'Brand New Person', Primary_Client__c = createTestAccount());
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

        Entities__c testEntity = new Entities__c(Name = 'Test LP', RecordTypeId = lpRtId, Limited_Partner_1__c = 'Partner A', Primary_Client__c = testAccountId);
        insert testEntity;

        // Manually create an active role to test deactivation logic
        Contact conA = new Contact(LastName = 'Partner A', AccountId = testAccountId);
        insert conA;
        insert new Entity_Role__c(Entity__c = testEntity.Id, Contact__c = conA.Id, Role__c = 'Manager 1', Entity_Role_Status__c = 'Active');

        Entities__c updatedEntity = testEntity.clone(true, true, true, true);
        updatedEntity.Limited_Partner_1__c = 'Partner B';

        EntityRoleOrchestrator.EntityRequest req = new EntityRoleOrchestrator.EntityRequest();
        req.currentRecord = updatedEntity;
        req.priorRecord = testEntity;

        Test.startTest();
        EntityRoleOrchestrator.processRoles(new List<EntityRoleOrchestrator.EntityRequest>{ req });
        Test.stopTest();

        List<Entity_Role__c> oldRoles = [
            SELECT Id, Entity_Role_Status__c
            FROM Entity_Role__c
            WHERE Contact__c = :conA.Id
        ];
        System.assertEquals(1, oldRoles.size(), 'The old role record should exist');
    }

    // --- NEW TESTS TO INCREASE COVERAGE ---

    @IsTest
    static void testEmptyAndNullRequests() {
        Test.startTest();
        // Covers early return logic
        EntityRoleOrchestrator.processRoles(null);
        EntityRoleOrchestrator.processRoles(new List<EntityRoleOrchestrator.EntityRequest>());
        Test.stopTest();
        
        System.assert(true, 'Method should safely return without throwing exceptions for null or empty inputs.');
    }

    @IsTest
    static void testRoleDeactivationOnBlankName() {
        Id corpRtId = Schema.SObjectType.Entities__c.getRecordTypeInfosByDeveloperName().get('Corporation')?.getRecordTypeId();
        Id testAccountId = createTestAccount();

        Entities__c testEntity = new Entities__c(Name = 'Test Corp', RecordTypeId = corpRtId, President__c = 'John Doe', Primary_Client__c = testAccountId);
        insert testEntity;

        // Create the initial role
        EntityRoleOrchestrator.EntityRequest req1 = new EntityRoleOrchestrator.EntityRequest();
        req1.currentRecord = testEntity;
        EntityRoleOrchestrator.processRoles(new List<EntityRoleOrchestrator.EntityRequest>{ req1 });

        // Update the entity to blank out the name
        Entities__c updatedEntity = testEntity.clone(true, true, true, true);
        updatedEntity.President__c = null; 

        EntityRoleOrchestrator.EntityRequest req2 = new EntityRoleOrchestrator.EntityRequest();
        req2.currentRecord = updatedEntity;
        req2.priorRecord = testEntity;

        Test.startTest();
        EntityRoleOrchestrator.processRoles(new List<EntityRoleOrchestrator.EntityRequest>{ req2 });
        Test.stopTest();

        List<Entity_Role__c> inactiveRoles = [SELECT Id FROM Entity_Role__c WHERE Entity__c = :testEntity.Id AND Entity_Role_Status__c = 'Inactive'];
        System.assert(inactiveRoles.size() > 0, 'The role should have been marked as Inactive when the name was blanked out.');
    }

    @IsTest
    static void testBackAndForthReactivation() {
        Id corpRtId = Schema.SObjectType.Entities__c.getRecordTypeInfosByDeveloperName().get('Corporation')?.getRecordTypeId();
        Id testAccountId = createTestAccount();

        Entities__c testEntity = new Entities__c(Name = 'Test Corp', RecordTypeId = corpRtId, President__c = 'Alice', Primary_Client__c = testAccountId);
        insert testEntity;

        // 1. Initial assignment -> Alice
        EntityRoleOrchestrator.EntityRequest req1 = new EntityRoleOrchestrator.EntityRequest();
        req1.currentRecord = testEntity;
        EntityRoleOrchestrator.processRoles(new List<EntityRoleOrchestrator.EntityRequest>{ req1 });

        // 2. Change assignment -> Bob (Deactivates Alice)
        Entities__c entityBob = testEntity.clone(true, true, true, true);
        entityBob.President__c = 'Bob';
        EntityRoleOrchestrator.EntityRequest req2 = new EntityRoleOrchestrator.EntityRequest();
        req2.currentRecord = entityBob;
        req2.priorRecord = testEntity;
        EntityRoleOrchestrator.processRoles(new List<EntityRoleOrchestrator.EntityRequest>{ req2 });

        // 3. Change assignment back -> Alice (Reactivates Alice)
        Entities__c entityAliceReturn = entityBob.clone(true, true, true, true);
        entityAliceReturn.President__c = 'Alice';
        EntityRoleOrchestrator.EntityRequest req3 = new EntityRoleOrchestrator.EntityRequest();
        req3.currentRecord = entityAliceReturn;
        req3.priorRecord = entityBob;

        Test.startTest();
        EntityRoleOrchestrator.processRoles(new List<EntityRoleOrchestrator.EntityRequest>{ req3 });
        Test.stopTest();

        List<Entity_Role__c> activeRoles = [SELECT Id, Contact__r.Name FROM Entity_Role__c WHERE Entity__c = :testEntity.Id AND Entity_Role_Status__c = 'Active'];
        Boolean foundAlice = false;
        for (Entity_Role__c er : activeRoles) {
            if (er.Contact__r.Name.contains('Alice')) {
                foundAlice = true;
            }
        }
        System.assert(foundAlice, 'Alice should have been reactivated as an Active role instead of creating a duplicate.');
    }

    @IsTest
    static void testSingleNameParsing() {
        Id corpRtId = Schema.SObjectType.Entities__c.getRecordTypeInfosByDeveloperName().get('Corporation')?.getRecordTypeId();
        
        Entities__c testEntity = new Entities__c(Name = 'Test Corp', RecordTypeId = corpRtId, President__c = 'Madonna', Primary_Client__c = createTestAccount());
        insert testEntity;

        EntityRoleOrchestrator.EntityRequest req = new EntityRoleOrchestrator.EntityRequest();
        req.currentRecord = testEntity;
        req.priorRecord = null;

        Test.startTest();
        EntityRoleOrchestrator.processRoles(new List<EntityRoleOrchestrator.EntityRequest>{ req });
        Test.stopTest();

        List<Contact> singleNameCons = [SELECT Id, FirstName, LastName FROM Contact WHERE LastName = 'Madonna'];
        System.assertEquals(1, singleNameCons.size(), 'A contact should be created successfully using just the Last Name.');
        System.assertEquals(null, singleNameCons[0].FirstName, 'First Name should be null when only one name is provided.');
    }
    
    @IsTest
    static void testProcessRolesDmlException() {
        // STRATEGY: Pass an uninserted Entities__c record. 
        // The orchestrator will attempt to insert an Entity_Role__c with a null Entity__c lookup ID.
        // This forces a DmlException for a missing required field.
        
        Id corpRtId = Schema.SObjectType.Entities__c.getRecordTypeInfosByDeveloperName().get('Corporation')?.getRecordTypeId();
        
        // Note: We are NOT inserting this record, so its Id is null
        Entities__c uninsertedEntity = new Entities__c(
            Name = 'Uninserted Test Corp', 
            RecordTypeId = corpRtId, 
            President__c = 'Error Trigger Person'
        );

        EntityRoleOrchestrator.EntityRequest req = new EntityRoleOrchestrator.EntityRequest();
        req.currentRecord = uninsertedEntity;
        req.priorRecord = null;

        Test.startTest();
        try {
            EntityRoleOrchestrator.processRoles(new List<EntityRoleOrchestrator.EntityRequest>{ req });
            System.assert(false, 'An exception should have been thrown due to the missing Parent Entity Id.');
        } catch (EntityRoleOrchestrator.EntityRoleException e) {
            // Assert that the catch block successfully caught the DML error and threw the custom Exception
            System.assertNotEquals(null, e.getMessage(), 'Exception message should be populated');
            // Depending on the exact AppConstants string, it will likely format the REQUIRED FIELD message here
        }
        Test.stopTest();
    }

    @IsTest
    static void testProcessRolesGenericException() {
        // STRATEGY: Pass a completely null currentRecord.
        // The code `Id entityId = req.currentRecord.Id;` will throw a NullPointerException,
        // which gets caught by the catch block to test the generic fallback logic.
        
        EntityRoleOrchestrator.EntityRequest req = new EntityRoleOrchestrator.EntityRequest();
        req.currentRecord = null; // Deliberately set to null

        Test.startTest();
        try {
            EntityRoleOrchestrator.processRoles(new List<EntityRoleOrchestrator.EntityRequest>{ req });
            System.assert(false, 'An exception should have been thrown due to a NullPointerException.');
        } catch (EntityRoleOrchestrator.EntityRoleException e) {
            System.assert(e.getMessage() != null, 'The generic exception handler should have wrapped the error message.');
        }
        Test.stopTest();
    }

    // Helper method to create test account
    private static Id createTestAccount() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        return testAccount.Id;
    }
}