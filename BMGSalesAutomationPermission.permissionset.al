namespace BMG_SalesAutomationPermission;

permissionset 68800 BMG_SalesAutomation
{
    Assignable = true;
    Permissions = codeunit BMGPopulateOpenStatement = X,
        codeunit "BMG LSC Statement-Calculate" = X,
        codeunit "BMG LSC Statement-Post" = X,
        codeunit BMGClearOpenStatement = X,
        codeunit BMGPOSStatementUtility = X,
        codeunit BMGItemReclassMgt = X,
        codeunit BMGPostBulkOpenStatement = X;
}