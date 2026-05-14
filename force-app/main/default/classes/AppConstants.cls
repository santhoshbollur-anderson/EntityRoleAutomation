/**
 * @description       : Org-wide constants repository. Contains all string literals, field API names, 
 *                      error messages, DML error codes, and record type developer names used throughout 
 *                      the organization to ensure consistency and maintainability.
 * @author            : Santhosh Bollur (Anderson SSC)
 * @group             : Core
 * @last modified on  : 05-14-2026
 * @last modified by  :  Santhosh Bollur (Anderson SSC)
**/
public with sharing class AppConstants {
    
    // ========================================
    // GENERAL STATUS VALUES
    // ========================================
    public static final String STATUS_ACTIVE = 'Active';
    public static final String STATUS_INACTIVE = 'Inactive';
    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_PENDING = 'Pending';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_REJECTED = 'Rejected';
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String STATUS_CANCELLED = 'Cancelled';
    
    // ========================================
    // RECORD TYPE DEVELOPER NAMES - CONTACT
    // ========================================
    public static final String RT_CONTACT_STANDARD = 'Standard';
    
    // ========================================
    // RECORD TYPE DEVELOPER NAMES - ENTITY
    // ========================================
    public static final String RT_ENTITY_LLC = 'Limited_Liability_Company_LLC';
    public static final String RT_ENTITY_CORPORATION = 'Corporation';
    public static final String RT_ENTITY_LIMITED_PARTNERSHIP = 'Limited_Partnership_LP';
    
    // ========================================
    // DML ERROR CODES (Salesforce Standard)
    // ========================================
    public static final String DML_ERROR_INVALID_PICKLIST = 'INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST';
    public static final String DML_ERROR_REQUIRED_FIELD = 'REQUIRED_FIELD_MISSING';
    public static final String DML_ERROR_DUPLICATE_VALUE = 'DUPLICATE_VALUE';
    public static final String DML_ERROR_FIELD_CUSTOM_VALIDATION = 'FIELD_CUSTOM_VALIDATION_EXCEPTION';
    public static final String DML_ERROR_UNABLE_TO_LOCK_ROW = 'UNABLE_TO_LOCK_ROW';
    public static final String DML_ERROR_INSUFFICIENT_ACCESS = 'INSUFFICIENT_ACCESS_OR_READONLY';
    
    // ========================================
    // ERROR MESSAGE PREFIXES
    // ========================================
    public static final String ERROR_PREFIX_AUTOMATION = 'Automation Failed: ';
    public static final String ERROR_PREFIX_VALIDATION = 'Validation Error: ';
    public static final String ERROR_PREFIX_SYSTEM = 'System Error: ';
    
    // ========================================
    // ENTITY ROLE AUTOMATION - SPECIFIC ERRORS
    // ========================================
    public static final String ERROR_ENTITY_ROLE_AUTOMATION = 'Entity Role Automation Failed: ';
    public static final String ERROR_INVALID_PICKLIST = 'One of the State values entered is not valid for the "State of Residence" picklist. Please ensure you are using standard State abbreviations or names defined in Salesforce.';
    public static final String ERROR_REQUIRED_FIELD = 'A required field is missing. Please check that all Name and Role fields are populated.';
    
    // ========================================
    // COMMON FIELD API NAMES
    // ========================================
    public static final String FIELD_NAME = 'Name';
    public static final String FIELD_STATUS = 'Status__c';
    public static final String FIELD_CREATED_DATE = 'CreatedDate';
    public static final String FIELD_LAST_MODIFIED_DATE = 'LastModifiedDate';
    public static final String FIELD_OWNER_ID = 'OwnerId';
    
    // ========================================
    // DATE & TIME FORMATS
    // ========================================
    public static final String DATE_FORMAT_STANDARD = 'yyyy-MM-dd';
    public static final String DATETIME_FORMAT_STANDARD = 'yyyy-MM-dd HH:mm:ss';
    public static final String TIME_FORMAT_STANDARD = 'HH:mm:ss';
    
    // ========================================
    // QUERY LIMITS
    // ========================================
    public static final Integer QUERY_LIMIT_DEFAULT = 200;
    public static final Integer QUERY_LIMIT_SMALL = 50;
    public static final Integer QUERY_LIMIT_LARGE = 2000;
    
    // ========================================
    // BATCH SIZES
    // ========================================
    public static final Integer BATCH_SIZE_DEFAULT = 200;
    public static final Integer BATCH_SIZE_SMALL = 50;
    public static final Integer BATCH_SIZE_LARGE = 2000;
    
    // ========================================
    // HELPER METHODS
    // ========================================
    
    /**
     * @description Prevents instantiation of this constants class
     */
    private AppConstants() {
        throw new IllegalArgumentException('Constants class cannot be instantiated');
    }
}