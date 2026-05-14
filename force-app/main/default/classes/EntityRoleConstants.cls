/**
 * @description       : Central constants repository for Entity Role automation. Contains all string literals, 
 *                      field API names, error messages, and DML error codes used throughout the Entity Role 
 *                      automation process to ensure consistency and maintainability.
 * @author            : Santhosh Bollur (Anderson SSC)
 * @group             : 
 * @last modified on  : 05-14-2026
 * @last modified by  :  Santhosh Bollur (Anderson SSC)
**/
public with sharing class EntityRoleConstants {
    // Entity Role Status Values
    public static final String STATUS_ACTIVE = 'Active';
    public static final String STATUS_INACTIVE = 'Inactive';

    // Record Type Developer Names
    public static final String RT_CONTACT_STANDARD = 'Standard';
    public static final String RT_LLC = 'Limited_Liability_Company_LLC';
    public static final String RT_CORPORATION = 'Corporation';
    public static final String RT_LIMITED_PARTNERSHIP = 'Limited_Partnership_LP';

    // Error Messages
    public static final String ERROR_ENTITY_ROLE_AUTOMATION = 'Entity Role Automation Failed: ';
    public static final String ERROR_INVALID_PICKLIST = 'One of the State values entered is not valid for the "State of Residence" picklist. Please ensure you are using standard State abbreviations or names defined in Salesforce.';
    public static final String ERROR_REQUIRED_FIELD = 'A required field is missing. Please check that all Name and Role fields are populated.';

    // DML Error Codes
    public static final String DML_ERROR_INVALID_PICKLIST = 'INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST';
    public static final String DML_ERROR_REQUIRED_FIELD = 'REQUIRED_FIELD_MISSING';
}
