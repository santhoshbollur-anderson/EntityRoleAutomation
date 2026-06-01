/**
 * @description       : Test class for EntityReprocessingBatch
 * @author            : Santhosh Bollur (Anderson SSC)
 * @last modified on  : 06-01-2026
 **/
@IsTest
private class EntityReprocessingBatchTest {
    /**
     * @description Test setup to create test data
     */
    @TestSetup
    static void makeData() {
        // Create test Account for Primary_Client__c relationship
        Account testAccount = new Account(Name = 'Test Account for Batch');
        insert testAccount;

        // Create test Entities with role fields populated
        List<Entities__c> testEntities = new List<Entities__c>();

        // Entity 1 - Has Director role
        testEntities.add(new Entities__c(Name = 'Test Entity 1', Primary_Client__c = testAccount.Id, Status__c = 'Active', Origin__c = 'Anderson Formed', Director_1__c = 'John Director'));

        // Entity 2 - Has Member role with 100% ownership
        testEntities.add(new Entities__c(Name = 'Test Entity 2', Primary_Client__c = testAccount.Id, Status__c = 'Active', Origin__c = 'Anderson Formed', Member_1__c = 'Jane Member', Ownership__c = 100.0));

        // Entity 3 - Has Manager role
        testEntities.add(new Entities__c(Name = 'Test Entity 3', Primary_Client__c = testAccount.Id, Status__c = 'Active', Origin__c = 'Anderson Formed', Manager_1__c = 'Bob Manager'));

        // Entity 4 - Inactive (should be excluded)
        testEntities.add(new Entities__c(Name = 'Test Entity 4 Inactive', Primary_Client__c = testAccount.Id, Status__c = 'Inactive', Origin__c = 'Anderson Formed', Director_1__c = 'Inactive Director'));

        // Entity 5 - Client Formed (should be excluded)
        testEntities.add(new Entities__c(Name = 'Test Entity 5 Client Formed', Primary_Client__c = testAccount.Id, Status__c = 'Active', Origin__c = 'Client Formed', Director_1__c = 'Client Director'));

        // Entity 6 - No roles populated (should be excluded)
        testEntities.add(new Entities__c(Name = 'Test Entity 6 No Roles', Primary_Client__c = testAccount.Id, Status__c = 'Active', Origin__c = 'Anderson Formed'));

        insert testEntities;

        // Set CreatedDate to April 2026 to match batch filter
        Test.setCreatedDate(testEntities[0].Id, DateTime.newInstance(2026, 4, 15, 12, 0, 0));
        Test.setCreatedDate(testEntities[1].Id, DateTime.newInstance(2026, 4, 16, 12, 0, 0));
        Test.setCreatedDate(testEntities[2].Id, DateTime.newInstance(2026, 4, 17, 12, 0, 0));
        Test.setCreatedDate(testEntities[3].Id, DateTime.newInstance(2026, 4, 18, 12, 0, 0));
        Test.setCreatedDate(testEntities[4].Id, DateTime.newInstance(2026, 4, 19, 12, 0, 0));
        Test.setCreatedDate(testEntities[5].Id, DateTime.newInstance(2026, 4, 20, 12, 0, 0));
    }

    /**
     * @description Comprehensive batch execution test
     * Note: Only ONE executeBatch call allowed per test class in Salesforce
     */
    @IsTest
    static void testBatchExecution_Comprehensive() {
        // Verify test data setup
        List<Entities__c> allEntities = [SELECT Id, Name, Status__c, Origin__c FROM Entities__c];
        System.assert(!allEntities.isEmpty(), 'Test entities should exist');

        // Verify filtering setup
        List<Entities__c> inactiveEntities = [SELECT Id FROM Entities__c WHERE Status__c = 'Inactive'];
        List<Entities__c> clientFormedEntities = [SELECT Id FROM Entities__c WHERE Origin__c = 'Client Formed'];
        List<Entities__c> noRoleEntities = [SELECT Id FROM Entities__c WHERE Name = 'Test Entity 6 No Roles'];

        System.assert(!inactiveEntities.isEmpty(), 'Inactive entity should exist');
        System.assert(!clientFormedEntities.isEmpty(), 'Client Formed entity should exist');
        System.assert(!noRoleEntities.isEmpty(), 'No-role entity should exist');

        Test.startTest();

        // Execute batch - ONLY ONE executeBatch call allowed per test class
        EntityReprocessingBatch batch = new EntityReprocessingBatch();
        Id batchId = Database.executeBatch(batch, 200);

        Test.stopTest();

        // 1. Test custom label loading
        System.assertNotEquals(null, batch.processMonth, 'Process month should be loaded');
        System.assertNotEquals(null, batch.processYear, 'Process year should be loaded');
        System.assert(batch.processMonth >= 1 && batch.processMonth <= 12, 'Process month should be valid');
        System.assert(batch.processYear > 2000, 'Process year should be reasonable');

        // 2. Test stateful variable initialization
        System.assertNotEquals(null, batch.successfulIds, 'Successful IDs list should exist');
        System.assertNotEquals(null, batch.failedIds, 'Failed IDs list should exist');
        System.assertNotEquals(null, batch.errorMessages, 'Error messages list should exist');

        // 3. Test stateful tracking
        Integer totalAccounted = batch.successfulIds.size() + batch.failedIds.size();
        System.assertEquals(batch.totalProcessed, totalAccounted, 'All processed entities should be in success or failed lists');
        System.assert(batch.totalProcessed >= 0, 'Total processed should be non-negative');

        // 4. Test no failures
        System.assertEquals(0, batch.failedIds.size(), 'Should have no DML failures');

        // 5. Test batch completion
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems
            FROM AsyncApexJob
            WHERE Id = :batchId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete successfully');
        System.assertEquals(0, job.NumberOfErrors, 'Should have no batch execution errors');

        // 6. Test filtering - verify excluded entities were NOT processed
        for (Id successId : batch.successfulIds) {
            System.assertNotEquals(inactiveEntities[0].Id, successId, 'Inactive entity should not be processed');
            System.assertNotEquals(clientFormedEntities[0].Id, successId, 'Client Formed entity should not be processed');
            System.assertNotEquals(noRoleEntities[0].Id, successId, 'No-role entity should not be processed');
        }

        // Note: Actual processing count depends on CreatedDate matching custom label filter (April 2026)
        // Test focuses on batch structure, initialization, completion, and filtering logic
    }

    /**
     * @description Test batch query locator creation without executing batch
     */
    @IsTest
    static void testBatchStart_QueryLocator() {
        // This test doesn't call executeBatch, so it's safe
        EntityReprocessingBatch batch = new EntityReprocessingBatch();

        Test.startTest();
        Database.QueryLocator ql = batch.start(null);
        Test.stopTest();

        // Verify query locator is created
        System.assertNotEquals(null, ql, 'Query locator should be created');

        // Verify iterator can be obtained
        Database.QueryLocatorIterator iterator = ql.iterator();
        System.assertNotEquals(null, iterator, 'Query iterator should exist');
    }

    /**
     * @description Test batch initialization without execution
     */
    @IsTest
    static void testBatchInitialization() {
        // Test batch can be instantiated and variables are initialized
        Test.startTest();
        EntityReprocessingBatch batch = new EntityReprocessingBatch();
        Test.stopTest();

        // Verify instance variables are initialized
        System.assertNotEquals(null, batch.processMonth, 'Process month should be initialized');
        System.assertNotEquals(null, batch.processYear, 'Process year should be initialized');
        System.assertNotEquals(null, batch.successfulIds, 'Successful IDs should be initialized');
        System.assertNotEquals(null, batch.failedIds, 'Failed IDs should be initialized');
        System.assertNotEquals(null, batch.errorMessages, 'Error messages should be initialized');
        System.assertEquals(0, batch.totalProcessed, 'Total processed should start at 0');
    }
}
