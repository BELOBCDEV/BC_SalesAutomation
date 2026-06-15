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
        codeunit BMGPostBulkOpenStatement = X,
        codeunit BMGMondayDotComMgt = X,
        tabledata BMGMondayTickets = RIMD,
        table BMGMondayTickets = X,
        page BMGMondayTickets = X,
        codeunit SendMondayTickets = X,
        page BMGMondayTicketList = X,
        codeunit "BMG CO Prepay. Inv. Mgt Public" = X,
        codeunit "BMG CO Prepayment Invoice Mgt" = X,
        query "BMG Statement Post Discounts" = X,
        codeunit "BMG Transaction FreeText Utils" = X;
}