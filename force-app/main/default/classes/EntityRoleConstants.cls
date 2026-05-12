/**
 * @description       : Constants class for Entity Role automation
 * @author            : Santhosh Bollur (Anderson SSC)
 * @group             : 
 * @last modified on  : 05-12-2026
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
}