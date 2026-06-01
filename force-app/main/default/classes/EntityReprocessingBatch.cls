/**
 * @description       :
 * @author            :  Santhosh Bollur (Anderson SSC)
 * @group             :
 * @last modified on  : 06-01-2026
 * @last modified by  :  Santhosh Bollur (Anderson SSC)
 **/
public class EntityReprocessingBatch implements Database.Batchable<sObject>, Database.Stateful {
    // Track overall processing numbers
    public Integer totalProcessed = 0;

    // Tracking lists for exact IDs and errors
    public List<Id> successfulIds = new List<Id>();
    public List<Id> failedIds = new List<Id>();
    public List<String> errorMessages = new List<String>();

    // Fetch the Month and Year from Custom Labels and convert them to Integers
    public Integer processMonth = Integer.valueOf(System.Label.Batch_Process_Month);
    public Integer processYear = Integer.valueOf(System.Label.Batch_Process_Year);

    // 1. START: Query using dynamic Custom Labels instead of hardcoded dates
    public Database.QueryLocator start(Database.BatchableContext bc) {
        String query =
            'SELECT Id, Name FROM Entities__c ' +
            'WHERE CALENDAR_MONTH(CreatedDate) = :processMonth ' +
            'AND CALENDAR_YEAR(CreatedDate) = :processYear ' +
            'AND Status__c != \'Inactive\' ' +
            'AND Origin__c != \'Client Formed\' ' +
            'AND (Director_1__c != NULL OR Director_2__c != NULL OR Director_3__c != NULL OR ' +
            'Director_4__c != NULL OR Director_5__c != NULL OR Director_6__c != NULL OR ' +
            'Limited_Partner_1__c != NULL OR Limited_Partner_2__c != NULL OR ' +
            'Limited_Partner_3__c != NULL OR Limited_Partner_4__c != NULL OR ' +
            'Manager_1__c != NULL OR Manager_2__c != NULL OR Manager_3__c != NULL OR ' +
            'Manager_4__c != NULL OR Manager_5__c != NULL OR ' +
            'Member_1__c != NULL OR Member_2__c != NULL OR Member_3__c != NULL OR ' +
            'Member_4__c != NULL OR Member_5__c != NULL OR ' +
            'President__c != NULL OR Secretary__c != NULL OR Treasurer__c != NULL OR ' +
            'Vice_President__c != NULL OR ' +
            'Share_Holder_1__c != NULL OR Share_Holder_2__c != NULL OR ' +
            'Share_Holder_3__c != NULL OR Share_Holder_4__c != NULL)';
        return Database.getQueryLocator(query);
    }

    // 2. EXECUTE: Process in chunks
    public void execute(Database.BatchableContext bc, List<Entities__c> scope) {
        totalProcessed += scope.size();

        Database.SaveResult[] results = Database.update(scope, false);

        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                successfulIds.add(scope[i].Id);
            } else {
                failedIds.add(scope[i].Id);
                for (Database.Error err : results[i].getErrors()) {
                    errorMessages.add('Failed ID: ' + scope[i].Id + ' | Error: ' + err.getMessage());
                }
            }
        }
    }

    // 3. FINISH: Send the dynamically formatted email
    public void finish(Database.BatchableContext bc) {
        // Map the numeric month (e.g., 4) to the Month Name (e.g., 'April') for the email subject
        Map<Integer, String> monthMap = new Map<Integer, String>{ 1 => 'January', 2 => 'February', 3 => 'March', 4 => 'April', 5 => 'May', 6 => 'June', 7 => 'July', 8 => 'August', 9 => 'September', 10 => 'October', 11 => 'November', 12 => 'December' };
        String monthName = monthMap.containsKey(processMonth) ? monthMap.get(processMonth) : String.valueOf(processMonth);

        // Prepare the email addresses
        String emailLabel = System.Label.Batch_Admin_Emails;
        List<String> toAddresses = new List<String>();

        if (String.isNotBlank(emailLabel)) {
            for (String email : emailLabel.split(',')) {
                toAddresses.add(email.trim());
            }
        }

        // Send the Email
        if (!toAddresses.isEmpty()) {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(toAddresses);

            // DYNAMIC SUBJECT LINE: e.g., "Salesforce Batch Complete: Entity Reprocessing for April 2026"
            mail.setSubject('Salesforce Batch Complete: Entity Reprocessing for ' + monthName + ' ' + processYear);

            String body = 'The Entity Reprocessing Batch for ' + monthName + ' ' + processYear + ' has finished running.\n\n' + 'Total Processed: ' + totalProcessed + '\n' + 'Total Successes: ' + successfulIds.size() + '\n' + 'Total Failures: ' + failedIds.size() + '\n\n';

            body += '--- SUCCESSFUL RECORD IDs ---\n';
            if (!successfulIds.isEmpty()) {
                body += String.join(successfulIds, '\n') + '\n\n';
            } else {
                body += 'None\n\n';
            }

            body += '--- FAILED RECORD IDs & ERRORS ---\n';
            if (!errorMessages.isEmpty()) {
                body += String.join(errorMessages, '\n');
            } else {
                body += 'None! Everything processed flawlessly.';
            }

            mail.setPlainTextBody(body);
            
            // Wrap email sending in try-catch to handle test context permission issues
            try {
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            } catch (System.EmailException e) {
                // Log the error but don't fail the batch
                System.debug('⚠️ Email sending failed: ' + e.getMessage());
                // In test context, this is expected due to NO_SINGLE_MAIL_PERMISSION
                if (!Test.isRunningTest()) {
                    // In production, we might want to handle this differently
                    System.debug('⚠️ Production email failure - please check email permissions');
                }
            }
        } else {
            System.debug('⚠️ Skipping email delivery: Custom Label "Batch_Admin_Emails" is empty.');
        }
    }
}
