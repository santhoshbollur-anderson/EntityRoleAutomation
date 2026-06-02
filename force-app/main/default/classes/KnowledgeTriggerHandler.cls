/**
 * @description       :
 * @author            :  Santhosh Bollur (Anderson SSC)
 * @group             :
 * @last modified on  : 05-06-2026
 * @last modified by  :  Santhosh Bollur (Anderson SSC)
 **/
public with sharing class KnowledgeTriggerHandler {
   // Method to handle Before Update context
   public void beforeUpdate(List<Knowledge__kav> newList, Map<Id, Knowledge__kav> oldMap) {
      // Call the helper method for checking rejection comments
      KnowledgeTriggerHelper.requireRejectionComments(newList, oldMap);

      // You can add other beforeUpdate helper methods here in the future
   }
}