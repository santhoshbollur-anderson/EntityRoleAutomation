/**
 * @description       :
 * @author            :  Santhosh Bollur (Anderson SSC)
 * @group             :
 * @last modified on  : 05-05-2026
 * @last modified by  :  Santhosh Bollur (Anderson SSC)
 **/
trigger KnowledgeTrigger on Knowledge__kav(before update) {
   // Instantiate the handler
   KnowledgeTriggerHandler handler = new KnowledgeTriggerHandler();

   // Route to the appropriate context
   if (Trigger.isBefore && Trigger.isUpdate) {
      handler.beforeUpdate(Trigger.new, Trigger.oldMap);
   }

   // Future contexts (afterUpdate, beforeInsert, etc.) can be added here later

}