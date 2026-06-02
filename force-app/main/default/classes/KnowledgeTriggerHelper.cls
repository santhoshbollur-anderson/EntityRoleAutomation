/**
 * @description       :
 * @author            :  Santhosh Bollur (Anderson SSC)
 * @group             :
 * @last modified on  : 05-06-2026
 * @last modified by  :  Santhosh Bollur (Anderson SSC)
 **/
public with sharing class KnowledgeTriggerHelper {
   /**
    * Enforces that a comment is provided when an article is rejected in an Approval Process.
    */
   public static void requireRejectionComments(List<Knowledge__kav> newList, Map<Id, Knowledge__kav> oldMap) {
      // 1. Create a map to hold the records that are being rejected
      Map<Id, Knowledge__kav> rejectedRecords = new Map<Id, Knowledge__kav>();

      for (Knowledge__kav article : newList) {
         // Check if the status is changing to 'Rejected'
         Knowledge__kav oldArticle = oldMap.get(article.Id);
         if (article.Stage__c == 'Rejected' && oldArticle.Stage__c != 'Rejected') {
            rejectedRecords.put(article.Id, article);
         }
      }

      // 2. If we have rejected records, check the Approval Process comments
      if (!rejectedRecords.isEmpty()) {
         // Query the most recent approval step for these records
         List<ProcessInstance> processInstances = [
            SELECT
               TargetObjectId,
               (
                  SELECT Id, StepStatus, Comments
                  FROM Steps
                  WHERE StepStatus = 'Rejected'
                  ORDER BY CreatedDate DESC
                  LIMIT 1
               )
            FROM ProcessInstance
            WHERE TargetObjectId IN :rejectedRecords.keySet()
            ORDER BY CreatedDate DESC
         ];

         // 3. Loop through the results and throw an error if comments are blank
         for (ProcessInstance pi : processInstances) {
            if (!pi.Steps.isEmpty()) {
               ProcessInstanceStep lastStep = pi.Steps[0];

               // If the comment is null or only contains whitespace
               if (String.isBlank(lastStep.Comments)) {
                  // This error will pop up on the user's screen, blocking the rejection
                  Knowledge__kav rejectedArticle = rejectedRecords.get(pi.TargetObjectId);

                  // Error message pulled dynamically from Custom Labels
                  rejectedArticle.addError(System.Label.Knowledge_article_rejected_error_message);
               }
            }
         }
      }
   }
}